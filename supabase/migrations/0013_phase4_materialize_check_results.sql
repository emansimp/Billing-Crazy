-- 0013: materialize the check matrix (the full evaluation takes ~10 s). The definition stays in calc.v_check_results;
-- findings/classification views read the materialized copy. Refresh after any data reload: select calc.refresh_findings();
create materialized view calc.mv_check_results as select * from calc.v_check_results;
create unique index on calc.mv_check_results (check_code, coalesce(salesforce_account_id, 'workspace'));
create function calc.refresh_findings() returns void language sql as 'refresh materialized view calc.mv_check_results';

create or replace view calc.v_findings as
select check_code || ':' || coalesce(salesforce_account_id, 'workspace') as finding_id, *
from calc.mv_check_results where class <> 'pass';

-- All 30 customers classified. Severity: error > needs_info > valid_explanation > clean.
create or replace view calc.v_customer_classification as
select c.salesforce_account_id, c.account_name,
       count(r.*) as checks_recorded,
       count(*) filter (where r.class = 'pass') as checks_passed,
       count(*) filter (where r.class = 'error') as errors,
       count(*) filter (where r.class = 'needs_info') as needs_info,
       count(*) filter (where r.class = 'valid_explanation') as valid_explanations,
       case when count(*) filter (where r.class = 'error') > 0 then 'error'
            when count(*) filter (where r.class = 'needs_info') > 0 then 'needs_info'
            when count(*) filter (where r.class = 'valid_explanation') > 0 then 'valid_explanation' else 'clean' end as overall_class,
       array_agg(r.check_code order by r.check_code) filter (where r.class <> 'pass') as finding_checks
from stg.customers c left join calc.mv_check_results r using (salesforce_account_id)
group by c.salesforce_account_id, c.account_name;

-- Tie-out: findings counted in the variance total vs the Phase 3 expected-vs-billed totals.
create or replace view calc.v_findings_tieout as
select 'platform under-billed' as measure,
       (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'platform' and direction = 'under') as findings_total,
       (select round(sum(platform_under_billed), 2) from calc.v_expected_vs_billed) as phase3_total
union all select 'platform over-billed', (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'platform' and direction = 'over'), (select round(sum(platform_over_billed), 2) from calc.v_expected_vs_billed)
union all select 'usage under-billed', (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'usage' and direction = 'under'), (select round(sum(usage_under_billed), 2) from calc.v_expected_vs_billed)
union all select 'usage over-billed', (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'usage' and direction = 'over'), (select round(sum(usage_over_billed), 2) from calc.v_expected_vs_billed);

-- The owner's expectation list vs what the data says (a disagreement is reported, never forced).
create or replace view calc.v_findings_owner_expectations as
with ex(n, customer_like, check_code, expected_class, expected_amount, expected_direction, description) as (values
 (1, 'Cedar%',   'usage_variance',          'error',             3096.80::numeric, 'over',  'Cedar Harbor usage over-billed $3,096.80'),
 (2, 'Meridian%','platform_variance',       'error',             526.03,           'under', 'Meridian platform under-billed $526.03'),
 (3, 'Zephyr%',  'concession',              'valid_explanation', 100.00,           null,    'Zephyr $100 concession valid'),
 (4, 'Alder%',   'void_credit_note',        'valid_explanation', 50.00,            null,    'Alder void $50 credit valid'),
 (5, 'UNASSIGNED%','unassigned_usage',      'needs_info',        null,             null,    'Unassigned workspace needs info'),
 (6, 'Willow%',  'concession',              'needs_info',        250.00,           null,    'Willow $250 concession request, no approval: needs info'),
 (7, 'Willow%',  'missing_usage_invoice',   'needs_info',        null,             null,    'Willow no October usage invoice: needs info'),
 (8, 'Crescent%','15th_anchor_timing',      'valid_explanation', null,             null,    'Crescent Shore 15th-anchor valid'))
select ex.n, ex.description, ex.expected_class, f.class as actual_class, ex.expected_amount, f.amount as actual_amount, f.direction as actual_direction,
       case when f.class is not distinct from ex.expected_class and (ex.expected_amount is null or f.amount = ex.expected_amount)
                 and (ex.expected_direction is null or f.direction = ex.expected_direction) then 'MATCH' else 'DISAGREES' end as result
from ex left join calc.mv_check_results r on r.check_code = ex.check_code and r.customer like ex.customer_like
left join calc.v_findings f on f.finding_id = r.check_code || ':' || coalesce(r.salesforce_account_id, 'workspace');


revoke all on all tables in schema calc from anon, authenticated;
