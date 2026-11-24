-- Dedupe on record_id: 1,925 physical rows -> 1,924 unique active records. The repeat is ur_7352010ec2e04c (Westhaven Metrics, 2026-10-14).
select test_name, expected, actual, (expected = actual) as pass from (
  select 'raw physical rows' as test_name, '1925' as expected, (select count(*) from raw.product_usage)::text as actual
  union all select 'distinct record_id in raw', '1924', (select count(distinct record_id) from raw.product_usage)::text
  union all select 'v_usage_clean rows', '1924', (select count(*) from stg.v_usage_clean)::text
  union all select 'v_usage_clean has no repeated record_id', '0', (select count(*) from (select record_id from stg.v_usage_clean group by 1 having count(*) > 1) x)::text
  union all select 'ur_7352010ec2e04c rows in raw (left in staging)', '2', (select count(*) from raw.product_usage where record_id = 'ur_7352010ec2e04c')::text
  union all select 'ur_7352010ec2e04c rows in v_usage_clean', '1', (select count(*) from stg.v_usage_clean where record_id = 'ur_7352010ec2e04c')::text
  union all select 'explicit zero-use days are kept as records', '16', (select count(*) from stg.v_usage_clean where units = 0)::text
  union all select 'all clean rows are active', '1924', (select count(*) from stg.v_usage_clean where record_status = 'active')::text
) t;
