#!/usr/bin/env python3
"""Export the owner review table (one row per customer) from ref.v_contract_terms_review to semantic/entities/contract_terms_review.csv."""
import csv, json, os, urllib.request
REF, TOKEN = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": "select * from ref.v_contract_terms_review order by customer"}).encode(),
    method="POST", headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
rows = json.loads(urllib.request.urlopen(r, timeout=60).read())
with open("semantic/entities/contract_terms_review.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n"); w.writerow(rows[0].keys())
    for x in rows: w.writerow(["" if v is None else v for v in x.values()])
print(f"wrote {len(rows)} rows")
