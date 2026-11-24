-- Per-customer October aggregation across all of a customer's verified product accounts.
select test_name, expected, actual, (expected = actual) as pass from (
  select 'Cedar Harbor Labs Oct records' as test_name, '31' as expected, (select record_count from stg.v_usage_by_customer_month where account_name like 'Cedar Harbor%' and month_start = '2026-10-01')::text as actual
  union all select 'Cedar Harbor Labs Oct runs', '58470', (select verified_units from stg.v_usage_by_customer_month where account_name like 'Cedar Harbor%' and month_start = '2026-10-01')::text
  union all select 'Silver Current Oct records (2 accounts x 31)', '62', (select record_count from stg.v_usage_by_customer_month where account_name like 'Silver Current%' and month_start = '2026-10-01')::text
  union all select 'Silver Current Oct runs', '72266', (select verified_units from stg.v_usage_by_customer_month where account_name like 'Silver Current%' and month_start = '2026-10-01')::text
  union all select 'Silver Current product accounts', '2', (select product_accounts from stg.v_usage_by_customer_month where account_name like 'Silver Current%' and month_start = '2026-10-01')::text
  union all select 'Timberline Insights Oct records', '62', (select record_count from stg.v_usage_by_customer_month where account_name like 'Timberline%' and month_start = '2026-10-01')::text
  union all select 'Timberline Insights Oct runs', '79285', (select verified_units from stg.v_usage_by_customer_month where account_name like 'Timberline%' and month_start = '2026-10-01')::text
  union all select 'Timberline Insights product accounts', '2', (select product_accounts from stg.v_usage_by_customer_month where account_name like 'Timberline%' and month_start = '2026-10-01')::text
  union all select 'Westhaven Metrics Oct records (duplicate removed)', '31', (select record_count from stg.v_usage_by_customer_month where account_name like 'Westhaven%' and month_start = '2026-10-01')::text
  union all select 'Westhaven Metrics Oct runs', '61866', (select verified_units from stg.v_usage_by_customer_month where account_name like 'Westhaven%' and month_start = '2026-10-01')::text
  union all select 'Willow Passage Oct usage rows (unknown, not zero)', 'null', coalesce((select record_count from stg.v_usage_by_customer_month where account_name like 'Willow Passage%' and month_start = '2026-10-01')::text, 'null')
  union all select 'customers with verified Oct usage', '29', (select count(*) from stg.v_usage_by_customer_month where month_start = '2026-10-01' and record_count is not null)::text
  union all select 'all customers Oct verified runs', '1551184', (select sum(verified_units) from stg.v_usage_by_customer_month where month_start = '2026-10-01')::text
  union all select 'all customers Oct verified records (31 accounts x 31 days)', '961', (select sum(record_count) from stg.v_usage_by_customer_month where month_start = '2026-10-01')::text
  union all select 'all Oct runs incl. unassigned', '1600946', (select sum(units) from stg.v_usage_clean where service_date >= '2026-10-01')::text
) t;
