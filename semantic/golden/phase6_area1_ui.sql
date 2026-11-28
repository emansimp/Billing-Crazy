-- Phase 6 Area 1 golden tests: the UI views (what the Close overview and Finding detail pages render) carry the SQL-computed figures.
-- Expected values: Q1 platform uses the day-based allocation: expected 93,060.17 = billed 92,534.14 + 526.03 catch-up; usage net of the approved $100:
--   expected 77,944.60 ; billed 74,831.90 - 100.00 = 74,731.90 ; under 6,309.50 ; over 3,096.80 ; platform under 526.03 ; totals under 6,835.53 over 3,096.80 (never netted).
-- Q2: billing corrections 5 (Cedar, Meridian, Beacon, Juniper, Yarrow) ; October entries 4 ; needs info 3 ; valid explanations 6.
-- Q3: usage reduction 3,096.80 ; usage increase 3,135.22 + 3,074.28 = 6,209.50 ; platform true-up 526.03 ; net revenue +3,638.73.
with snap as materialized (select 1)
select test_name, expected, actual, (expected = actual) as pass from (
  select 'Q1 platform expected (allocation basis)' as test_name, '93060.17' as expected, (select round(expected, 2)::text from public.ui_overview_q1 where stream = 'Platform subscription') as actual
  union all select 'Q1 platform billed (allocation basis)', '92534.14', (select round(billed, 2)::text from public.ui_overview_q1 where stream = 'Platform subscription')
  union all select 'Q1 platform under / over', '526.03/0.00', (select round(under_billed, 2) || '/' || round(over_billed, 2) from public.ui_overview_q1 where stream = 'Platform subscription')
  union all select 'Q1 usage expected net', '77944.60', (select round(expected, 2)::text from public.ui_overview_q1 where stream = 'Workflow-run usage')
  union all select 'Q1 usage billed net', '74731.90', (select round(billed, 2)::text from public.ui_overview_q1 where stream = 'Workflow-run usage')
  union all select 'Q1 usage under / over (not netted)', '6309.50/3096.80', (select round(under_billed, 2) || '/' || round(over_billed, 2) from public.ui_overview_q1 where stream = 'Workflow-run usage')
  union all select 'Q1 total under / over (not netted)', '6835.53/3096.80', (select round(under_billed, 2) || '/' || round(over_billed, 2) from public.ui_overview_q1 where stream = 'Total')
  union all select 'Q2 counts', '5/4/3/6', (select billing_corrections || '/' || october_accounting_adjustments || '/' || need_more_information || '/' || valid_explanations from public.ui_overview_q2)
  union all select 'Q3 usage accrual reduction', '3096.80', (select round(amount, 2)::text from public.ui_overview_q3 where label like 'Usage accrual reduction%')
  union all select 'Q3 usage accrual increase', '6209.50', (select round(amount, 2)::text from public.ui_overview_q3 where label like 'Usage accrual increase%')
  union all select 'Q3 platform true-up', '526.03', (select round(amount, 2)::text from public.ui_overview_q3 where label like 'Platform recognition%')
  union all select 'Q3 no contra row by default (Zephyr already reflected)', '0', (select count(*) from public.ui_overview_q3 where label like 'Contra%')::text
  union all select 'Q3 proposed entries / net revenue effect', '4/3638.73', (select proposed_entries || '/' || round(net_revenue_effect, 2) from public.ui_overview_q3_summary)
  union all select 'findings list: total / error / valid / needs info', '15/6/6/3', (select total || '/' || errors || '/' || valid_explanations || '/' || needs_info from public.ui_findings_counts)
  union all select 'labels follow the mockup: F-01 Cedar, F-02 Meridian, F-03 Zephyr', 'Cedar Harbor Labs/Meridian Process Systems/Zephyr Grove',
        (select string_agg(customer, '/' order by display_id) from public.ui_findings_list where display_id in ('F-01', 'F-02', 'F-03'))
  union all select 'F-01 amount / direction', '$3,096.80/Over-billed', (select amount_display || '/' || direction_label from public.ui_findings_list where display_id = 'F-01')
  union all select 'F-02 period and amount', 'Oct 16–31/$526.03', (select period_label || '/' || amount_display from public.ui_findings_list where display_id = 'F-02')
  union all select 'diagnosis rows are not listed as findings (amendment_not_loaded, Yarrow missing invoice)', '0', (select count(*) from public.ui_findings_list where check_code = 'amendment_not_loaded' or (check_code = 'missing_usage_invoice' and class = 'error'))::text
  union all select 'every listed finding has a detail row, evidence and math', '15/15/15', (select (select count(*) from public.ui_finding_detail) || '/' || (select count(distinct finding_id) from public.ui_finding_evidence) || '/' || (select count(distinct finding_id) from public.ui_finding_math))
  union all select 'F-01 math results', '37,742 runs|20,728 runs|$8,291.20|$11,388.00|$3,096.80 over-billed',
        (select string_agg(m.result, '|' order by m.step_no) from public.ui_finding_math m join public.ui_findings_list l using (finding_id) where l.display_id = 'F-01')
  union all select 'F-01 math calculation 1 shows the weighted allowance', '(30,000 × 15 days + 45,000 × 16 days) ÷ 31, rounded once, half up',
        (select m.calculation from public.ui_finding_math m join public.ui_findings_list l using (finding_id) where l.display_id = 'F-01' and m.step_no = 1)
  union all select 'F-01 why heading', 'Why 7,742 runs?', (select n.heading from public.ui_finding_math_notes n join public.ui_findings_list l using (finding_id) where l.display_id = 'F-01')
  union all select 'F-02 math: increment', '$526.03', (select m.result from public.ui_finding_math m join public.ui_findings_list l using (finding_id) where l.display_id = 'F-02' and m.step_no = 3)
  union all select 'F-11 (Juniper) rate evidence', 'Usage billed at $0.05 per run, contract rate is $0.16; usage under-billed', (select what_we_found from public.ui_findings_list where display_id = 'F-11')
  union all select 'F-01 evidence items (amendment, not loaded, message, billed, metering, accrual)', '6', (select count(*) from public.ui_finding_evidence e join public.ui_findings_list l using (finding_id) where l.display_id = 'F-01')::text
  union all select 'F-01 evidence cites the amendment PDF and the register', 'true',
        (select (bool_or(source_ref like 'contracts/AM-OF-2026-157.pdf%') and bool_or(source_ref like 'contract_register.csv%'))::text from public.ui_finding_evidence e join public.ui_findings_list l using (finding_id) where l.display_id = 'F-01')
  union all select 'F-01 accounting effect names the accrual JE', 'true', (select (accounting_effect like '%JE-3670271955a1fc%' and accounting_effect like '%reduce the accrual by $3,096.80%')::text from public.ui_finding_detail where display_id = 'F-01')
  union all select 'F-03 Zephyr accounting effect says no entry', 'true', (select (accounting_effect like 'No October entry%')::text from public.ui_finding_detail where display_id = 'F-03')
  union all select 'billing corrections listed', '6', (select count(*) from public.ui_billing_corrections)::text
  union all select 'billing corrections: Zephyr is already issued, no new document', 'No new document/Already issued', (select document || '/' || status from public.ui_billing_corrections where customer like 'Zephyr%')
  union all select 'billing corrections proposed with a November issue date', '5', (select count(*) from public.ui_billing_corrections where proposed_issue_date >= '2026-11-01' and proposed_issue_date < '2026-12-01')::text
  union all select 'readiness', '18/19/1/0', (select verified || '/' || total || '/' || pending || '/' || failed from public.ui_readiness)
  union all select 'readiness percentage computed in SQL', '94.7', (select verified_pct::text from public.ui_readiness)
  union all select 'snapshots are fresh: overview, findings, detail (rows differing from the live views)', '0',
        (select (select count(*) from ((select * from public.ui_overview_q1 except select * from public.ui_overview_q1_live) union all (select * from public.ui_overview_q1_live except select * from public.ui_overview_q1)) a)
              + (select count(*) from ((select to_jsonb(s) - 'decision' j from public.ui_findings_list s except select to_jsonb(l) - 'decision' from public.ui_findings_list_live l) union all (select to_jsonb(l) - 'decision' from public.ui_findings_list_live l except select to_jsonb(s) - 'decision' from public.ui_findings_list s)) b)  -- decision is overlaid live by the app, so the snapshot value may lag
              + (select count(*) from ((select * from public.ui_overview_q3 except select * from public.ui_overview_q3_live) union all (select * from public.ui_overview_q3_live except select * from public.ui_overview_q3)) c))::text
  union all select 'a run is recorded (footer source)', 'true', (select (count(*) >= 1)::text from ops.runs)
  union all select 'browser role cannot read the live logic views or raw/calc tables', '0',
        (select count(*) from information_schema.role_table_grants where grantee = 'anon' and (table_schema in ('raw', 'calc', 'ref', 'stg', 'ops') or table_name like '%\_live'))::text
) t;
