"""
bq_incremental_sync.py
──────────────────────────────────────────────────────────────────────────────
Incremental MySQL → BigQuery sync for Form 26AS TDS Reconciliation System.
Sundaram Finance Limited — Data Platform

STRATEGY
────────
Instead of TRUNCATE + full reload, this script:
  1. Reads a watermark timestamp per table from bq_sync_watermark (MySQL table)
  2. Fetches only rows created/updated AFTER the watermark
  3. Appends to BigQuery using WRITE_APPEND
  4. For updates [example: New customers → APPEND, changed customers → staging → MERGE delta only]
  5. Updates the watermark after successful sync

TABLES SYNCED
─────────────
  income_records    — new invoices + updated tds_deductible rows
  form26as_records  — new 26AS uploads
  cust_master       — new/updated customers
  audit_logs        — append-only, never updated (pure incremental)
  tds_summary       — recomputed snapshot (always full for FY, not incremental)

HOW TO RUN
──────────
python bq_incremental_sync.py
  

FIRST-TIME SETUP
────────────────
  1. Run bq_full_sync.py once to populate BQ with existing data
  2. Run this script — it will create bq_sync_watermark table in MySQL
  3. Schedule airflow_dag.py to run this nightly

DEPENDENCIES
────────────
  pip install google-cloud-bigquery mysql-connector-python python-dotenv
"""

import os
import json
from datetime import datetime, timezone
from dotenv import load_dotenv
from google.cloud import bigquery
import mysql.connector

load_dotenv()

# ── Config ─────────────────────────────────────────────────────────────────
BQ_KEY      = os.getenv('BQ_KEY_PATH', 'bq_service_account.json')
BQ_PROJECT  = os.getenv('BQ_PROJECT',  'eternal-skyline-468312-g7')
BQ_DATASET  = os.getenv('BQ_DATASET',  'tds_reconciliation')
MYSQL_HOST  = os.getenv('DB_HOST',     'localhost')
MYSQL_PORT  = int(os.getenv('DB_PORT', '3306'))
MYSQL_USER  = os.getenv('DB_USER',     '')
MYSQL_PASS  = os.getenv('DB_PASSWORD', '')
MYSQL_DB    = os.getenv('DB_NAME',     'form26as_db')
BATCH_SIZE  = 500   # BQ streaming insert limit per request
# ───────────────────────────────────────────────────────────────────────────


def get_mysql():
    return mysql.connector.connect(
        host=MYSQL_HOST, port=MYSQL_PORT,
        user=MYSQL_USER, password=MYSQL_PASS,
        database=MYSQL_DB, charset='utf8mb4'
    )


def get_bq():
    return bigquery.Client.from_service_account_json(BQ_KEY)


# ── Watermark helpers ───────────────────────────────────────────────────────

WATERMARK_DDL = """
CREATE TABLE IF NOT EXISTS bq_sync_watermark (
    table_name      VARCHAR(100) NOT NULL PRIMARY KEY,
    last_synced_at  DATETIME     NOT NULL DEFAULT '2000-01-01 00:00:00',
    last_row_count  INT          NOT NULL DEFAULT 0,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"""

def ensure_watermark_table(conn):
    """Create bq_sync_watermark if it doesn't exist."""
    cur = conn.cursor()
    cur.execute(WATERMARK_DDL)
    conn.commit()
    cur.close()


def get_watermark(conn, table_name):
    """Return last_synced_at for the table, or epoch if never synced."""
    cur = conn.cursor(dictionary=True)
    cur.execute(
        "SELECT last_synced_at FROM bq_sync_watermark WHERE table_name = %s",
        (table_name,)
    )
    row = cur.fetchone()
    cur.close()
    if row:
        return row['last_synced_at']
    # First run — seed the watermark at epoch so all rows are picked up
    return datetime(2000, 1, 1, 0, 0, 0)


def set_watermark(conn, table_name, synced_at, row_count):
    """Upsert watermark after successful sync."""
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO bq_sync_watermark (table_name, last_synced_at, last_row_count)
        VALUES (%s, %s, %s)
        ON DUPLICATE KEY UPDATE
            last_synced_at = VALUES(last_synced_at),
            last_row_count = VALUES(last_row_count)
    """, (table_name, synced_at, row_count))
    conn.commit()
    cur.close()


# ── Type cleaner ────────────────────────────────────────────────────────────

def clean_rows(rows):
    """Convert MySQL types to BigQuery-safe JSON types."""
    clean = []
    for row in rows:
        clean_row = {}
        for k, v in row.items():
            if v is None:
                clean_row[k] = None
            elif isinstance(v, bool):
                clean_row[k] = v
            elif isinstance(v, int):
                clean_row[k] = v
            elif isinstance(v, float):
                clean_row[k] = v
            elif hasattr(v, '__float__'):   # Decimal
                clean_row[k] = float(v)
            elif hasattr(v, 'strftime'):
                # handles both date and datetime objects
                if hasattr(v, 'hour'):
                    clean_row[k] = v.strftime('%Y-%m-%d %H:%M:%S')
                else:
                    clean_row[k] = v.strftime('%Y-%m-%d')
            else:
                clean_row[k] = str(v)
        clean.append(clean_row)
    return clean


# ── BQ insert helper ────────────────────────────────────────────────────────

def bq_append(client, table_id, rows):
    """
    Append rows to a BigQuery table in batches.
    Uses WRITE_APPEND — never truncates.
    Returns total error count.
    """
    if not rows:
        return 0
    full_table = f'{BQ_PROJECT}.{BQ_DATASET}.{table_id}'
    total_errors = []
    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i:i + BATCH_SIZE]
        errs  = client.insert_rows_json(full_table, batch)
        total_errors.extend(errs)
    return len(total_errors)


def bq_merge_income_records(client, rows):
    """
    MERGE income_records in BigQuery using income_id as the key.
    This handles both new inserts AND updates to tds_deductible/tds_section
    from update_tds_deductible_from_section().

    Pattern: write to a temp staging table, then MERGE into the main table.
    """
    if not rows:
        return 0

    staging_table = f'{BQ_PROJECT}.{BQ_DATASET}.income_records_staging'
    main_table    = f'{BQ_PROJECT}.{BQ_DATASET}.income_records'

    # Step 1 — Write to staging (WRITE_TRUNCATE clears stale staging data)
    # Serialise through json first to ensure date/Decimal types are converted
    import json, datetime as _dt, decimal as _dec
    def _serial(o):
        if isinstance(o, _dt.datetime): return o.strftime('%Y-%m-%d %H:%M:%S')
        if isinstance(o, _dt.date):     return o.strftime('%Y-%m-%d')
        if isinstance(o, _dec.Decimal): return float(o)
        raise TypeError(f'Object of type {type(o)} is not JSON serialisable')
    safe_rows = json.loads(json.dumps(rows, default=_serial))
    # Explicit schema prevents BQ from autodetecting doc_date as DATE
    # (main table has it as STRING — must match for MERGE to work)
    staging_schema = [
        bigquery.SchemaField('income_id',      'INTEGER'),
        bigquery.SchemaField('upload_ref',     'STRING'),
        bigquery.SchemaField('fin_year',       'STRING'),
        bigquery.SchemaField('cust_id',        'INTEGER'),
        bigquery.SchemaField('cust_code',      'STRING'),
        bigquery.SchemaField('cust_name',      'STRING'),
        bigquery.SchemaField('pan_number',     'STRING'),
        bigquery.SchemaField('tan_number',     'STRING'),
        bigquery.SchemaField('doc_number',     'STRING'),
        bigquery.SchemaField('doc_date',       'STRING'),  # keep as STRING to match main table
        bigquery.SchemaField('doc_type',       'STRING'),
        bigquery.SchemaField('taxable_amt',    'FLOAT'),
        bigquery.SchemaField('tax_amt',        'FLOAT'),
        bigquery.SchemaField('gross_amt',      'FLOAT'),
        bigquery.SchemaField('tds_section',    'STRING'),
        bigquery.SchemaField('tds_rate',       'FLOAT'),
        bigquery.SchemaField('tds_deductible', 'FLOAT'),
        bigquery.SchemaField('entry_source',   'STRING'),
    ]
    job_config = bigquery.LoadJobConfig(
        write_disposition = bigquery.WriteDisposition.WRITE_TRUNCATE,
        source_format     = bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema            = staging_schema,
        autodetect        = False,
    )
    job = client.load_table_from_json(safe_rows, staging_table, job_config=job_config)
    job.result()   # wait for staging load

    # Step 2 — MERGE staging into main table on income_id
    merge_sql = f"""
    MERGE `{main_table}` AS T
    USING `{staging_table}` AS S
    ON T.income_id = S.income_id
    WHEN MATCHED THEN UPDATE SET
        T.tds_deductible = S.tds_deductible,
        T.tds_section    = S.tds_section,
        T.tds_rate       = S.tds_rate,
        T.upload_ref     = S.upload_ref,
        T.taxable_amt    = S.taxable_amt,
        T.tax_amt        = S.tax_amt,
        T.gross_amt      = S.gross_amt
    WHEN NOT MATCHED THEN INSERT (
        income_id, upload_ref, fin_year, cust_id, cust_code, cust_name,
        pan_number, tan_number, doc_number, doc_date, doc_type,
        taxable_amt, tax_amt, gross_amt, tds_section, tds_rate,
        tds_deductible, entry_source
    ) VALUES (
        S.income_id, S.upload_ref, S.fin_year, S.cust_id, S.cust_code, S.cust_name,
        S.pan_number, S.tan_number, S.doc_number, S.doc_date, S.doc_type,
        S.taxable_amt, S.tax_amt, S.gross_amt, S.tds_section, S.tds_rate,
        S.tds_deductible, S.entry_source
    )
    """
    merge_job = client.query(merge_sql)
    merge_job.result()   # wait for merge
    return 0   # MERGE doesn't return row-level errors like insert_rows_json


# ── Individual table sync functions ─────────────────────────────────────────

def sync_income_records(conn, client, watermark):
    """
    Incremental sync of income_records — split into two operations:

    1. NEW rows (income_id > last_watermark)
       → direct WRITE_APPEND to BQ, no staging, no full-table scan

    2. UPDATED rows (tds_deductible changed since last sync)
       → only those rows go to staging → MERGE on income_id
       → BQ scans only the small staging set, not the entire main table

    This avoids the expensive full-table MERGE scan for millions of records.
    """
    import json, datetime as _dt, decimal as _dec
    def _serial(o):
        if isinstance(o, _dt.datetime): return o.strftime('%Y-%m-%d %H:%M:%S')
        if isinstance(o, _dt.date):     return o.strftime('%Y-%m-%d')
        if isinstance(o, _dec.Decimal): return float(o)
        raise TypeError(f'Not serialisable: {type(o)}')

    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT last_row_count FROM bq_sync_watermark WHERE table_name = 'income_records'")
    wm_row = cur.fetchone()
    last_id = wm_row['last_row_count'] if wm_row else 0
    print(f'  [income_records] last synced income_id = {last_id}')

    # ── Step 1: NEW rows → direct APPEND ────────────────────────
    cur.execute("""
        SELECT
            ir.income_id, ir.upload_ref, ir.fin_year, ir.cust_id,
            cm.cust_code, cm.cust_name, cm.pan_number, cm.tan_number,
            ir.doc_number, CAST(ir.doc_date AS CHAR) AS doc_date,
            ir.doc_type,
            CAST(ir.taxable_amt    AS DECIMAL(15,2)) AS taxable_amt,
            CAST(ir.tax_amt        AS DECIMAL(15,2)) AS tax_amt,
            CAST(ir.gross_amt      AS DECIMAL(15,2)) AS gross_amt,
            ir.tds_section,
            CAST(ir.tds_rate       AS DECIMAL(5,2))  AS tds_rate,
            CAST(ir.tds_deductible AS DECIMAL(15,2)) AS tds_deductible,
            ir.entry_source
        FROM income_records ir
        JOIN cust_master cm ON ir.cust_id = cm.cust_id
        WHERE ir.income_id > %s
    """, (last_id,))
    new_rows = cur.fetchall()

    appended = 0
    if new_rows:
        new_cleaned = clean_rows(new_rows)
        errs = bq_append(client, 'income_records', new_cleaned)
        max_id = max(r['income_id'] for r in new_rows)
        if errs == 0:
            cur2 = conn.cursor()
            cur2.execute("""
                INSERT INTO bq_sync_watermark (table_name, last_synced_at, last_row_count)
                VALUES ('income_records', NOW(), %s)
                ON DUPLICATE KEY UPDATE last_synced_at=NOW(), last_row_count=%s
            """, (max_id, max_id))
            conn.commit()
            cur2.close()
        appended = len(new_cleaned)
        print(f'  [income_records] appended {appended} new rows, watermark → income_id {max_id} (errors: {errs})')
    else:
        print(f'  [income_records] no new rows since income_id {last_id}')

    # ── Step 2: UPDATED rows (tds_deductible changed) → MERGE ───
    # Compare MySQL tds_deductible against BQ for existing rows (income_id <= last_id)
    # Pull current tds_deductible from BQ for existing rows
    bq_table = f'`{BQ_PROJECT}.{BQ_DATASET}.income_records`'
    bq_vals_query = f"""
        SELECT income_id, tds_deductible, tds_section, tds_rate
        FROM {bq_table}
        WHERE income_id <= {last_id}
    """
    bq_job    = client.query(bq_vals_query)
    bq_rows   = {r['income_id']: r for r in bq_job.result()}

    if bq_rows:
        # Fetch same rows from MySQL
        ids_str = ','.join(str(k) for k in bq_rows.keys())
        cur.execute(f"""
            SELECT
                ir.income_id,
                CAST(ir.tds_deductible AS DECIMAL(15,2)) AS tds_deductible,
                ir.tds_section,
                CAST(ir.tds_rate AS DECIMAL(5,2)) AS tds_rate,
                ir.upload_ref, ir.fin_year, ir.cust_id,
                cm.cust_code, cm.cust_name, cm.pan_number, cm.tan_number,
                ir.doc_number, CAST(ir.doc_date AS CHAR) AS doc_date,
                ir.doc_type,
                CAST(ir.taxable_amt AS DECIMAL(15,2)) AS taxable_amt,
                CAST(ir.tax_amt     AS DECIMAL(15,2)) AS tax_amt,
                CAST(ir.gross_amt   AS DECIMAL(15,2)) AS gross_amt,
                ir.entry_source
            FROM income_records ir
            JOIN cust_master cm ON ir.cust_id = cm.cust_id
            WHERE ir.income_id IN ({ids_str})
        """)
        mysql_rows = cur.fetchall()

        # Find only rows where tds_deductible differs
        changed = [
            r for r in mysql_rows
            if abs(float(r['tds_deductible']) -
                   float(bq_rows[r['income_id']]['tds_deductible'] or 0)) > 0.001
        ]

        if changed:
            changed_cleaned = clean_rows(changed)
            safe = json.loads(json.dumps(changed_cleaned, default=_serial))
            staging = f'{BQ_PROJECT}.{BQ_DATASET}.income_records_staging'
            main    = f'{BQ_PROJECT}.{BQ_DATASET}.income_records'
            staging_schema = [
                bigquery.SchemaField('income_id',      'INTEGER'),
                bigquery.SchemaField('upload_ref',     'STRING'),
                bigquery.SchemaField('fin_year',       'STRING'),
                bigquery.SchemaField('cust_id',        'INTEGER'),
                bigquery.SchemaField('cust_code',      'STRING'),
                bigquery.SchemaField('cust_name',      'STRING'),
                bigquery.SchemaField('pan_number',     'STRING'),
                bigquery.SchemaField('tan_number',     'STRING'),
                bigquery.SchemaField('doc_number',     'STRING'),
                bigquery.SchemaField('doc_date',       'STRING'),
                bigquery.SchemaField('doc_type',       'STRING'),
                bigquery.SchemaField('taxable_amt',    'FLOAT'),
                bigquery.SchemaField('tax_amt',        'FLOAT'),
                bigquery.SchemaField('gross_amt',      'FLOAT'),
                bigquery.SchemaField('tds_section',    'STRING'),
                bigquery.SchemaField('tds_rate',       'FLOAT'),
                bigquery.SchemaField('tds_deductible', 'FLOAT'),
                bigquery.SchemaField('entry_source',   'STRING'),
            ]
            jc = bigquery.LoadJobConfig(
                write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
                schema=staging_schema, autodetect=False
            )
            client.load_table_from_json(safe, staging, job_config=jc).result()
            merge_sql = f"""
            MERGE `{main}` AS T
            USING `{staging}` AS S ON T.income_id = S.income_id
            WHEN MATCHED THEN UPDATE SET
                T.tds_deductible = S.tds_deductible,
                T.tds_section    = S.tds_section,
                T.tds_rate       = S.tds_rate
            """
            client.query(merge_sql).result()
            print(f'  [income_records] merged {len(changed)} updated rows via staging (delta only)')
        else:
            print(f'  [income_records] no tds_deductible changes detected')

    cur.close()
    return appended


def sync_form26as_records(conn, client, watermark):
    """
    Incremental append of new Form 26AS records.
    Uses record_id (auto-increment PK) as watermark — form26as_records has no
    timestamp column. Records are never updated after insert so PK is sufficient.
    """
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT last_row_count FROM bq_sync_watermark WHERE table_name = 'form26as_records'")
    wm_row = cur.fetchone()
    last_id = wm_row['last_row_count'] if wm_row else 0
    print(f'  [form26as_records] last synced record_id = {last_id}')
    cur.execute("""
        SELECT
            f.record_id, f.fin_year, f.tan_of_deductor, f.deductor_name,
            f.section_code,
            CAST(f.transaction_date AS CHAR) AS transaction_date,
            CAST(f.booking_amt  AS DECIMAL(15,2)) AS booking_amt,
            CAST(f.tds_credited AS DECIMAL(15,2)) AS tds_credited,
            cm.cust_code, cm.cust_name
        FROM form26as_records f
        LEFT JOIN cust_master cm
            ON LOWER(TRIM(cm.tan_number)) = LOWER(TRIM(f.tan_of_deductor))
        WHERE f.record_id > %s
    """, (last_id,))
    rows = cur.fetchall()
    cur.close()
    if not rows:
        print(f'  [form26as_records] no new rows since record_id {last_id}')
        return 0
    cleaned = clean_rows(rows)
    errs = bq_append(client, 'form26as_records', cleaned)
    if errs == 0:
        max_id = max(r['record_id'] for r in rows)
        cur2 = conn.cursor()
        cur2.execute("""
            INSERT INTO bq_sync_watermark (table_name, last_synced_at, last_row_count)
            VALUES ('form26as_records', NOW(), %s)
            ON DUPLICATE KEY UPDATE last_synced_at=NOW(), last_row_count=%s
        """, (max_id, max_id))
        conn.commit()
        cur2.close()
    print(f'  [form26as_records] appended {len(cleaned)} rows (errors: {errs})')
    return len(cleaned)


def sync_cust_master(conn, client, watermark):
    """
    Incremental sync of cust_master — split into two operations:

    1. NEW customers (cust_id > last_watermark)
       → direct WRITE_APPEND, no staging, no full-table scan

    2. UPDATED customers (gstin, tan, status changed for existing cust_ids)
       → compare MySQL vs BQ for existing rows
       → only changed rows go to staging → MERGE (small delta set)
    """
    import json, datetime as _dt, decimal as _dec
    def _serial(o):
        if isinstance(o, _dt.datetime): return o.strftime('%Y-%m-%d %H:%M:%S')
        if isinstance(o, _dt.date):     return o.strftime('%Y-%m-%d')
        if isinstance(o, _dec.Decimal): return float(o)
        raise TypeError(f'Not serialisable: {type(o)}')

    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT last_row_count FROM bq_sync_watermark WHERE table_name = 'cust_master'")
    wm_row = cur.fetchone()
    last_id = wm_row['last_row_count'] if wm_row else 0
    print(f'  [cust_master] last synced cust_id = {last_id}')

    # ── Step 1: NEW customers → direct APPEND ───────────────────
    cur.execute("""
        SELECT cust_id, cust_code, cust_name, pan_number,
               gstin_number, tan_number, cust_status
        FROM cust_master
        WHERE cust_id > %s
    """, (last_id,))
    new_rows = cur.fetchall()

    appended = 0
    if new_rows:
        new_cleaned = clean_rows(new_rows)
        errs = bq_append(client, 'cust_master', new_cleaned)
        max_id = max(r['cust_id'] for r in new_rows)
        if errs == 0:
            cur2 = conn.cursor()
            cur2.execute("""
                INSERT INTO bq_sync_watermark (table_name, last_synced_at, last_row_count)
                VALUES ('cust_master', NOW(), %s)
                ON DUPLICATE KEY UPDATE last_synced_at=NOW(), last_row_count=%s
            """, (max_id, max_id))
            conn.commit()
            cur2.close()
        appended = len(new_cleaned)
        print(f'  [cust_master] appended {appended} new customers, watermark → cust_id {max_id}')
    else:
        print(f'  [cust_master] no new customers since cust_id {last_id}')

    # ── Step 2: UPDATED customers → compare MySQL vs BQ → MERGE delta ──
    bq_table = f'`{BQ_PROJECT}.{BQ_DATASET}.cust_master`'
    bq_job  = client.query(f"""
        SELECT cust_id, cust_code, cust_name, gstin_number, tan_number, cust_status
        FROM {bq_table}
        WHERE cust_id <= {last_id}
    """)
    bq_rows = {r['cust_id']: r for r in bq_job.result()}

    if bq_rows:
        ids_str = ','.join(str(k) for k in bq_rows.keys())
        cur.execute(f"""
            SELECT cust_id, cust_code, cust_name, pan_number,
                   gstin_number, tan_number, cust_status
            FROM cust_master WHERE cust_id IN ({ids_str})
        """)
        mysql_rows = cur.fetchall()

        # Detect any field change
        changed = []
        for r in mysql_rows:
            bq = bq_rows.get(r['cust_id'])
            if not bq: continue
            if (str(r['cust_name'] or '')      != str(bq['cust_name'] or '')      or
                str(r['gstin_number'] or '')   != str(bq['gstin_number'] or '')   or
                str(r['tan_number'] or '')     != str(bq['tan_number'] or '')     or
                str(r['cust_status'] or '')    != str(bq['cust_status'] or '')):
                changed.append(r)

        if changed:
            safe = json.loads(json.dumps(clean_rows(changed), default=_serial))
            staging = f'{BQ_PROJECT}.{BQ_DATASET}.cust_master_staging'
            main    = f'{BQ_PROJECT}.{BQ_DATASET}.cust_master'
            jc = bigquery.LoadJobConfig(
                write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
                autodetect=True
            )
            client.load_table_from_json(safe, staging, job_config=jc).result()
            merge_sql = f"""
            MERGE `{main}` AS T
            USING `{staging}` AS S ON T.cust_id = S.cust_id
            WHEN MATCHED THEN UPDATE SET
                T.cust_code    = S.cust_code,   T.cust_name  = S.cust_name,
                T.pan_number   = S.pan_number,  T.gstin_number = S.gstin_number,
                T.tan_number   = S.tan_number,  T.cust_status = S.cust_status
            """
            client.query(merge_sql).result()
            print(f'  [cust_master] merged {len(changed)} updated customers via staging (delta only)')
        else:
            print(f'  [cust_master] no customer changes detected')

    cur.close()
    return appended


def sync_audit_logs(conn, client, watermark):
    """
    Audit logs are purely append-only — never updated after insert.
    Uses log_id as watermark (timestamp column is called 'timestamp' not 'created_at').
    """
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT last_row_count FROM bq_sync_watermark WHERE table_name = 'audit_logs'")
    wm_row = cur.fetchone()
    last_id = wm_row['last_row_count'] if wm_row else 0
    print(f'  [audit_logs] last synced log_id = {last_id}')
    cur.execute("""
        SELECT log_id, action_type, module_name, description,
               severity_level, user_name, ip_address,
               CAST(timestamp AS CHAR) AS timestamp
        FROM audit_logs
        WHERE log_id > %s
        ORDER BY log_id ASC
    """, (last_id,))
    rows = cur.fetchall()
    cur.close()
    if not rows:
        print(f'  [audit_logs] no new rows since log_id {last_id}')
        return 0
    cleaned = clean_rows(rows)
    errs = bq_append(client, 'audit_logs', cleaned)
    if errs == 0:
        max_id = max(r['log_id'] for r in rows)
        cur2 = conn.cursor()
        cur2.execute("""
            INSERT INTO bq_sync_watermark (table_name, last_synced_at, last_row_count)
            VALUES ('audit_logs', NOW(), %s)
            ON DUPLICATE KEY UPDATE last_synced_at=NOW(), last_row_count=%s
        """, (max_id, max_id))
        conn.commit()
        cur2.close()
    print(f'  [audit_logs] appended {len(cleaned)} rows (errors: {errs})')
    return len(cleaned)


def sync_tds_summary(conn, client):
    """
    Sync tds_summary — split into two operations:

    1. NEW (cust_id, fin_year) combinations not yet in BQ
       → direct WRITE_APPEND

    2. EXISTING (cust_id, fin_year) where aggregates changed
       → only changed rows to staging → MERGE (delta only)
       → BQ scans only the small staging set, not the full summary table
    """
    import json, datetime as _dt, decimal as _dec
    def _serial(o):
        if isinstance(o, _dt.datetime): return o.strftime('%Y-%m-%d %H:%M:%S')
        if isinstance(o, _dt.date):     return o.strftime('%Y-%m-%d')
        if isinstance(o, _dec.Decimal): return float(o)
        raise TypeError(f'Not serialisable: {type(o)}')

    print('  [tds_summary] computing current aggregates...')
    cur = conn.cursor(dictionary=True)
    cur.execute("""
        SELECT DISTINCT fin_year FROM income_records
        UNION
        SELECT DISTINCT fin_year FROM form26as_records
    """)
    fin_years = [r['fin_year'] for r in cur.fetchall()]

    # Recompute all FYs from MySQL
    all_rows = []
    for fy in fin_years:
        cur.execute("""
            SELECT
                c.cust_id, c.cust_code, c.cust_name, c.pan_number, c.tan_number,
                ir.fin_year,
                COALESCE(SUM(ir.taxable_amt),    0.00) AS total_taxable_amt,
                COALESCE(SUM(ir.tds_deductible), 0.00) AS total_tds_deductible,
                COALESCE(SUM(ir.gross_amt),      0.00) AS total_gross_amt,
                COALESCE(f26.total_tds_credited, 0.00) AS total_26as_credit,
                COALESCE(SUM(ir.tds_deductible), 0.00)
                    - COALESCE(f26.total_tds_credited, 0.00) AS variance_amt,
                CASE WHEN COALESCE(SUM(ir.tds_deductible), 0) = 0 THEN 0.00
                     ELSE ROUND(
                         COALESCE(f26.total_tds_credited, 0.00)
                         / COALESCE(SUM(ir.tds_deductible), 0.00) * 100, 2)
                END AS pct_credit,
                COUNT(ir.income_id) AS invoice_count
            FROM cust_master c
            LEFT JOIN income_records ir
                ON c.cust_id = ir.cust_id AND ir.fin_year = %s
            LEFT JOIN (
                SELECT LOWER(TRIM(tan_of_deductor)) AS tan,
                       SUM(tds_credited) AS total_tds_credited
                FROM form26as_records WHERE fin_year = %s
                GROUP BY LOWER(TRIM(tan_of_deductor))
            ) f26 ON LOWER(TRIM(c.tan_number)) = f26.tan
            WHERE ir.fin_year = %s
            GROUP BY c.cust_id, c.cust_code, c.cust_name,
                     c.pan_number, c.tan_number, ir.fin_year,
                     f26.total_tds_credited
        """, (fy, fy, fy))
        all_rows.extend(cur.fetchall())
    cur.close()

    if not all_rows:
        print('  [tds_summary] no rows to sync')
        return 0

    # Pull current BQ tds_summary for comparison
    bq_table = f'`{BQ_PROJECT}.{BQ_DATASET}.tds_summary`'
    bq_job  = client.query(f"""
        SELECT cust_id, fin_year, total_tds_deductible, total_26as_credit, variance_amt
        FROM {bq_table}
    """)
    bq_rows = {(r['cust_id'], r['fin_year']): r for r in bq_job.result()}

    new_rows     = []
    changed_rows = []

    for r in all_rows:
        key = (r['cust_id'], r['fin_year'])
        if key not in bq_rows:
            new_rows.append(r)
        else:
            bq = bq_rows[key]
            if abs(float(r['total_tds_deductible']) -
                   float(bq['total_tds_deductible'] or 0)) > 0.001:
                changed_rows.append(r)

    total = 0

    # Step 1: New (cust_id, fin_year) → direct APPEND
    if new_rows:
        cleaned_new = clean_rows(new_rows)
        errs = bq_append(client, 'tds_summary', cleaned_new)
        print(f'  [tds_summary] appended {len(cleaned_new)} new rows (errors: {errs})')
        total += len(cleaned_new)
    else:
        print('  [tds_summary] no new (cust_id, fin_year) combinations')

    # Step 2: Changed rows → staging → MERGE (delta only)
    if changed_rows:
        safe = json.loads(json.dumps(clean_rows(changed_rows), default=_serial))
        staging = f'{BQ_PROJECT}.{BQ_DATASET}.tds_summary_staging'
        main    = f'{BQ_PROJECT}.{BQ_DATASET}.tds_summary'
        jc = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
            autodetect=True
        )
        client.load_table_from_json(safe, staging, job_config=jc).result()
        merge_sql = f"""
        MERGE `{main}` AS T
        USING `{staging}` AS S
            ON T.cust_id = S.cust_id AND T.fin_year = S.fin_year
        WHEN MATCHED THEN UPDATE SET
            T.total_taxable_amt    = S.total_taxable_amt,
            T.total_tds_deductible = S.total_tds_deductible,
            T.total_gross_amt      = S.total_gross_amt,
            T.total_26as_credit    = S.total_26as_credit,
            T.variance_amt         = S.variance_amt,
            T.pct_credit           = S.pct_credit,
            T.invoice_count        = S.invoice_count
        """
        client.query(merge_sql).result()
        print(f'  [tds_summary] merged {len(changed_rows)} changed rows via staging (delta only)')
        total += len(changed_rows)
    else:
        print('  [tds_summary] no aggregate changes detected')

    return total


def run_incremental_sync():
    """
    Run incremental sync for all tables.
    Called by airflow_dag.py on schedule, or directly via python bq_incremental_sync.py
    """
    sync_start = datetime.now(timezone.utc).replace(tzinfo=None)
    print(f'\n{"="*60}')
    print(f'Incremental MySQL → BigQuery sync')
    print(f'Started: {sync_start.strftime("%Y-%m-%d %H:%M:%S UTC")}')
    print(f'{"="*60}\n')

    try:
        conn   = get_mysql()
        client = get_bq()
        ensure_watermark_table(conn)
    except Exception as e:
        print(f'[ERROR] Could not connect: {e}')
        raise

    results = {}

    # ── income_records ──────────────────────────────────────
    wm = get_watermark(conn, 'income_records')
    n  = sync_income_records(conn, client, wm)
    if n > 0:
        set_watermark(conn, 'income_records', sync_start, n)
    results['income_records'] = n

    # ── form26as_records ────────────────────────────────────
    wm = get_watermark(conn, 'form26as_records')
    n  = sync_form26as_records(conn, client, wm)
    if n > 0:
        set_watermark(conn, 'form26as_records', sync_start, n)
    results['form26as_records'] = n

    # ── cust_master ─────────────────────────────────────────
    wm = get_watermark(conn, 'cust_master')
    n  = sync_cust_master(conn, client, wm)
    if n > 0:
        set_watermark(conn, 'cust_master', sync_start, n)
    results['cust_master'] = n

    # ── audit_logs ──────────────────────────────────────────
    wm = get_watermark(conn, 'audit_logs')
    n  = sync_audit_logs(conn, client, wm)
    if n > 0:
        set_watermark(conn, 'audit_logs', sync_start, n)
    results['audit_logs'] = n

    # ── tds_summary (always recomputed — see docstring) ─────
    n = sync_tds_summary(conn, client)
    set_watermark(conn, 'tds_summary', sync_start, n)
    results['tds_summary'] = n

    conn.close()

    print(f'\n{"="*60}')
    print('Sync complete. Summary:')
    for table, count in results.items():
        status = f'{count} rows' if count > 0 else 'no changes'
        print(f'  {table:<25} {status}')
    print(f'Finished: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')
    print(f'{"="*60}\n')

    return results


if __name__ == '__main__':
    run_incremental_sync()
