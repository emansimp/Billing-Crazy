# /scripts
Operational scripts. `load_raw.py` ingests every contest CSV into the `raw` schema, records per-file row counts in `raw.load_files`, and compares them to the START_HERE manifest (`raw.source_manifest`). Usage: `python3 scripts/load_raw.py <contestant-folder>`; reads `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` from the environment.
