#!/usr/bin/env python3
"""Load every contest CSV into Supabase `raw.*`, record per-file row counts, compare to the START_HERE manifest.

Usage:  SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_PROJECT_REF=<ref> python3 scripts/load_raw.py "<contestant folder>"
Nothing is transformed: blanks become NULL (START_HERE: blank = missing, not zero); values are inserted as exported.
Exit code 0 only if every manifest check passes.
"""
import csv, json, os, subprocess, sys, urllib.request, urllib.error

if len(sys.argv) != 2:
    sys.exit(__doc__)
SRC = sys.argv[1]
TOKEN, REF = os.environ.get("SUPABASE_ACCESS_TOKEN"), os.environ.get("SUPABASE_PROJECT_REF")
if not TOKEN or not REF:
    sys.exit("Set SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF")

def run(sql):
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": sql}).encode(), method="POST",
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy-loader"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=120).read().decode() or "[]")
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:500]}")

def lit(v):
    return "NULL" if v == "" else "'" + v.replace("'", "''") + "'"

# csv file -> (raw table, columns in CSV order)
FILES = {
 "salesforce_accounts.csv": ("salesforce_accounts", "account_id,account_name,parent_id,billing_country,stripe_customer_id,netsuite_customer_internal_id,account_owner"),
 "contract_register.csv": ("contract_register", "document_id,contract_id,salesforce_account_id,document_type,document_filename,signed_at,effective_from,effective_to,supersedes_document_id,billing_loaded_at,approval_reference"),
 "product_account_mapping.csv": ("product_account_mapping", "product_account_id,salesforce_account_id,account_label,effective_from,effective_to,mapping_updated_at"),
 "product_usage.csv": ("product_usage", "record_id,product_account_id,sku,service_date,units,ingested_at,record_status,replaces_record_id,batch_id"),
 "usage_batch_controls.csv": ("usage_batch_controls", "service_date,batch_id,distinct_active_record_count,active_units_total,extracted_at"),
 "stripe_invoices.csv": ("stripe_invoices", "id,number,customer_id,status,created,finalized_at,currency,subtotal,total_discount_amount,total,source_system"),
 "stripe_invoice_lines.csv": ("stripe_invoice_lines", "id,invoice_id,description,product_id,price_id,quantity,unit_amount_decimal,amount,discount_amount,period_start,period_end,proration"),
 "stripe_credit_notes.csv": ("stripe_credit_notes", "id,number,invoice_id,customer_id,status,created,voided_at,currency,amount,reason"),
 "stripe_credit_note_lines.csv": ("stripe_credit_note_lines", "id,credit_note_id,invoice_line_item_id,description,amount,quantity,service_start,service_end_exclusive,service_period_source"),
 "netsuite_gl_detail.csv": ("netsuite_gl_detail", "internal_id,line_id,transaction_type,document_number,txn_date,posting_period,account_number,customer_internal_id,debit,credit,memo,external_source_id,revenue_plan_id,created_at"),
 "netsuite_opening_balances.csv": ("netsuite_opening_balances", "customer_internal_id,account_number,account_name,as_of_date,debit_balance,credit_balance,source_reference"),
 "netsuite_revenue_plan_detail.csv": ("netsuite_revenue_plan_detail", "revenue_plan_id,revenue_element_id,customer_internal_id,source_document_id,plan_type,recognition_start,recognition_end_exclusive,posting_period,planned_amount,recognized_amount,journal_internal_id,plan_updated_at"),
}
try:
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
except Exception:
    commit = None
batch = run(f"insert into raw.load_batches (source_folder, git_commit) values ({lit(os.path.basename(SRC.rstrip('/')))}, {lit(commit or '')}) returning load_batch_id")[0]["load_batch_id"]

for fn, (tbl, cols) in FILES.items():
    with open(os.path.join(SRC, fn), newline="", encoding="utf-8-sig") as f:
        rows = list(csv.reader(f))
    header, data = rows[0], [r for r in rows[1:] if r]
    assert len(header) == len(cols.split(",")), f"{fn}: unexpected column count"
    assert all(len(r) == len(header) for r in data), f"{fn}: ragged rows"
    run(f"truncate raw.{tbl} restart identity")
    for i in range(0, len(data), 300):
        vals = ",".join("(" + ",".join(lit(c) for c in r) + f",'{batch}','{fn}')" for r in data[i:i + 300])
        run(f"insert into raw.{tbl} ({cols},load_batch_id,source_file) values {vals}")
    run(f"""insert into raw.load_files (load_batch_id, source_file, csv_rows, db_rows, expected_rows, status)
            select '{batch}', '{fn}', {len(data)}, (select count(*) from raw.{tbl} where load_batch_id = '{batch}'),
                   m.expected_rows, 'PASS' from raw.source_manifest m where m.source_file = '{fn}'""")

result = run("select source_file, expected_rows, csv_rows, db_rows, status, basis from public.load_manifest_check")
w = max(len(r["source_file"]) for r in result)
print(f"{'check':<{w}}  {'expected':>8} {'csv':>6} {'db':>6}  status")
bad = 0
for r in result:
    bad += r["status"] != "PASS"
    print(f"{r['source_file']:<{w}}  {r['expected_rows']:>8} {str(r['csv_rows'] or ''):>6} {r['db_rows']:>6}  {r['status']}")
print(f"\nbatch {batch}: {'ALL PASS' if not bad else str(bad) + ' FAIL'}")
if bad:
    run(f"update raw.load_files set status='FAIL' where load_batch_id='{batch}' and (db_rows<>expected_rows or csv_rows<>expected_rows)")
sys.exit(1 if bad else 0)
