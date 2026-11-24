-- Batch controls: clean (post-dedup, incl. unassigned) must equal usage_batch_controls on records and runs for all 61 dates.
select test_name, expected, actual, (expected = actual) as pass from (
  select 'batch dates reconciled' as test_name, '61' as expected, (select count(*) from stg.v_usage_batch_reconciliation)::text as actual
  union all select 'sum of record differences', '0', (select sum(record_diff) from stg.v_usage_batch_reconciliation)::text
  union all select 'sum of unit differences', '0', (select sum(unit_diff) from stg.v_usage_batch_reconciliation)::text
  union all select 'dates with open items', '0', (select count(*) from stg.v_usage_batch_reconciliation where status like 'OPEN%')::text
  union all select 'dates explained by an exact repeat (2026-10-14)', '1', (select count(*) from stg.v_usage_batch_reconciliation where status like 'explained%' and service_date = '2026-10-14')::text
  union all select 'Sep 1-14 controls = 30 records/day', '14', (select count(*) from stg.v_usage_batch_reconciliation where service_date < '2026-09-15' and control_records = 30)::text
  union all select 'Sep 15-Oct 31 controls = 32 records/day', '47', (select count(*) from stg.v_usage_batch_reconciliation where service_date >= '2026-09-15' and control_records = 32)::text
  union all select 'control units total', '3138816', (select sum(control_units) from stg.v_usage_batch_reconciliation)::text
) t;
