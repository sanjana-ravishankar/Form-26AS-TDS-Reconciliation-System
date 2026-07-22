from google.cloud import bigquery
import os

client = bigquery.Client.from_service_account_json('bq_service_account.json')
project = "eternal-skyline-468312-g7"
dataset = "tds_reconciliation"

schemas = {
    "cust_master": [
        bigquery.SchemaField("cust_id", "INTEGER"),
        bigquery.SchemaField("cust_code", "STRING"),
        bigquery.SchemaField("cust_name", "STRING"),
        bigquery.SchemaField("pan_number", "STRING"),
        bigquery.SchemaField("gstin_number", "STRING"),
        bigquery.SchemaField("tan_number", "STRING"),
        bigquery.SchemaField("cust_status", "STRING"),
    ],
    "income_records": [
        bigquery.SchemaField("income_id", "INTEGER"),
        bigquery.SchemaField("upload_ref", "STRING"),
        bigquery.SchemaField("fin_year", "STRING"),
        bigquery.SchemaField("cust_id", "INTEGER"),
        bigquery.SchemaField("cust_code", "STRING"),
        bigquery.SchemaField("cust_name", "STRING"),
        bigquery.SchemaField("pan_number", "STRING"),
        bigquery.SchemaField("tan_number", "STRING"),
        bigquery.SchemaField("doc_number", "STRING"),
        bigquery.SchemaField("doc_date", "STRING"),
        bigquery.SchemaField("doc_type", "STRING"),
        bigquery.SchemaField("taxable_amt", "FLOAT"),
        bigquery.SchemaField("tax_amt", "FLOAT"),
        bigquery.SchemaField("gross_amt", "FLOAT"),
        bigquery.SchemaField("tds_section", "STRING"),
        bigquery.SchemaField("tds_rate", "FLOAT"),
        bigquery.SchemaField("tds_deductible", "FLOAT"),
        bigquery.SchemaField("entry_source", "STRING"),
    ],
    "form26as_records": [
        bigquery.SchemaField("record_id", "INTEGER"),
        bigquery.SchemaField("fin_year", "STRING"),
        bigquery.SchemaField("tan_of_deductor", "STRING"),
        bigquery.SchemaField("deductor_name", "STRING"),
        bigquery.SchemaField("section_code", "STRING"),
        bigquery.SchemaField("transaction_date", "STRING"),
        bigquery.SchemaField("booking_amt", "FLOAT"),
        bigquery.SchemaField("tds_credited", "FLOAT"),
        bigquery.SchemaField("cust_code", "STRING"),
        bigquery.SchemaField("cust_name", "STRING"),
    ],
    "tds_summary": [
        bigquery.SchemaField("cust_id", "INTEGER"),
        bigquery.SchemaField("cust_code", "STRING"),
        bigquery.SchemaField("cust_name", "STRING"),
        bigquery.SchemaField("pan_number", "STRING"),
        bigquery.SchemaField("tan_number", "STRING"),
        bigquery.SchemaField("fin_year", "STRING"),
        bigquery.SchemaField("total_taxable_amt", "FLOAT"),
        bigquery.SchemaField("total_tds_deductible", "FLOAT"),
        bigquery.SchemaField("total_gross_amt", "FLOAT"),
        bigquery.SchemaField("total_26as_credit", "FLOAT"),
        bigquery.SchemaField("variance_amt", "FLOAT"),
        bigquery.SchemaField("pct_credit", "FLOAT"),
        bigquery.SchemaField("invoice_count", "INTEGER"),
    ],
    "audit_logs": [
        bigquery.SchemaField("log_id",       "INTEGER"),
        bigquery.SchemaField("action_type",  "STRING"),
        bigquery.SchemaField("module_name",  "STRING"),
        bigquery.SchemaField("description",  "STRING"),
        bigquery.SchemaField("severity",     "STRING"),
        bigquery.SchemaField("user_name",    "STRING"),
        bigquery.SchemaField("ip_address",   "STRING"),
        bigquery.SchemaField("created_at",   "STRING"),
    ],
    # Staging tables used by bq_incremental_sync.py MERGE pattern
    # These are transient — wiped and reloaded on every incremental run
    "income_records_staging": [
        bigquery.SchemaField("income_id",      "INTEGER"),
        bigquery.SchemaField("upload_ref",     "STRING"),
        bigquery.SchemaField("fin_year",       "STRING"),
        bigquery.SchemaField("cust_id",        "INTEGER"),
        bigquery.SchemaField("cust_code",      "STRING"),
        bigquery.SchemaField("cust_name",      "STRING"),
        bigquery.SchemaField("pan_number",     "STRING"),
        bigquery.SchemaField("tan_number",     "STRING"),
        bigquery.SchemaField("doc_number",     "STRING"),
        bigquery.SchemaField("doc_date",       "STRING"),
        bigquery.SchemaField("doc_type",       "STRING"),
        bigquery.SchemaField("taxable_amt",    "FLOAT"),
        bigquery.SchemaField("tax_amt",        "FLOAT"),
        bigquery.SchemaField("gross_amt",      "FLOAT"),
        bigquery.SchemaField("tds_section",    "STRING"),
        bigquery.SchemaField("tds_rate",       "FLOAT"),
        bigquery.SchemaField("tds_deductible", "FLOAT"),
        bigquery.SchemaField("entry_source",   "STRING"),
    ],
    "cust_master_staging": [
        bigquery.SchemaField("cust_id",       "INTEGER"),
        bigquery.SchemaField("cust_code",     "STRING"),
        bigquery.SchemaField("cust_name",     "STRING"),
        bigquery.SchemaField("pan_number",    "STRING"),
        bigquery.SchemaField("gstin_number",  "STRING"),
        bigquery.SchemaField("tan_number",    "STRING"),
        bigquery.SchemaField("cust_status",   "STRING"),
    ],
    "tds_summary_staging": [
        bigquery.SchemaField("cust_id",              "INTEGER"),
        bigquery.SchemaField("cust_code",            "STRING"),
        bigquery.SchemaField("cust_name",            "STRING"),
        bigquery.SchemaField("pan_number",           "STRING"),
        bigquery.SchemaField("tan_number",           "STRING"),
        bigquery.SchemaField("fin_year",             "STRING"),
        bigquery.SchemaField("total_taxable_amt",    "FLOAT"),
        bigquery.SchemaField("total_tds_deductible", "FLOAT"),
        bigquery.SchemaField("total_gross_amt",      "FLOAT"),
        bigquery.SchemaField("total_26as_credit",    "FLOAT"),
        bigquery.SchemaField("variance_amt",         "FLOAT"),
        bigquery.SchemaField("pct_credit",           "FLOAT"),
        bigquery.SchemaField("invoice_count",        "INTEGER"),
    ],
}

for table_name, schema in schemas.items():
    table_id = f"{project}.{dataset}.{table_name}"
    table = bigquery.Table(table_id, schema=schema)
    try:
        client.create_table(table)
        print(f"Created: {table_name}")
    except Exception as e:
        if "Already Exists" in str(e):
            print(f"Already exists: {table_name}")
        else:
            print(f"Error creating {table_name}: {e}")

print("Done.")
