# Form 26AS TDS Reconciliation System

Internal web utility for Sundaram Finance Limited — Data Platform.
Automates reconciliation of TDS credits from TRACES Form 26AS against Books of Accounts.

Built by **Sanjana Ravishankar**, Full Stack Developer Intern.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python 3 — Flask |
| Database | MySQL 8 |
| Frontend | Vanilla HTML5 / CSS3 / JavaScript |
| PDF Parsing | pypdf |
| Excel Parsing | openpyxl |
| Cloud Analytics | Google BigQuery |
| BI Reporting | Power BI Desktop (MySQL ODBC views) |
| Beam Pipeline | Apache Beam (DirectRunner / GCP Dataflow) |

---

## Project Structure

```
form26as_app/
│
├── app.py                        ← Flask backend (34 API routes)
├── .env                          ← DB + Flask credentials (not committed)
├── bq_service_account.json       ← GCP service account key (not committed)
│
├── templates/
│   ├── customer_master.html
│   ├── form26as.html
│   ├── books_of_accounts.html
│   ├── upload_utility.html
│   ├── reconciliation.html
│   ├── tds_summary.html
│   └── audit-trail.html
│
│
├── ── BigQuery Sync ────────────────────────────────────────────────
├── bq_incremental_sync.py        ← Core incremental sync engine (run in beam_env)
├── create_bq_tables.py           ← Creates all BQ tables + staging tables (run once)
├── dataflow_mysql_to_bq.py       ← Apache Beam Dataflow pipeline (future GCP use)
│
└── beam_env/                     ← Python virtual environment for BQ scripts
```

---

## MySQL Tables

### Application Tables (form26as_db)

| Table | Purpose |
|---|---|
| `cust_master` | Customer master — deductors with TAN, PAN, GSTIN |
| `income_records` | Books of Accounts — one row per invoice |
| `form26as_records` | TRACES Form 26AS — TDS credit entries per deductor |
| `tds_codes_master` | Global TDS rate reference table (Finance Act 2026, v2) |
| `tcs_codes_master` | TCS rate reference table |
| `file_uploads_log` | Upload audit log — every file upload with hash and row count |
| `audit_logs` | System event log — all data mutations and uploads |
| `adjustments` | Credit notes and deductions linked to invoices |
| `unreferenced_entries` | Rows from Books upload that could not match any customer |
| `recon_overrides` | Manual reconciliation status overrides by tax analyst |
| `user_master` | Application user accounts |

### BigQuery Sync Tracking (form26as_db)

| Table | Purpose |
|---|---|
| `bq_sync_watermark` | Tracks last synced primary key per BQ table — created automatically by bq_incremental_sync.py on first run |

---

## BigQuery Tables (tds_reconciliation dataset)

### Main Tables (synced from MySQL)

| Table | Sync Strategy | Watermark |
|---|---|---|
| `income_records` | MERGE via staging on income_id | income_id (PK) |
| `form26as_records` | WRITE_APPEND | record_id (PK) |
| `cust_master` | MERGE via staging on cust_id | cust_id (PK) |
| `audit_logs` | WRITE_APPEND | log_id (PK) |
| `tds_summary` | Full recompute + MERGE on (cust_id, fin_year) | Always recomputes |

### Staging Tables (transient — wiped on every sync run)

| Table | Used by |
|---|---|
| `income_records_staging` | MERGE into income_records |
| `cust_master_staging` | MERGE into cust_master |
| `tds_summary_staging` | MERGE into tds_summary |

---

## Setup

### 1. Environment

```bash
# Flask app — uses base Python or a venv with flask requirements
pip install -r requirements.txt

# BigQuery scripts — must use beam_env
cd form26as_app
.\beam_env\Scripts\activate        # Windows
source beam_env/bin/activate       # Linux/Mac
pip install -r requirements.txt
```

### 2. Environment Variables (.env)

```
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=your_user_name
DB_PASSWORD=your_password
DB_NAME=form26as_db
FLASK_HOST=127.0.0.1
FLASK_PORT=5000
FLASK_DEBUG=true
BQ_KEY_PATH=bq_service_account.json
BQ_PROJECT=eternal-skyline-468312-g7
BQ_DATASET=tds_reconciliation
```

### 3. MySQL Setup

```sql
-- Run in order in MySQL Workbench:
-- 1. form26as_schema.sql
-- 2. form26as_page_schema.sql
-- 3. income_tds_tcs_schema.sql
-- 4. upload_files-schema.sql
-- 5. schema_fixes.sql
-- 6. tds_codes_master_v2.sql
-- 7. powerbi_views.sql
```

### 4. BigQuery Setup (beam_env)

```bash
# Create all BQ tables including staging tables
python create_bq_tables.py

# First incremental sync — seeds BQ with all existing MySQL data
python bq_incremental_sync.py
```

### 5. Run Flask App

```bash
python app.py
# App available at http://127.0.0.1:5000
```

---

## Running the BigQuery Sync

Always run BQ scripts inside `beam_env`:

```bash
.\beam_env\Scripts\activate
python bq_incremental_sync.py
```

The sync is also triggered automatically by app.py after every Books of Accounts upload,
Form 26AS upload, and Customer Master upload.


```

### Windows Task Scheduler (Interim Task Scheduling Approach)

- Open Task Scheduler → Create Basic Task
- Trigger: Daily at 00:30
- Action: `python.exe` → Arguments: `C:\path\to\form26as_app\bq_incremental_sync.py`

---

## Power BI

Connect Power BI Desktop to MySQL via ODBC using the four views in `powerbi_views.sql`:

| View | Used for |
|---|---|
| `vw_tds_summary` | Customer-wise TDS deductible vs 26AS credit per FY |
| `vw_reconciliation` | Reconciliation status and variance per customer per FY |
| `vw_invoice_detail` | Invoice-level drill-down with FY quarter |
| `vw_upload_history` | Upload audit log for reporting |

---

## Key Design Decisions

| Decision | Reason |
|---|---|
| TAN as primary reconciliation key | Most reliable deductor identifier in Form 26AS |
| `tds_deductible` not `tax_amt` for TDS | `tax_amt` includes GST; `tds_deductible` is the legally computed TDS |
| Annual aggregate threshold check | CBDT-correct — threshold applies to annual total, not per invoice |
| Multiplicative surcharge formula | `base × (1 + surcharge/100) × (1 + cess/100)` — legally correct compounding |
| PK watermark for BQ incremental sync | Production MySQL tables have no consistent timestamp columns |
| SHA-256 dedup for Form 26AS | Prevents double-counting TDS credits on re-upload |
| Delete-then-insert upsert for Books | Ensures re-uploads refresh stale data cleanly |
| Rs 5 reconciliation tolerance | Absorbs paisa rounding across multiple invoices |

---

## GCP Details

| Property | Value |
|---|---|
| Project | eternal-skyline-468312-g7 |
| Dataset | tds_reconciliation |
| Location | asia-south1 |
| Service account key | bq_service_account.json |



