-- Phase 6 Area 3 golden tests: the journal screens read live views; baseline = policy defaults, nothing approved.
-- Entries: JE01 Cedar 3,096.80 ; JE02 Juniper 3,135.22 ; JE03 Meridian 526.03 + reclass 526.03 ; JE04 Yarrow 3,074.28 ; JE05 Zephyr reference 100.00 posts nothing by default.
--   debits = credits = 3,096.80 + 3,135.22 + 526.03 + 526.03 + 3,074.28 = 10,358.36 ; net revenue = -3,096.80 + 3,135.22 + 3,074.28 + 526.03 = +3,638.73
--   (usage 4010 +3,112.70, platform 4000 +526.03). Contra and write-off effects 0. The override behaviours (reason required, approval withdrawn on change,
--   write-off blocks export, Zephyr contra carries a double-count warning) were verified in a rolled-back run and are asserted structurally here.
with ent as materialized (select * from public.ui_je_entries), ln as materialized (select * from public.ui_je_lines), op as materialized (select * from public.ui_je_options),
     sm as materialized (select * from public.ui_je_summary), ex as materialized (select * from public.ui_export_checks), el as materialized (select * from public.ui_export_lines)
select test_name, expected, actual, (expected = actual) as pass from (
  select 'entry cards (4 posting + Zephyr selector)' as test_name, '5' as expected, (select count(*) from ent)::text as actual
  union all select 'entry order and customers', 'Cedar Harbor Labs|Juniper Signal Works|Meridian Process Systems|Yarrow Ridge|Zephyr Grove', (select string_agg(split_part(customer, ',', 1), '|' order by external_id) from ent)
  union all select 'entry finding labels', 'F-01|F-11|F-02|F-12|F-03', (select string_agg(display_id, '|' order by external_id) from ent)
  union all select 'all entries start as Draft', '5', (select count(*) from ent where status = 'Draft')::text
  union all select 'adjustment lines (incl. reclass and Zephyr reference)', '6', (select count(*) from ln)::text
  union all select 'default treatments', 'accrual,accrual,accrual,policy,accrual,none', (select string_agg(selected_treatment, ',' order by external_id, line_order) from ln)
  union all select 'Cedar line accounts and amount', '4010 Usage revenue/1150 Unbilled usage receivable/3096.80', (select debit_label || '/' || credit_label || '/' || round(amount, 2) from ln where customer like 'Cedar%')
  union all select 'Juniper line accounts (missed revenue accrual only)', '1150 Unbilled usage receivable/4010 Usage revenue/3135.22', (select debit_label || '/' || credit_label || '/' || round(amount, 2) from ln where customer like 'Juniper%')
  union all select 'Meridian true-up and reclass lines', '2200 Deferred platform revenue>4000 Platform revenue|1160 Platform contract asset>2200 Deferred platform revenue', (select string_agg(debit_label || '>' || credit_label, '|' order by line_order) from ln where customer like 'Meridian%')
  union all select 'Meridian reclass is fixed by policy, amount 526.03', 'true/526.03', (select fixed_by_policy || '/' || round(amount, 2) from ln where adjustment_kind = 'contract_asset_reclass')
  union all select 'Yarrow line', '1150 Unbilled usage receivable/4010 Usage revenue/3074.28', (select debit_label || '/' || credit_label || '/' || round(amount, 2) from ln where customer like 'Yarrow%')
  union all select 'Zephyr reference line posts nothing by default', 'none/false/100.00', (select selected_treatment || '/' || posts_entry || '/' || round(amount, 2) from ln where customer like 'Zephyr%')
  union all select 'no default line uses a placeholder account', '0', (select count(*) from ln where uses_placeholder_account and posts_entry)::text
  union all select 'selector options: usage reduction has accrual/contra/writeoff', 'accrual,contra,writeoff', (select string_agg(option_treatment, ',' order by option_treatment) from op where line_id like 'ADJ:usage_variance:0011e97a%')
  union all select 'selector options: missed revenue is accrual only (Juniper, Yarrow)', 'accrual|accrual', (select string_agg(option_treatment, ',') from op where line_id = 'ADJ:usage_variance:001ff8487ef5b3dAAA') || '|' || (select string_agg(option_treatment, ',') from op where line_id = 'ADJ:usage_variance:001e11d0aa846d7AAA')
  union all select 'selector options: platform true-up is accrual only', 'accrual', (select string_agg(option_treatment, ',') from op where line_id like 'ADJ:platform_variance:%')
  union all select 'selector options: Zephyr none/accrual/contra/writeoff', 'accrual,contra,none,writeoff', (select string_agg(option_treatment, ',' order by option_treatment) from op where line_id like 'ADJ:concession:%')
  union all select 'every non-default option requires a reason (Cedar 2 + Zephyr 3)', '5', (select count(*) filter (where requires_reason) from op)::text
  union all select 'placeholder options flagged 4090 and 6900', 'true|true', (select bool_or(uses_placeholder_account)::text from op where option_treatment = 'contra') || '|' || (select bool_or(uses_placeholder_account)::text from op where option_treatment = 'writeoff')
  union all select 'Zephyr non-default options carry a double-count warning', '3', (select count(*) from op where line_id like 'ADJ:concession:%' and warning like 'DOUBLE-COUNT%')::text
  union all select 'summary debits = credits, balanced', '10358.36/10358.36/true', (select round(debits, 2) || '/' || round(credits, 2) || '/' || balanced from sm)
  union all select 'summary entries and lines', '4/10', (select entries || '/' || lines from sm)
  union all select 'net revenue effect and split', '3638.73/3112.70/526.03', (select round(net_revenue_effect, 2) || '/' || round(usage_effect, 2) || '/' || round(platform_effect, 2) from sm)
  union all select 'contra and write-off effects are zero by default', '0.00/0.00', (select round(contra_effect, 2) || '/' || round(writeoff_effect, 2) from sm)
  union all select 'summary flags at baseline (writeoff, overrides, double count, placeholder lines, approved)', '0/0/0/0/0', (select writeoff_lines || '/' || overrides || '/' || double_count_lines || '/' || placeholder_lines || '/' || approved_entries from sm)
  union all select 'export checks at baseline', 'Controller approval:pending', (select string_agg(check_name || ':' || status, '; ') from ex where status <> 'pass')
  union all select 'export lines: 10, each with one of debit or credit', '10/0', (select count(*) || '/' || count(*) filter (where (debit is null) = (credit is null)) from el)
  union all select 'export External ID repeats on every line (lines per entry)', '2|2|4|2', (select string_agg(n::text, '|' order by external_id) from (select external_id, count(*) n from el group by 1) x)
  union all select 'export has no total row (rows whose External ID is not a BR- id)', '0', (select count(*) from el where external_id not like 'BR-OCT26-JE%')::text
  union all select 'chart of accounts: placeholders flagged', '4090,6900', (select string_agg(account_number, ',' order by account_number) from public.ui_coa where placeholder)
  union all select 'chart of accounts: accounts used in the file', '1150,1160,2200,4000,4010', (select string_agg(account_number, ',' order by account_number) from public.ui_coa where used_in_export)
  union all select 'run history has a recorded run with commit and totals', 'true', (select (count(*) >= 1 and bool_and(git_commit is not null) and bool_and(output_totals is not null))::text from public.ui_run_history)
  union all select 'latest run is Complete', 'Complete', (select result from public.ui_run_history order by run_id desc limit 1)
  union all select 'billing corrections snapshot carries finding_id for the live status overlay', '5', (select count(finding_id) from public.ui_billing_corrections)::text
  union all select 'decision history view exists and is readable', 'true', (select (count(*) >= 0)::text from public.ui_finding_decision_log)
  union all select 'write RPCs are not executable by the browser roles', '0',
        (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname in ('ui_set_treatment', 'ui_clear_treatment', 'ui_approve_entries', 'ui_revoke_approvals', 'ui_record_run', 'ui_refresh_snapshots', 'ui_reset_demo', 'ui_record_finding_decision')
            and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')))::text
  union all select 'no leftover test state (overrides, approvals)', '0/0', (select (select count(*) from ref.adjustment_treatments) || '/' || (select count(*) from ref.journal_approvals))
) t;
