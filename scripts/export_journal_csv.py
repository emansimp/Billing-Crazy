#!/usr/bin/env python3
"""Generate the NetSuite journal-entry CSV from calc.v_journal_lines (file only; nothing is sent to NetSuite).

Layout follows the Journal entries: NetSuite export mockup: External ID is repeated on every row, one debit-or-credit per line (the
other column is blank, never 0), account shown as "number name", Name = NetSuite customer internal ID, no total row.
Pre-export checks come from calc.v_journal_export_checks: any 'fail' (unbalanced entry, CLOSED posting period, write-off, bad override) blocks the file;
'warning' (placeholder accounts 4090 / 6900) is printed loudly; 'pending' Controller approval blocks unless --allow-draft.
Usage: SUPABASE_ACCESS_TOKEN=... SUPABASE_PROJECT_REF=... python3 scripts/export_journal_csv.py [--allow-draft] [--out exports/file.csv]
"""
import csv, io, json, os, sys, urllib.request
from decimal import Decimal
REF, TOKEN = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
def q(sql):
    r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": sql}).encode(),
        method="POST", headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
    return json.loads(urllib.request.urlopen(r, timeout=170).read())
allow_draft = "--allow-draft" in sys.argv
out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else "exports/relaycloud_oct2026_adjustments_netsuite.csv"
checks = q("select check_name, status, detail from calc.v_journal_export_checks")
blocked = False
print("Pre-export checks")
for c in checks:
    flag = {"pass": "PASS   ", "warning": "WARNING", "pending": "PENDING", "fail": "FAIL   "}[c["status"]]
    print(f"  {flag} {c['check_name']}: {c['detail']}")
    if c["status"] == "fail" or (c["status"] == "pending" and not allow_draft): blocked = True
    if c["status"] == "warning": print("          >> ACTION REQUIRED before import: map the placeholder account(s) to real NetSuite accounts.")
if blocked:
    sys.exit("Export blocked. Fix failures; Controller approval is required (or pass --allow-draft to write a DRAFT file for review).")
rows = q("select external_id, date, posting_period, account_label, debit, credit, memo, name from calc.v_journal_lines order by external_id, line_order, side_order")
hdr = ["External ID", "Date", "Posting Period", "Journal Entry - Line: Account", "Journal Entry - Line: Debit", "Journal Entry - Line: Credit", "Journal Entry - Line: Memo", "Name"]
buf = io.StringIO(newline="")
w = csv.writer(buf, lineterminator="\r\n"); w.writerow(hdr)
fmt = lambda v: "" if v is None else f"{Decimal(v):.2f}"
for r in rows:
    assert (r["debit"] is None) != (r["credit"] is None), "each line carries a debit or a credit, never both"
    w.writerow([r["external_id"], r["date"], r["posting_period"], r["account_label"], fmt(r["debit"]), fmt(r["credit"]), r["memo"], r["name"]])
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
open(out, "w", encoding="utf-8", newline="").write(buf.getvalue())
# re-read and verify: opens clean, balanced per entry, no total row, External ID on every row
back = list(csv.DictReader(open(out, encoding="utf-8", newline="")))
bal = {}
for r in back:
    assert r["External ID"] and r["Date"] and r["Posting Period"] and r["Name"] and r["Journal Entry - Line: Account"], "missing field"
    assert r["External ID"].lower() != "totals", "total row present"
    assert (r["Journal Entry - Line: Debit"] == "") != (r["Journal Entry - Line: Credit"] == ""), "debit/credit rule"
    b = bal.setdefault(r["External ID"], Decimal(0)); bal[r["External ID"]] = b + Decimal(r["Journal Entry - Line: Debit"] or 0) - Decimal(r["Journal Entry - Line: Credit"] or 0)
assert all(v == 0 for v in bal.values()), f"unbalanced: {bal}"
print(f"\nwrote {out}: {len(back)} lines, {len(bal)} entries, every entry balances, no total row" + ("  [DRAFT: Controller approval pending]" if any(c['status'] == 'pending' for c in checks) else ""))
