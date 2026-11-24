#!/usr/bin/env python3
"""Run every semantic/golden/*.sql test against Supabase and print a pass/fail table. Exit 1 on any failure."""
import glob, json, os, sys, urllib.request
REF, TOKEN = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
def q(sql):
    r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": sql}).encode(),
        method="POST", headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
    return json.loads(urllib.request.urlopen(r, timeout=60).read())
folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "semantic", "golden")
failed = total = 0
for path in sorted(glob.glob(os.path.join(folder, "*.sql"))):
    print(f"\n== {os.path.basename(path)}")
    for r in q(open(path).read()):
        total += 1; failed += not r["pass"]
        print(f"  {'PASS' if r['pass'] else 'FAIL'}  {r['test_name']:<70} expected={r['expected']} actual={r['actual']}")
print(f"\n{total - failed}/{total} passed" + ("" if not failed else f"  ({failed} FAILED)"))
sys.exit(1 if failed else 0)
