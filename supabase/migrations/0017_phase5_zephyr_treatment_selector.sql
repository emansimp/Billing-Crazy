-- 0017: make the treatment selector usable for an approved concession that is ALREADY in the October accrual (Zephyr Grove).
-- Default = 'none' (posts nothing; the accrual is already net). Any other treatment is an override: reason required, and the line carries a
-- double-count warning because the accrual already equals the expected net.

alter table ref.treatment_account_pairs alter column debit_account drop not null, alter column credit_account drop not null;
alter table ref.treatment_account_pairs drop constraint treatment_account_pairs_treatment_check;
alter table ref.treatment_account_pairs add constraint treatment_account_pairs_treatment_check check (treatment in ('accrual','contra','writeoff','policy','none'));
insert into ref.treatment_account_pairs values
 ('concession_already_reflected', 'none',     null,   null,   true,  'Default: the approved concession is already in the October accrual (accrual = expected net). No October entry.'),
 ('concession_already_reflected', 'contra',   '4090', '1150', false, 'Override: contra revenue. WARNING: reduces October revenue a second time. 4090 is a PLACEHOLDER account.'),
 ('concession_already_reflected', 'accrual',  '4010', '1150', false, 'Override: reduce the usage accrual directly. WARNING: reduces October revenue a second time.'),
 ('concession_already_reflected', 'writeoff', '6900', '1150', false, 'Override: outside exercise policy; Controller approval required. WARNING: reduces October revenue a second time. 6900 is a PLACEHOLDER account.');

-- base candidates: add the already-reflected concession (reference amount = the approved concession; posts nothing by default)
create or replace view calc.v_adjustment_base as
with usage_adj as (
  select q.salesforce_account_id, q.account_name, q.netsuite_customer_internal_id, 'usage'::text as stream,
         case when q.accrual_adjustment_needed > 0 then 'usage_increase'
              when e.approved_concessions > 0 then 'concession_credit' else 'usage_reduce' end as adjustment_kind,
         abs(q.accrual_adjustment_needed) as amount,
         case when q.accrual_adjustment_needed > 0 then 'under' else 'over' end as direction,
         'usage_variance' as finding_check,
         'accrual ' || q.gl_accrued || ' posted vs ' || q.expected_net || ' expected (' || e.verified_units || ' runs, allowance ' || e.allowance_runs || ', rate ' || e.overage_rate_per_run || ')' as calc_basis
  from calc.usage_accrual_comparison q join calc.v_expected_usage e using (salesforce_account_id) where q.accrual_adjustment_needed <> 0
), plat_adj as (
  select r.salesforce_account_id, c.account_name, r.netsuite_customer_internal_id, 'platform', 'platform_increase', r.recognition_adjustment_needed, 'under', 'platform_variance',
         'October recognition ' || r.gl_recognized || ' posted vs ' || r.expected_total || ' expected (base ' || r.expected_base || ' + increment ' || r.expected_increment || ')'
  from calc.platform_recognition_oct r join stg.customers c using (salesforce_account_id) where r.recognition_adjustment_needed <> 0
), concession_reflected as (
  select q.salesforce_account_id, q.account_name, q.netsuite_customer_internal_id, 'usage', 'concession_already_reflected', e.approved_concessions, null::text, 'concession',
         'approved concession ' || e.approved_concessions || ' (MSG-2026-109) already in the October accrual: GL accrual ' || q.gl_accrued || ' = expected net ' || q.expected_net
  from calc.usage_accrual_comparison q join calc.v_expected_usage e using (salesforce_account_id)
  where e.approved_concessions > 0 and q.accrual_adjustment_needed = 0
)
select * from usage_adj union all select * from plat_adj union all select * from concession_reflected;

-- lines: new trailing columns posts_entry and double_count_warning (existing columns unchanged)
create or replace view calc.v_adjustment_lines as
with lines as (
  select 'ADJ:' || b.finding_check || ':' || b.salesforce_account_id as line_id, b.salesforce_account_id, b.account_name, b.netsuite_customer_internal_id,
         b.stream, b.adjustment_kind, b.amount, b.direction, b.finding_check, b.calc_basis, 1 as line_order
  from calc.v_adjustment_base b
  union all
  select 'ADJ:reclass:' || r.salesforce_account_id, r.salesforce_account_id, c.account_name, r.netsuite_customer_internal_id, 'platform', 'contract_asset_reclass',
         r.incremental_reclass, 'under', 'platform_variance',
         'required 1160 ' || round(r.required_1160, 2) || ' (net debit in 2200 after corrected recognition) minus existing 1160 ' || round(r.existing_1160, 2), 2
  from calc.v_reclass_incremental r join stg.customers c using (salesforce_account_id) where r.incremental_reclass <> 0
), numbered as (
  select l.*, dense_rank() over (order by l.account_name) as entry_no from lines l
)
select n.line_id, 'BR-OCT26-JE' || lpad(n.entry_no::text, 2, '0') as external_id, n.salesforce_account_id, n.account_name as customer, n.netsuite_customer_internal_id,
       n.stream, n.adjustment_kind, n.direction, round(n.amount, 2) as amount, n.line_order,
       (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default) as policy_default_treatment,
       coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) as selected_treatment,
       (o.treatment is not null and o.treatment <> (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) as treatment_overridden,
       o.reason as override_reason,
       (select array_agg(p.treatment order by p.treatment) from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind) as allowed_treatments,
       pr.debit_account, pr.credit_account,
       (pr.adjustment_kind is not null) as treatment_valid,
       exists (select 1 from ref.chart_of_accounts a where a.account_number in (pr.debit_account, pr.credit_account) and a.placeholder) as uses_placeholder_account,
       (select string_agg(a.account_number || ' ' || a.account_name || ' is a PLACEHOLDER account (not in the supplied chart of accounts): map it to a real NetSuite account before import', '; ')
          from ref.chart_of_accounts a where a.account_number in (pr.debit_account, pr.credit_account) and a.placeholder) as placeholder_warning,
       (select f.finding_id from calc.v_findings f where f.check_code = n.finding_check and f.salesforce_account_id = n.salesforce_account_id) as finding_id,
       n.finding_check, n.calc_basis, pr.note as treatment_note,
       (select journal_posting_period from ref.close_params) as posting_period, (select journal_date from ref.close_params) as entry_date,
       (coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) <> 'none') as posts_entry,
       case when n.adjustment_kind = 'concession_already_reflected'
                 and coalesce(o.treatment, 'none') <> 'none'
            then 'DOUBLE-COUNT WARNING: ' || n.calc_basis || '. Posting this entry reduces October revenue a second time.' end as double_count_warning
from numbered n
left join ref.adjustment_treatments o on o.line_id = n.line_id
left join ref.treatment_account_pairs pr on pr.adjustment_kind = n.adjustment_kind
     and pr.treatment = case n.adjustment_kind when 'contract_asset_reclass' then 'policy'
                             else coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) end;

-- journal lines: wording for the new kind (a 'none' line has no accounts, so the inner join to the chart already excludes it)
create or replace view calc.v_journal_lines as
select l.external_id, l.entry_date as date, l.posting_period, x.account_number,
       a.account_number || ' ' || a.account_name as account_label, a.placeholder as account_is_placeholder,
       x.debit, x.credit,
       replace(l.finding_check, '_', ' ') || ' - ' || l.customer || ': ' || case l.adjustment_kind
         when 'usage_reduce' then 'reduce October usage accrual' when 'usage_increase' then 'accrue missing October usage revenue'
         when 'platform_increase' then 'recognize October platform upgrade true-up' when 'contract_asset_reclass' then 'contract asset reclass for increment (incremental change only)'
         when 'concession_credit' then 'approved concession' when 'concession_already_reflected' then 'approved concession (OVERRIDE; already in the accrual: double-count warning)' end
         || ' [treatment: ' || l.selected_treatment || '] basis: ' || l.calc_basis as memo,
       l.netsuite_customer_internal_id as name, l.line_id, l.line_order, x.side_order
from calc.v_adjustment_lines l
cross join lateral (values (l.debit_account, l.amount, null::numeric, 1), (l.credit_account, null::numeric, l.amount, 2)) as x(account_number, debit, credit, side_order)
join ref.chart_of_accounts a on a.account_number = x.account_number
where l.treatment_valid and l.posts_entry;

-- billing-correction revenue effect counts only lines that actually post
create or replace view calc.v_billing_corrections as
select f.finding_id, f.salesforce_account_id, f.customer, f.stream, f.direction,
       case f.direction when 'under' then 'supplemental invoice' else 'linked credit note' end as document_type,
       f.amount,
       (select proposed_billing_issue_date from ref.close_params) as proposed_issue_date, 'Nov 2026'::text as posting_period,
       (select period_start from ref.close_params) as service_period_start, (select period_end_exclusive from ref.close_params) as service_period_end_exclusive,
       case f.direction when 'under' then f.amount else -f.amount end as ar_effect,
       case when f.stream = 'platform' then case f.direction when 'under' then 'Dr 1100 / Cr 2200' end
            else case f.direction when 'under' then 'Dr 1100 / Cr 1150' else 'Dr 1150 / Cr 1100' end end as november_posting_pair,
       coalesce((select sum(case when l.adjustment_kind in ('usage_increase', 'platform_increase') then l.amount else -l.amount end)
                 from calc.v_adjustment_lines l where l.salesforce_account_id = f.salesforce_account_id and l.stream = f.stream and l.adjustment_kind <> 'contract_asset_reclass' and l.posts_entry), 0) as october_revenue_effect,
       'Controller approval required; not created in any live system' as status
from calc.v_findings f where f.in_variance_total and f.class = 'error';

-- the "considered, no entry" list drops an item only when it actually posts an entry
create or replace view calc.v_adjustments_considered as
select f.finding_id, f.customer, f.check_code, f.class, f.amount,
       case
         when f.check_code = 'concession' and f.class = 'valid_explanation' then
           'No October entry: the approved concession is already in the October accrual (' || f.detail || '). A contra-revenue entry would reduce revenue twice. The November credit note reduces AR and releases unbilled usage only. (Selector available: calc.v_treatment_options.)'
         when f.check_code = 'concession' and f.class = 'needs_info' then 'No entry: request is not approved by the Controller; it authorizes no credit and no revenue reduction.'
         when f.check_code = 'usage_variance' then 'No October entry: the October accrual already equals the contract-supported amount, so only the November billing correction applies.'
         when f.check_code = 'void_credit_note' then 'No entry: void credit note has no current effect and nothing was posted.'
         when f.check_code = 'unassigned_usage' then 'No entry: unverified usage is not accrued or assigned until Product Operations verifies ownership.'
         when f.check_code = 'missing_usage_invoice' then 'No separate entry: covered by the usage accrual line / not billable (see finding).'
         else 'No entry: diagnosis or timing item only (see finding).' end as reason
from calc.v_findings f
where not exists (select 1 from calc.v_adjustment_lines l where l.salesforce_account_id = f.salesforce_account_id and l.finding_check = f.check_code and l.posts_entry)
  and (f.salesforce_account_id is null or f.check_code in ('concession','usage_variance','void_credit_note','missing_usage_invoice','unassigned_usage'));

-- selector options for every adjustment line (what the mockup's treatment dropdown shows)
create view calc.v_treatment_options as
select l.line_id, l.external_id, l.customer, l.adjustment_kind, l.amount as line_amount, p.treatment as option_treatment,
       p.debit_account, p.credit_account, (p.treatment = l.policy_default_treatment) as is_policy_default, (p.treatment = l.selected_treatment) as is_selected,
       (p.treatment <> l.policy_default_treatment) as requires_reason,
       exists (select 1 from ref.chart_of_accounts a where a.account_number in (p.debit_account, p.credit_account) and a.placeholder) as uses_placeholder_account,
       case when l.adjustment_kind = 'concession_already_reflected' and p.treatment <> 'none' then 'DOUBLE-COUNT WARNING: accrual already net; this reduces October revenue a second time' end as warning,
       p.note
from calc.v_adjustment_lines l join ref.treatment_account_pairs p on p.adjustment_kind = l.adjustment_kind and p.treatment <> 'policy';

create function calc.clear_treatment(p_line_id text) returns void language sql as 'delete from ref.adjustment_treatments where line_id = p_line_id';

-- export checks: add a visible warning when an override double-counts an already-reflected concession
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
union all select 'No double-counted concession',
       case when exists (select 1 from al where double_count_warning is not null) then 'warning' else 'pass' end,
       coalesce((select string_agg(customer || ': ' || double_count_warning, '; ') from al where double_count_warning is not null), 'none')
union all select 'Controller approval',
       case when (select count(distinct external_id) from jl) > 0 and (select n from ap) = (select count(distinct external_id) from jl) then 'pass' else 'pending' end,
       (select n from ap) || ' of ' || (select count(distinct external_id) from jl) || ' entries approved'
union all select 'No write-off treatments selected',
       case when exists (select 1 from al where selected_treatment = 'writeoff') then 'fail' else 'pass' end,
       'write-off is outside exercise policy and blocks export without explicit approval'
union all select 'Every override has a reason and an allowed treatment',
       case when exists (select 1 from al where not treatment_valid or (treatment_overridden and coalesce(btrim(override_reason), '') = '')) then 'fail' else 'pass' end,
       (select count(*) from al where treatment_overridden) || ' overrides';

revoke all on all tables in schema calc from anon, authenticated;
revoke all on all tables in schema ref from anon, authenticated;
