#!/usr/bin/env python3
"""Apply one or more SQL files to the Supabase project through the Management API (the same path the migrations were applied with).

Usage: SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_PROJECT_REF=<ref> python3 scripts/apply_sql.py supabase/migrations/0001_raw_source_tables.sql [more.sql ...]
Each file runs as one request (one transaction); on error nothing from that file is applied.
"""
import json, os, sys, urllib.error, urllib.request

REF, TOKEN = os.environ.get("SUPABASE_PROJECT_REF"), os.environ.get("SUPABASE_ACCESS_TOKEN")
if not REF or not TOKEN or len(sys.argv) < 2:
    sys.exit(__doc__)
for path in sys.argv[1:]:
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": open(path).read()}).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "billing-crazy"})
    try:
        print(path, urllib.request.urlopen(req, timeout=170).read().decode()[:200])
    except urllib.error.HTTPError as e:
        sys.exit(f"{path}: HTTP {e.code} {e.read().decode()[:800]}")
