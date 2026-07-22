import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions, GoogleCloudOptions, StandardOptions
from google.cloud import bigquery
import mysql.connector
from decimal import Decimal
import datetime
import os

# ── CONFIG ──────────────────────────────────────────────────────
MYSQL_HOST   = "127.0.0.1"        
MYSQL_PORT   = 3306
MYSQL_USER   = ""                
MYSQL_PASS   = ""                    
MYSQL_DB     = "form26as_db"         

GCP_PROJECT  = "eternal-skyline-468312-g7"
BQ_DATASET   = "tds_reconciliation"
GCS_BUCKET   = "gs://eternal-skyline-468312-g7-dataflow"
BQ_KEY       = "bq_service_account.json"  
# ────────────────────────────────────────────────────────────────

os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = BQ_KEY


def clean(val):
    """Convert MySQL types to BQ-safe Python types."""
    if val is None:
        return None
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, (datetime.date, datetime.datetime)):
        return str(val)
    if isinstance(val, (int, float, bool, str)):
        return val
    return str(val)


def read_mysql(query):
    """Read rows from MySQL and yield as dicts."""
    conn = mysql.connector.connect(
        host=MYSQL_HOST, port=MYSQL_PORT,
        user=MYSQL_USER, password=MYSQL_PASS,
        database=MYSQL_DB
    )
    cur = conn.cursor(dictionary=True)
    cur.execute(query)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [{k: clean(v) for k, v in row.items()} for row in rows]


class ReadMySQL(beam.DoFn):
    def __init__(self, query):
        self.query = query

    def process(self, element):
        for row in read_mysql(self.query):
            yield row


# ── QUERIES ─────────────────────────────────────────────────────
QUERIES = {
    "cust_master": """
        SELECT cust_id, cust_code, cust_name, pan_number,
               gstin_number, tan_number, cust_status
        FROM cust_master
    """,
    "income_records": """
        SELECT ir.income_id, ir.upload_ref, ir.fin_year, ir.cust_id,
               cm.cust_code, cm.cust_name, cm.pan_number, cm.tan_number,
               ir.doc_number, CAST(ir.doc_date AS CHAR) AS doc_date,
               ir.doc_type, ir.taxable_amt, ir.tax_amt, ir.gross_amt,
               ir.tds_section, ir.tds_rate, ir.tds_deductible, ir.entry_source
        FROM income_records ir
        JOIN cust_master cm ON ir.cust_id = cm.cust_id
    """,
    "form26as_records": """
        SELECT f.record_id, f.fin_year, f.tan_of_deductor, f.deductor_name,
               f.section_code, CAST(f.transaction_date AS CHAR) AS transaction_date,
               f.booking_amt, f.tds_credited,
               cm.cust_code, cm.cust_name
        FROM form26as_records f
        LEFT JOIN cust_master cm
            ON LOWER(TRIM(cm.tan_number)) = LOWER(TRIM(f.tan_of_deductor))
    """,
    "tds_summary": """
        SELECT c.cust_id, c.cust_code, c.cust_name, c.pan_number, c.tan_number,
               ir.fin_year,
               COALESCE(SUM(ir.taxable_amt), 0.00)    AS total_taxable_amt,
               COALESCE(SUM(ir.tds_deductible), 0.00) AS total_tds_deductible,
               COALESCE(SUM(ir.gross_amt), 0.00)      AS total_gross_amt,
               COALESCE(f26.total_tds_credited, 0.00) AS total_26as_credit,
               COALESCE(SUM(ir.tds_deductible), 0.00)
                   - COALESCE(f26.total_tds_credited, 0.00) AS variance_amt,
               CASE WHEN COALESCE(SUM(ir.tds_deductible), 0) = 0 THEN 0.00
                    ELSE ROUND(COALESCE(f26.total_tds_credited, 0.00)
                         / COALESCE(SUM(ir.tds_deductible), 0.00) * 100, 2)
               END AS pct_credit,
               COUNT(ir.income_id) AS invoice_count
        FROM cust_master c
        LEFT JOIN income_records ir ON c.cust_id = ir.cust_id
        LEFT JOIN (
            SELECT LOWER(TRIM(tan_of_deductor)) AS tan, fin_year,
                   SUM(tds_credited) AS total_tds_credited
            FROM form26as_records
            GROUP BY LOWER(TRIM(tan_of_deductor)), fin_year
        ) f26 ON LOWER(TRIM(c.tan_number)) = f26.tan
              AND ir.fin_year = f26.fin_year
        WHERE ir.fin_year IS NOT NULL
        GROUP BY c.cust_id, c.cust_code, c.cust_name, c.pan_number,
                 c.tan_number, ir.fin_year, f26.total_tds_credited
    """,
}

# ── BQ SCHEMAS ──────────────────────────────────────────────────
BQ_SCHEMAS = {
    "cust_master":
        "cust_id:INTEGER,cust_code:STRING,cust_name:STRING,"
        "pan_number:STRING,gstin_number:STRING,tan_number:STRING,cust_status:STRING",
    "income_records":
        "income_id:INTEGER,upload_ref:STRING,fin_year:STRING,cust_id:INTEGER,"
        "cust_code:STRING,cust_name:STRING,pan_number:STRING,tan_number:STRING,"
        "doc_number:STRING,doc_date:STRING,doc_type:STRING,taxable_amt:FLOAT,"
        "tax_amt:FLOAT,gross_amt:FLOAT,tds_section:STRING,tds_rate:FLOAT,tds_deductible:FLOAT,entry_source:STRING",
    "form26as_records":
        "record_id:INTEGER,fin_year:STRING,tan_of_deductor:STRING,deductor_name:STRING,"
        "section_code:STRING,transaction_date:STRING,booking_amt:FLOAT,tds_credited:FLOAT,"
        "cust_code:STRING,cust_name:STRING",
    "tds_summary":
        "cust_id:INTEGER,cust_code:STRING,cust_name:STRING,pan_number:STRING,"
        "tan_number:STRING,fin_year:STRING,total_taxable_amt:FLOAT,"
        "total_tds_deductible:FLOAT,total_gross_amt:FLOAT,total_26as_credit:FLOAT,"
        "variance_amt:FLOAT,pct_credit:FLOAT,invoice_count:INTEGER",
}


def run():
    options = PipelineOptions()
    options.view_as(StandardOptions).runner = "DirectRunner"
    gcp_options = options.view_as(GoogleCloudOptions)
    gcp_options.project = GCP_PROJECT
    gcp_options.temp_location = f"{GCS_BUCKET}/temp"

    print("\n[Dataflow] Initializing Unified Pipeline graph execution context...")
    
    # FIX: Open ONE pipeline scope, construct parallel branches inside it
    with beam.Pipeline(options=options) as p:
        for table_name, query in QUERIES.items():
            bq_table = f"{GCP_PROJECT}:{BQ_DATASET}.{table_name}"
            print(f" -> Constructing transform branch for: {table_name}")

            (
                p
                | f"Start_{table_name}"    >> beam.Create([None])
                | f"ReadMySQL_{table_name}" >> beam.ParDo(ReadMySQL(query))
                | f"WriteBQ_{table_name}"  >> beam.io.WriteToBigQuery(
                    bq_table,
                    schema=BQ_SCHEMAS[table_name],
                    write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
                    custom_gcs_temp_location=f"{GCS_BUCKET}/temp",
                )
            )

    print("\n[Dataflow] All tables synced to BigQuery successfully.")


if __name__ == "__main__":
    run()

