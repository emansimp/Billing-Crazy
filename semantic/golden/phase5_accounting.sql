-- Phase 5 golden tests (hand-calculated; arithmetic in comments).
-- TIE-OUTS: GL 4000 Oct = plan = base 93,764.36 ; expected incl. Meridian increment 93,764.36 + 526.03 = 94,290.39 ; GL - expected = -526.03 (Meridian only)
--   usage accrual GL 4010 = 1150 = 74,831.90 ; expected net 77,944.60 ; GL - expected = -3,112.70 = +3,096.80 (Cedar) -3,135.22 (Juniper) -3,074.28 (Yarrow)
-- ENTRIES: JE01 Cedar Dr 4010 / Cr 1150 3,096.80 ; JE02 Juniper Dr 1150 / Cr 4010 3,135.22 ; JE03 Meridian Dr 2200 / Cr 4000 526.03 + Dr 1160 / Cr 2200 526.03 ; JE04 Yarrow Dr 1150 / Cr 4010 3,074.28
--   debits = 3,096.80 + 3,135.22 + 526.03 + 526.03 + 3,074.28 = 10,358.36 = credits
--   Meridian reclass: opening 2200 credit 54.79 ; October invoice credit 4,000.00 ; base recognition debit 4,076.71 -> net debit before reclass = 4,076.71 + 54.79 - ... = 21.92 (baseline reclass in GL)
--   after the 526.03 true-up the net debit is 21.92 + 526.03 = 547.95 ; existing 1160 = 21.92 ; incremental reclass = 547.95 - 21.92 = 526.03
-- NET REVENUE EFFECT: 4010 = -3,096.80 + 3,135.22 + 3,074.28 = +3,112.70 ; 4000 = +526.03 ; total +3,638.73 ; contra 4090 0.00 ; write-off 6900 0.00
-- BILLING DOCUMENTS (November): Cedar credit note -3,096.80 ; Juniper +3,135.22 ; Yarrow +3,074.28 ; Beacon +100.00 (no October entry) ; Meridian +526.03 ; AR effect = 3,738.73
with jl as materialized (select * from calc.v_journal_lines),
  al as materialized (select * from calc.v_adjustment_lines),
  rev as materialized (select * from calc.v_revenue_effect),
  bc as materialized (select * from calc.v_billing_corrections),
  rfa as materialized (select * from calc.v_rollforward_after_proposed),
  tp as materialized (select * from calc.v_tieout_platform_recognition),
  tu as materialized (select * from calc.v_tieout_usage_accrual),
  rf as materialized (select * from calc.v_rollforward),
  rc as materialized (select * from calc.v_reclass_incremental),
  ac as materialized (select * from calc.v_adjustments_considered),
  ctl as materialized (select * from calc.v_controls),
  ec as materialized (select * from calc.v_journal_export_checks),
  eu as materialized (select * from calc.v_expected_usage)
select test_name, expected, actual, (expected = actual) as pass from (
  select 'TIE-OUT platform: GL 4000 October' as test_name, '93764.36' as expected, (select sum(gl_cr_4000)::text from tp) as actual
  union all select 'TIE-OUT platform: revenue plan October recognized', '93764.36', (select sum(plan_recognized)::text from tp)
  union all select 'TIE-OUT platform: GL minus plan', '0.00', (select sum(gl_minus_plan)::text from tp)
  union all select 'TIE-OUT platform: expected incl. increment', '94290.39', (select sum(expected_total)::text from tp)
  union all select 'TIE-OUT platform: GL minus expected', '-526.03', (select sum(gl_minus_expected)::text from tp)
  union all select 'TIE-OUT platform: customers with a difference (Meridian)', '1', (select count(*) from tp where gl_minus_expected <> 0)::text
  union all select 'TIE-OUT usage: GL 4010 October', '74831.90', (select sum(gl_cr_4010)::text from tu)
  union all select 'TIE-OUT usage: GL 1150 accrual debits equal 4010 credits', '0.00', (select sum(legs_difference)::text from tu)
  union all select 'TIE-OUT usage: expected net', '77944.60', (select sum(expected_usage_net)::text from tu)
  union all select 'TIE-OUT usage: GL minus expected', '-3112.70', (select sum(gl_minus_expected)::text from tu)
  union all select 'TIE-OUT usage: customers with a difference (Cedar, Juniper, Yarrow)', '3', (select count(*) from tu where gl_minus_expected <> 0)::text
  union all select 'ROLLFORWARD: customer-account rows (30 customers x 4 accounts)', '120', (select count(*) from rf)::text
  union all select 'ROLLFORWARD: rows not tying to sub-ledgers', '0', (select count(*) from rf where tie_difference <> 0)::text
  union all select 'ENTRIES: entries / lines', '4/10', (select count(distinct external_id) || '/' || count(*) from jl)
  union all select 'ENTRIES: JE01 Cedar Dr 4010', '3096.80', (select debit::text from jl where external_id = 'BR-OCT26-JE01' and account_number = '4010')
  union all select 'ENTRIES: JE01 Cedar Cr 1150', '3096.80', (select credit::text from jl where external_id = 'BR-OCT26-JE01' and account_number = '1150')
  union all select 'ENTRIES: JE02 Juniper Dr 1150', '3135.22', (select debit::text from jl where external_id = 'BR-OCT26-JE02' and account_number = '1150')
  union all select 'ENTRIES: JE02 Juniper Cr 4010', '3135.22', (select credit::text from jl where external_id = 'BR-OCT26-JE02' and account_number = '4010')
  union all select 'ENTRIES: JE03 Meridian Dr 2200 true-up', '526.03', (select debit::text from jl where external_id = 'BR-OCT26-JE03' and account_number = '2200' and debit is not null)
  union all select 'ENTRIES: JE03 Meridian Cr 4000 true-up', '526.03', (select credit::text from jl where external_id = 'BR-OCT26-JE03' and account_number = '4000')
  union all select 'ENTRIES: JE03 Meridian Dr 1160 incremental reclass', '526.03', (select debit::text from jl where external_id = 'BR-OCT26-JE03' and account_number = '1160')
  union all select 'ENTRIES: JE03 Meridian Cr 2200 incremental reclass', '526.03', (select credit::text from jl where external_id = 'BR-OCT26-JE03' and account_number = '2200' and credit is not null)
  union all select 'ENTRIES: JE04 Yarrow Dr 1150', '3074.28', (select debit::text from jl where external_id = 'BR-OCT26-JE04' and account_number = '1150')
  union all select 'ENTRIES: JE04 Yarrow Cr 4010', '3074.28', (select credit::text from jl where external_id = 'BR-OCT26-JE04' and account_number = '4010')
  union all select 'ENTRIES: total debits = total credits', '10358.36/10358.36', (select sum(debit)::text || '/' || sum(credit)::text from jl)
  union all select 'ENTRIES: every entry balances (unbalanced entries)', '0', (select count(*) from (select external_id from jl group by 1 having sum(coalesce(debit, 0)) <> sum(coalesce(credit, 0))) x)::text
  union all select 'ENTRIES: each line has a debit or a credit, never both or neither', '0', (select count(*) from jl where (debit is null) = (credit is null))::text
  union all select 'ENTRIES: all in the October posting period', 'Oct 2026', (select string_agg(distinct posting_period, ',') from jl)
  union all select 'ENTRIES: all dated 2026-10-31', '2026-10-31', (select string_agg(distinct date::text, ',') from jl)
  union all select 'RECLASS: required 1160 after true-up (21.92 + 526.03)', '547.95', (select round(required_1160, 2)::text from rc r join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%')
  union all select 'RECLASS: existing baseline 1160', '21.92', (select round(existing_1160, 2)::text from rc r join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%')
  union all select 'RECLASS: incremental change only (Meridian)', '526.03', (select round(incremental_reclass, 2)::text from rc r join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%')
  union all select 'RECLASS: customers needing any incremental reclass', '1', (select count(*) from rc where incremental_reclass <> 0)::text
  union all select 'SEPARATE LINES: over-billed accrual reductions', '1', (select count(*) from al where adjustment_kind = 'usage_reduce')::text
  union all select 'SEPARATE LINES: under-billed accruals (usage_increase)', '2', (select count(*) from al where adjustment_kind = 'usage_increase')::text
  union all select 'SEPARATE LINES: platform true-up', '1', (select count(*) from al where adjustment_kind = 'platform_increase')::text
  union all select 'NO ENTRY: Beacon (billing correction only) has no adjustment line', '0', (select count(*) from al where customer like 'Beacon%')::text
  union all select 'NO ENTRY: Zephyr (accrual already net) has no adjustment line', '0', (select count(*) from al where customer like 'Zephyr%')::text
  union all select 'NO ENTRY: Zephyr reviewed, reason recorded', '1', (select count(*) from ac where customer like 'Zephyr%' and reason like '%reduce revenue twice%')::text
  union all select 'NO ENTRY: Willow unapproved concession authorizes nothing', '1', (select count(*) from ac where customer like 'Willow%' and check_code = 'concession' and reason like '%not approved%')::text
  union all select 'NO ENTRY: no line posts to contra 4090 or write-off 6900 by default', '0', (select count(*) from jl where account_number in ('4090', '6900'))::text
  union all select 'NET EFFECT: usage revenue 4010', '3112.70', (select credit_minus_debit::text from rev where account_number = '4010')
  union all select 'NET EFFECT: platform revenue 4000', '526.03', (select credit_minus_debit::text from rev where account_number = '4000')
  union all select 'NET EFFECT: contra 4090', '0', (select credit_minus_debit::text from rev where account_number = '4090')
  union all select 'NET EFFECT: write-off 6900', '0', (select credit_minus_debit::text from rev where account_number = '6900')
  union all select 'NET EFFECT: total revenue (4000 + 4010)', '3638.73', (select sum(credit_minus_debit)::text from rev where account_number in ('4000', '4010'))
  union all select 'AFTER PROPOSED: 1150 closing = expected net usage for every customer (rows differing)', '0',
        (select count(*) from rfa r join eu e using (salesforce_account_id) where r.account_number = '1150' and r.closing_after_proposed <> e.expected_usage_net)::text
  union all select 'AFTER PROPOSED: no customer left with a net debit in 2200', '0', (select count(*) from rfa where account_number = '2200' and closing_after_proposed > 0)::text
  union all select 'AFTER PROPOSED: 4000 recognition (GL + true-up) = expected for all', '94290.39', (select (sum(gl_cr_4000) + (select credit_minus_debit from rev where account_number = '4000'))::text from tp)
  union all select 'BILLING: documents proposed', '5', (select count(*) from bc)::text
  union all select 'BILLING: all dated in November, posting period Nov 2026', '11/Nov 2026', (select string_agg(distinct extract(month from proposed_issue_date)::text || '/' || posting_period, ',') from bc)
  union all select 'BILLING: Cedar linked credit note', 'linked credit note/3096.80/-3096.80', (select document_type || '/' || amount || '/' || ar_effect from bc where customer like 'Cedar%')
  union all select 'BILLING: Juniper supplemental invoice', 'supplemental invoice/3135.22', (select document_type || '/' || amount from bc where customer like 'Juniper%')
  union all select 'BILLING: Yarrow supplemental invoice', 'supplemental invoice/3074.28', (select document_type || '/' || amount from bc where customer like 'Yarrow%')
  union all select 'BILLING: Beacon supplemental invoice with zero October revenue effect', 'supplemental invoice/100.00/0', (select document_type || '/' || amount || '/' || october_revenue_effect from bc where customer like 'Beacon%')
  union all select 'BILLING: Meridian supplemental invoice', 'supplemental invoice/526.03', (select document_type || '/' || amount from bc where customer like 'Meridian%')
  union all select 'BILLING: net AR effect', '3738.73', (select sum(ar_effect)::text from bc)
  union all select 'BILLING: never in the October posting period', '0', (select count(*) from bc where posting_period = 'Oct 2026')::text
  union all select 'TREATMENT: usage_reduce contra pair', '4090/1150', (select debit_account || '/' || credit_account from ref.treatment_account_pairs where adjustment_kind = 'usage_reduce' and treatment = 'contra')
  union all select 'TREATMENT: usage_reduce write-off pair', '6900/1150', (select debit_account || '/' || credit_account from ref.treatment_account_pairs where adjustment_kind = 'usage_reduce' and treatment = 'writeoff')
  union all select 'TREATMENT: missed revenue can only be accrued (usage_increase, platform_increase)', 'accrual;accrual',
        (select string_agg(treatment, ';') from ref.treatment_account_pairs where adjustment_kind in ('usage_increase', 'platform_increase'))
  union all select 'TREATMENT: override requires a non-blank reason (table constraint)', '1', (select count(*) from pg_constraint where conrelid = 'ref.adjustment_treatments'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%btrim%')::text
  union all select 'TREATMENT: set_treatment rejects a missing reason', 'true', (select (prosrc like '%override requires a reason%')::text from pg_proc where proname = 'set_treatment')
  union all select 'TREATMENT: no leftover test overrides', '0', (select count(*) from ref.adjustment_treatments)::text
  union all select 'PLACEHOLDERS: 4090 and 6900 flagged in the chart', '4090,6900', (select string_agg(account_number, ',' order by account_number) from ref.chart_of_accounts where placeholder)
  union all select 'PLACEHOLDERS: chart matches the /semantic file (8 accounts, version 1)', '8/1', (select count(*) || '/' || max(coa_version) from ref.chart_of_accounts)
  union all select 'PERIODS: September closed, October open', 'closed/open', (select (select status from ref.accounting_periods where period = 'Sep 2026') || '/' || (select status from ref.accounting_periods where period = 'Oct 2026'))
  union all select 'EXPORT CHECK: journals balance', 'pass', (select status from ec where check_name = 'Each journal balances')
  union all select 'EXPORT CHECK: October period open', 'pass', (select status from ec where check_name = 'Posting period is open')
  union all select 'EXPORT CHECK: placeholder accounts (none used by default)', 'pass', (select status from ec where check_name = 'Placeholder accounts used')
  union all select 'EXPORT CHECK: Controller approval pending until approved', 'pending', (select status from ec where check_name = 'Controller approval')
  union all select 'EXPORT CHECK: no write-off', 'pass', (select status from ec where check_name = 'No write-off treatments selected')
  union all select 'CONTROLS: count (A 10 + B 5 + C 4)', '19', (select count(*) from ctl)::text
  union all select 'CONTROLS: every control has a status', '0', (select count(*) from ctl where status not in ('pass', 'fail', 'pending'))::text
  union all select 'CONTROLS: pass', '18', (select count(*) from ctl where status = 'pass')::text
  union all select 'CONTROLS: fail', '0', (select count(*) from ctl where status = 'fail')::text
  union all select 'CONTROLS: pending (B4 unverified workspace, open item O-1)', 'B4', (select string_agg(control_id, ',') from ctl where status = 'pending')
  union all select 'CONTROLS: ids A1-A10, B1-B5, C1-C4', 'A1,A10,A2,A3,A4,A5,A6,A7,A8,A9,B1,B2,B3,B4,B5,C1,C2,C3,C4', (select string_agg(control_id, ',' order by control_id) from ctl)
) t;
