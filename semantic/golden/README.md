# golden
SQL tests with fixed expected values. Expected numbers were computed **independently from the source CSVs** (Python, not SQL), then
written here, so a test fails if the SQL layer drifts. Each file is one `select` returning `test_name, expected, actual, pass`.
Run all: `python3 scripts/run_golden.py` (needs `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`). Exit code 1 on any failure.
