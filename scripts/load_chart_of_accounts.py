#!/usr/bin/env python3
"""Load semantic/chart_of_accounts.v1.yaml into ref.chart_of_accounts (the file in /semantic is the source of truth)."""
import json, os, re, urllib.request
REF, TOKEN = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
def q(sql):
    r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": sql}).encode(),
        method="POST", headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
    return json.loads(urllib.request.urlopen(r, timeout=60).read())
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "semantic", "chart_of_accounts.v1.yaml")
text = open(path).read()
version = int(re.search(r"^version:\s*(\d+)", text, re.M).group(1))
accts = []
for blk in re.split(r"\n  - number:", text.split("accounts:")[1])[1:]:
    blk = "number:" + blk
    g = lambda k: (re.search(rf"^\s*{k}:\s*(.+?)\s*(#.*)?$", blk, re.M) or [None, None])[1]
    accts.append(dict(number=g("number").strip('"'), name=g("name"), type=g("type"), placeholder=g("placeholder") == "true"))
lit = lambda v: "'" + str(v).replace("'", "''") + "'"
vals = ",".join(f"({lit(a['number'])},{lit(a['name'])},{lit(a['type'])},{str(a['placeholder']).lower()},{version})" for a in accts)
q("create table if not exists ref.chart_of_accounts (account_number text primary key, account_name text not null, account_type text not null, placeholder boolean not null, coa_version int not null);"
  "alter table ref.chart_of_accounts enable row level security; revoke all on ref.chart_of_accounts from anon, authenticated;"
  f"truncate ref.chart_of_accounts; insert into ref.chart_of_accounts values {vals};")
print(f"loaded {len(accts)} accounts (v{version}):", ", ".join(a["number"] + ("*" if a["placeholder"] else "") for a in accts), " (* = PLACEHOLDER)")
