-- 0016 (Phase 5, part 3): v_controls (the 19 controls from the Controls mockup) and a faster pre-export check view.
-- Status vocabulary: pass | fail | pending. 'pending' = cannot be passed yet because evidence is outstanding (open item), not a calculation failure.

create or replace view calc.v_journal_lines as
select l.external_id, l.entry_date as date, l.posting_period, x.account_number,
       a.account_number || ' ' || a.account_name as account_label, a.placeholder as account_is_placeholder,
       x.debit, x.credit,
       replace(l.finding_check, '_', ' ') || ' - ' || l.customer || ': ' || case l.adjustment_kind
         when 'usage_reduce' then 'reduce October usage accrual' when 'usage_increase' then 'accrue missing October usage revenue'
         when 'platform_increase' then 'recognize October platform upgrade true-up' when 'contract_asset_reclass' then 'contract asset reclass for increment (incremental change only)'
         when 'concession_credit' then 'approved concession' end
         || ' [treatment: ' || l.selected_treatment || '] basis: ' || l.calc_basis as memo,
       l.netsuite_customer_internal_id as name, l.line_id, l.line_order, x.side_order
from calc.v_adjustment_lines l
cross join lateral (values (l.debit_account, l.amount, null::numeric, 1), (l.credit_account, null::numeric, l.amount, 2)) as x(account_number, debit, credit, side_order)
join ref.chart_of_accounts a on a.account_number = x.account_number
where l.treatment_valid;

create or replace view calc.v_journal_export_checks as
with jl as materialized (select * from calc.v_journal_lines),
     al as materialized (select * from calc.v_adjustment_lines),
     bal as (select external_id, sum(coalesce(debit, 0)) d, sum(coalesce(credit, 0)) c from jl group by 1),
     ap as (select count(*) n from ref.journal_approvals a where exists (select 1 from jl where jl.external_id = a.external_id))
select 'Each journal balances' as check_name,
       case when exists (select 1 from bal where d <> c) then 'fail' else 'pass' end as status,
       (select count(*) || ' entries, ' || (select count(*) from jl) || ' lines, debits ' || sum(d) || ' = credits ' || sum(c) from bal) as detail
union all select 'Posting period is open',
       case when exists (select 1 from jl join ref.accounting_periods p on p.period = jl.posting_period where p.status = 'closed') then 'fail'
            when exists (select 1 from jl left join ref.accounting_periods p on p.period = jl.posting_period where p.period is null) then 'warning' else 'pass' end,
       (select string_agg(distinct jl.posting_period || ' is ' || p.status || ' (' || p.source || ')', '; ') from jl join ref.accounting_periods p on p.period = jl.posting_period)
union all select 'Placeholder accounts used',
       case when exists (select 1 from jl where account_is_placeholder) then 'warning' else 'pass' end,
       coalesce((select string_agg(distinct account_label || ' (PLACEHOLDER)', '; ') from jl where account_is_placeholder), 'none (default treatments use only supplied accounts)')
union all select 'Controller approval',
       case when (select count(distinct external_id) from jl) > 0 and (select n from ap) = (select count(distinct external_id) from jl) then 'pass' else 'pending' end,
       (select n from ap) || ' of ' || (select count(distinct external_id) from jl) || ' entries approved'
union all select 'No write-off treatments selected',
       case when exists (select 1 from al where selected_treatment = 'writeoff') then 'fail' else 'pass' end,
       'write-off is outside exercise policy and blocks export without explicit approval'
union all select 'Every override has a reason and an allowed treatment',
       case when exists (select 1 from al where not treatment_valid or (treatment_overridden and coalesce(btrim(override_reason), '') = '')) then 'fail' else 'pass' end,
       (select count(*) from al where treatment_overridden) || ' overrides';

create or replace view calc.v_controls as
with m as (select * from public.load_manifest_check),
recon as materialized (select * from stg.v_usage_batch_reconciliation),
gl_j as (select internal_id, sum(debit) d, sum(credit) c from raw.netsuite_gl_detail group by 1),
plan_oct as (select p.*, (select sum(g.credit - g.debit) from raw.netsuite_gl_detail g where g.internal_id = p.journal_internal_id and g.account_number = '4000') as gl_amount
             from raw.netsuite_revenue_plan_detail p where p.posting_period = 'Oct 2026' and p.recognized_amount > 0),
inv as (select i.id, i.total, (select sum(g.debit) from raw.netsuite_gl_detail g where g.external_source_id = i.id and g.account_number = '1100') as gl_dr,
               (select sum(g.credit) from raw.netsuite_gl_detail g where g.external_source_id = i.id and g.account_number in ('1150', '2200')) as gl_cr, i.created
        from raw.stripe_invoices i),
two as (select s.salesforce_account_id from stg.v_customer_crosswalk s where s.product_account_count > 1),
two_chk as (select count(*) customers,
              count(*) filter (where (select sum(units) from stg.usage_verified u where u.salesforce_account_id = t.salesforce_account_id and u.service_date >= '2026-10-01')
                                   = (select verified_units from calc.verified_usage_month v where v.salesforce_account_id = t.salesforce_account_id and v.month_start = '2026-10-01')) as ok,
              string_agg(c.account_name, ', ') as names
            from two t join stg.customers c using (salesforce_account_id)),
un as (select count(distinct product_account_id) ws, count(*) filter (where service_date >= '2026-10-01') oct_records, coalesce(sum(units) filter (where service_date >= '2026-10-01'), 0) oct_units from stg.v_usage_unassigned)
select * from (
  -- A. Source completeness against the stated row counts
  select 'A1' as control_id, 'A. Source completeness' as control_group, 'Contract register rows' as control_name, expected_rows::text as expected, db_rows::text as found,
         case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end as status, 'contract_register.csv' as source, basis as detail from m where source_file = 'contract_register.csv'
  union all select 'A2', 'A. Source completeness', 'Salesforce accounts', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'salesforce_accounts.csv', basis from m where source_file = 'salesforce_accounts.csv'
  union all select 'A3', 'A. Source completeness', 'Product account mappings', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'product_account_mapping.csv', basis from m where source_file = 'product_account_mapping.csv'
  union all select 'A4', 'A. Source completeness', 'Stripe invoices', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'stripe_invoices.csv', basis from m where source_file = 'stripe_invoices.csv'
  union all select 'A5', 'A. Source completeness', 'Stripe invoice lines', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'stripe_invoice_lines.csv', basis from m where source_file = 'stripe_invoice_lines.csv'
  union all select 'A6', 'A. Source completeness', 'Stripe credit notes and lines', '2 and 2',
         (select db_rows from m where source_file = 'stripe_credit_notes.csv') || ' and ' || (select db_rows from m where source_file = 'stripe_credit_note_lines.csv'),
         case when (select db_rows from m where source_file = 'stripe_credit_notes.csv') = 2 and (select db_rows from m where source_file = 'stripe_credit_note_lines.csv') = 2 then 'pass' else 'fail' end,
         'stripe_credit_notes.csv, stripe_credit_note_lines.csv', 'START_HERE p5: 2 notes, 2 lines'
  union all select 'A7', 'A. Source completeness', 'NetSuite GL posting lines', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'netsuite_gl_detail.csv', basis from m where source_file = 'netsuite_gl_detail.csv'
  union all select 'A8', 'A. Source completeness', 'NetSuite opening balance rows', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'netsuite_opening_balances.csv', basis from m where source_file = 'netsuite_opening_balances.csv'
  union all select 'A9', 'A. Source completeness', 'NetSuite revenue plan rows', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'netsuite_revenue_plan_detail.csv', basis from m where source_file = 'netsuite_revenue_plan_detail.csv'
  union all select 'A10', 'A. Source completeness', 'Usage batch control dates', expected_rows::text, db_rows::text, case when db_rows = expected_rows and csv_rows = expected_rows then 'pass' else 'fail' end, 'usage_batch_controls.csv', basis from m where source_file = 'usage_batch_controls.csv'
  -- B. Usage integrity
  union all select 'B1', 'B. Usage integrity', 'Duplicate source records removed', '1,924 unique (exact repeat of ur_7352010ec2e04c is not new activity)',
         (select count(*) from raw.product_usage) || ' rows, ' || ((select count(*) from raw.product_usage) - (select count(*) from stg.v_usage_clean)) || ' repeat; ' || (select count(*) from stg.v_usage_clean) || ' unique after dedupe',
         case when (select count(*) from stg.v_usage_clean) = 1924 and (select count(*) from raw.product_usage) - (select count(*) from stg.v_usage_clean) = 1
                   and not exists (select 1 from stg.v_usage_clean group by record_id having count(*) > 1) then 'pass' else 'fail' end, 'product_usage.csv, record_id', 'dedupe on record_id'
  union all select 'B2', 'B. Usage integrity', 'Daily active record count vs batch controls', '30 per day Sep 1-14, 32 per day Sep 15-Oct 31',
         (select count(*) filter (where record_diff = 0) from recon) || ' of ' || (select count(*) from recon) || ' dates match',
         case when (select count(*) from recon) = 61 and not exists (select 1 from recon where record_diff <> 0)
                   and (select count(*) from recon where (service_date < '2026-09-15' and control_records = 30) or (service_date >= '2026-09-15' and control_records = 32)) = 61 then 'pass' else 'fail' end,
         'usage_batch_controls.csv', 'compared after dedupe, before dropping unmatched accounts'
  union all select 'B3', 'B. Usage integrity', 'Daily active units vs batch controls', '61 dates match after dedupe',
         (select count(*) filter (where unit_diff = 0) from recon) || ' of ' || (select count(*) from recon) || ' dates match; ' || (select sum(clean_units) from recon) || ' runs = controls ' || (select sum(control_units) from recon),
         case when (select count(*) from recon) = 61 and not exists (select 1 from recon where unit_diff <> 0) then 'pass' else 'fail' end, 'usage_batch_controls.csv', 'compared after dedupe, before dropping unmatched accounts'
  union all select 'B4', 'B. Usage integrity', 'Usage mapped to a verified customer', 'All records',
         case when un.ws = 0 then 'all mapped' else un.ws || ' workspace unmapped (' || un.oct_records || ' October records, ' || un.oct_units || ' runs, no verified owner)' end,
         case when un.ws = 0 then 'pass' else 'pending' end, 'open item O-1', 'Pending Product Operations verification (MSG-2026-131). Not assigned by elimination; isolated from every customer total.' from un
  union all select 'B5', 'B. Usage integrity', 'Customers with two product accounts', 'Usage summed across verified accounts before the allowance',
         two_chk.customers || ' customers (' || coalesce(two_chk.names, '-') || '); aggregated ' || two_chk.ok || ' of ' || two_chk.customers,
         case when two_chk.customers = two_chk.ok then 'pass' else 'fail' end, 'product_account_mapping.csv', 'aggregate equals the sum of the accounts' from two_chk
  -- C. Accounting tie-outs
  union all select 'C1', 'C. Accounting tie-outs', 'Every GL journal balances', 'Debits = credits',
         (select count(*) from gl_j) || ' journals, ' || (select count(*) from gl_j where d <> c) || ' unbalanced',
         case when not exists (select 1 from gl_j where d <> c) then 'pass' else 'fail' end, 'netsuite_gl_detail.csv', 'per Internal ID'
  union all select 'C2', 'C. Accounting tie-outs', 'October recognized plan rows join to posted journals', 'All rows',
         (select count(*) filter (where gl_amount = recognized_amount) from plan_oct) || ' of ' || (select count(*) from plan_oct) || ' rows join a posting with equal amount',
         case when not exists (select 1 from plan_oct where gl_amount is distinct from recognized_amount) then 'pass' else 'fail' end, 'netsuite_revenue_plan_detail.csv', 'plan Journal Internal ID = GL Internal ID, 4000 credit = recognized amount'
  union all select 'C3', 'C. Accounting tie-outs', 'Opening balance + October activity = closing, accounts 1100, 1150, 1160, 2200', 'Per customer',
         (select count(*) filter (where tie_difference = 0) from calc.v_rollforward) || ' of ' || (select count(*) from calc.v_rollforward) || ' customer-account rows tie to the supporting sub-ledgers',
         case when (select count(*) from calc.v_rollforward) = 120 and not exists (select 1 from calc.v_rollforward where tie_difference <> 0) then 'pass' else 'fail' end,
         'netsuite_opening_balances.csv', 'closing vs Stripe invoices/credits, revenue plan, accrual journal, reclass policy'
  union all select 'C4', 'C. Accounting tie-outs', 'Each issued invoice has a matching GL posting', '124',
         (select count(*) filter (where created >= '2026-10-01' and gl_dr = total::numeric / 100 and gl_cr = total::numeric / 100) from inv) || ' of ' || (select count(*) filter (where created >= '2026-10-01') from inv)
           || ' in-period invoices matched (Dr 1100 = invoice total); ' || (select count(*) filter (where created < '2026-10-01') from inv) || ' September invoices precede the GL extract = '
           || (select count(*) from inv),
         case when not exists (select 1 from inv where created >= '2026-10-01' and (gl_dr is distinct from total::numeric / 100 or gl_cr is distinct from total::numeric / 100)) then 'pass' else 'fail' end,
         'stripe_invoices.csv, netsuite_gl_detail.csv', 'START_HERE p4: September journals are outside the GL extract (supported by opening balances)'
) c order by left(control_id, 1), substring(control_id from 2)::int;

revoke all on all tables in schema calc from anon, authenticated;
