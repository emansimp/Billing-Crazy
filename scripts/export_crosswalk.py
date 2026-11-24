#!/usr/bin/env python3
"""Regenerate semantic/entities/customer_crosswalk.csv from stg.v_customer_crosswalk (SQL is the source of truth)."""
import csv, json, os, sys, urllib.request
REF, TOKEN = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
def q(sql):
    r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": sql}).encode(),
        method="POST", headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
    return json.loads(urllib.request.urlopen(r, timeout=60).read())
out = sys.argv[1] if len(sys.argv) > 1 else "semantic/entities/customer_crosswalk.csv"
rows = q("select * from stg.v_customer_crosswalk order by account_name")
cols = list(rows[0].keys())
with open(out, "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n"); w.writerow(cols)
    for r in rows:
        w.writerow(["|".join(v) if isinstance(v, list) else ("" if v is None else v) for v in (r[c] for c in cols)])
print(f"wrote {len(rows)} rows to {out}")
