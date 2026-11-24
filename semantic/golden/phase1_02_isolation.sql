-- Unverified usage: pa_676b6b455e0887 is isolated and never assigned to any customer by elimination.
select test_name, expected, actual, (expected = actual) as pass from (
  select 'unassigned product accounts' as test_name, 'pa_676b6b455e0887' as expected, (select string_agg(distinct product_account_id, ',') from stg.v_usage_unassigned) as actual
  union all select 'unassigned records (all dates)', '47', (select count(*) from stg.v_usage_unassigned)::text
  union all select 'unassigned records in October', '31', (select count(*) from stg.v_usage_unassigned where service_date >= '2026-10-01')::text
  union all select 'unassigned October runs', '49762', (select sum(units) from stg.v_usage_unassigned where service_date >= '2026-10-01')::text
  union all select 'unassigned September runs (onboarding, none expected)', '0', (select coalesce(sum(units), 0) from stg.v_usage_unassigned where service_date < '2026-10-01')::text
  union all select 'unassigned account has no salesforce_account_id in any record', '0', (select count(*) from stg.v_usage_unassigned where salesforce_account_id is not null)::text
  union all select 'unassigned records leaking into verified usage', '0', (select count(*) from stg.usage_verified where product_account_id = 'pa_676b6b455e0887')::text
  union all select 'unassigned account appears in a customer crosswalk row', '0', (select count(*) from stg.v_customer_crosswalk where 'pa_676b6b455e0887' = any(product_account_ids))::text
  union all select 'unassigned account appears in per-customer daily aggregate', '0', (select count(*) from stg.v_usage_by_customer_day where 'pa_676b6b455e0887' = any(product_account_ids))::text
  union all select 'verified + unassigned units = clean units', 'true', ((select sum(units) from stg.usage_verified) + (select sum(units) from stg.v_usage_unassigned) = (select sum(units) from stg.v_usage_clean))::text
  union all select 'Willow Passage left without a mapped account (no elimination)', '0', (select product_account_count from stg.v_customer_crosswalk where account_name like 'Willow Passage%')::text
) t;
