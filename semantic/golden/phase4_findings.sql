-- Phase 4 golden tests. Expected values are hand-counted from the owner's expectation list and the Phase 3 variance totals.
-- Findings: 18 rows = 9 error (platform_variance 1, usage_variance 4, amendment_not_loaded 2, missing_usage_invoice Yarrow 1, later_service_platform 1)
--                    + 3 needs_info (Willow concession, Willow missing invoice, unassigned workspace)
--                    + 6 valid_explanation (Zephyr, Alder, Crescent 15th, Willow 15th, Westhaven duplicate, Aspen no-overage invoice).
-- Customer classes: error 5 (Beacon, Cedar, Juniper Signal, Meridian, Yarrow), needs_info 1 (Willow), valid_explanation 5 (Alder, Aspen, Crescent, Westhaven, Zephyr), clean 19.
select test_name, expected, actual, (expected = actual) as pass from (
  select 'owner expectation 1: Cedar usage over-billed 3096.80 (error)' as test_name, 'MATCH' as expected, (select result from calc.v_findings_owner_expectations where n = 1) as actual
  union all select 'owner expectation 2: Meridian platform under-billed 526.03 (error)', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 2)
  union all select 'owner expectation 3: Zephyr $100 concession valid', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 3)
  union all select 'owner expectation 4: Alder void $50 valid', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 4)
  union all select 'owner expectation 5: unassigned workspace needs info', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 5)
  union all select 'owner expectation 6: Willow $250 request needs info', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 6)
  union all select 'owner expectation 7: Willow no usage invoice needs info', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 7)
  union all select 'owner expectation 8: Crescent 15th-anchor valid', 'MATCH', (select result from calc.v_findings_owner_expectations where n = 8)
  union all select 'tie-out platform under-billed', '526.03', (select findings_total::text from calc.v_findings_tieout where measure = 'platform under-billed')
  union all select 'tie-out platform over-billed', '0.00', (select round(findings_total, 2)::text from calc.v_findings_tieout where measure = 'platform over-billed')
  union all select 'tie-out usage under-billed', '6309.50', (select findings_total::text from calc.v_findings_tieout where measure = 'usage under-billed')
  union all select 'tie-out usage over-billed', '3096.80', (select findings_total::text from calc.v_findings_tieout where measure = 'usage over-billed')
  union all select 'tie-out: every measure equals Phase 3', '0', (select count(*) from calc.v_findings_tieout where findings_total <> phase3_total)::text
  union all select 'every non-zero variance has a finding (customers with a variance but no in-total finding)', '0',
        (select count(*) from calc.v_expected_vs_billed v where (v.platform_under_billed <> 0 or v.platform_over_billed <> 0 or v.usage_under_billed <> 0 or v.usage_over_billed <> 0)
           and not exists (select 1 from calc.v_findings f where f.salesforce_account_id = v.salesforce_account_id and f.in_variance_total))::text
  union all select 'customers classified', '30', (select count(*) from calc.v_customer_classification)::text
  union all select 'every customer has all 9 customer-level check results recorded', '30', (select count(*) from calc.v_customer_classification where checks_recorded = 9)::text
  union all select 'customers: error', '5', (select count(*) from calc.v_customer_classification where overall_class = 'error')::text
  union all select 'customers: needs_info', '1', (select count(*) from calc.v_customer_classification where overall_class = 'needs_info')::text
  union all select 'customers: valid_explanation', '5', (select count(*) from calc.v_customer_classification where overall_class = 'valid_explanation')::text
  union all select 'customers: clean (checked, nothing found)', '19', (select count(*) from calc.v_customer_classification where overall_class = 'clean')::text
  union all select 'findings total', '18', (select count(*) from calc.v_findings)::text
  union all select 'findings: error', '9', (select count(*) from calc.v_findings where class = 'error')::text
  union all select 'findings: needs_info', '3', (select count(*) from calc.v_findings where class = 'needs_info')::text
  union all select 'findings: valid_explanation', '6', (select count(*) from calc.v_findings where class = 'valid_explanation')::text
  union all select 'findings missing a required field', '0',
        (select count(*) from calc.v_findings where customer is null or stream is null or class is null or coalesce(contract_citation, '') = '' or coalesce(recommended_action, '') = ''
            or coalesce(owner, '') = '' or coalesce(approver, '') = '' or evidence is null or evidence = '{}'::jsonb)::text
  union all select 'error findings missing amount or direction', '0', (select count(*) from calc.v_findings where class = 'error' and (amount is null or direction is null))::text
  union all select 'materialized check matrix is fresh (equals the live view)', '0', (select count(*) from ((select * from calc.v_check_results except select * from calc.mv_check_results) union all (select * from calc.mv_check_results except select * from calc.v_check_results)) d)::text
  union all select 'platform and usage never mixed (streams present)', 'platform,usage', (select string_agg(distinct stream, ',' order by stream) from calc.v_findings)
  union all select 'unassigned workspace carries no customer assignment', '1', (select count(*) from calc.v_findings where check_code = 'unassigned_usage' and salesforce_account_id is null)::text
  union all select 'Westhaven duplicate classed valid (billing matches de-duplicated usage)', 'valid_explanation', (select class from calc.v_findings where check_code = 'duplicate_usage_record')
  union all select 'Aspen no usage invoice classed valid (no overage)', 'valid_explanation', (select class from calc.v_findings where check_code = 'missing_usage_invoice' and customer like 'Aspen%')
  union all select 'Yarrow no usage invoice classed error (overage exists)', 'error', (select class from calc.v_findings where check_code = 'missing_usage_invoice' and customer like 'Yarrow%')
  union all select 'later-service follow-up is outside the October variance total', 'false', (select in_variance_total::text from calc.v_findings where check_code = 'later_service_platform')
) t;
