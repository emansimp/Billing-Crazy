#!/usr/bin/env python3
"""Export calc.v_findings and calc.v_customer_classification to semantic/findings/*.csv (SQL is the source; evidence kept as JSON)."""
import csv, json, os, urllib.request
REF, TOKEN = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
def q(sql):
    r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": sql}).encode(),
        method="POST", headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
    return json.loads(urllib.request.urlopen(r, timeout=170).read())
def dump(sql, path):
    rows = q(sql)
    with open(path, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n"); w.writerow(rows[0].keys())
        for x in rows: w.writerow([json.dumps(v, separators=(",", ":")) if isinstance(v, (dict, list)) else ("" if v is None else v) for v in x.values()])
    print(f"wrote {len(rows)} rows to {path}")
dump("select * from calc.v_findings order by case class when 'error' then 1 when 'needs_info' then 2 else 3 end, check_code, customer", "semantic/findings/october_2026_findings.csv")
dump("select * from calc.v_customer_classification order by account_name", "semantic/findings/october_2026_customer_classification.csv")
