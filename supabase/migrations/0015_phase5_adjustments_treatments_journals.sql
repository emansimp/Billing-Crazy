-- 0015 (Phase 5, part 2): proposed adjusting entries, accounting treatments, billing corrections, journal lines.
-- Proposals only: nothing is posted. October-service accounting adjustments keep the October posting period;
-- billing documents (supplemental invoices / credit notes) are separate objects dated in November.
-- A billing correction is not an automatic revenue adjustment: a line exists only where the October accrual / recognition itself differs from policy.

-- Treatment -> account pairs. Missed revenue can only be accrued; contra applies to credited or waived amounts; write-off is outside policy.
create table ref.treatment_account_pairs (
  adjustment_kind text not null, treatment text not null check (treatment in ('accrual','contra','writeoff','policy')),
  debit_account text not null, credit_account text not null, is_policy_default boolean not null, note text not null,
  primary key (adjustment_kind, treatment)
);
insert into ref.treatment_account_pairs values
 ('usage_reduce',     'accrual',  '4010', '1150', true,  'Corrects the overstated usage accrual directly in usage revenue.'),
 ('usage_reduce',     'contra',   '4090', '1150', false, 'Shows a credited or waived amount as contra revenue (4090 is a PLACEHOLDER account).'),
 ('usage_reduce',     'writeoff', '6900', '1150', false, 'Outside exercise policy: requires explicit Controller approval (6900 is a PLACEHOLDER account).'),
 ('usage_increase',   'accrual',  '1150', '4010', true,  'Accrues usage revenue earned but missing from the October accrual. Missed revenue can only be accrued.'),
 ('platform_increase','accrual',  '2200', '4000', true,  'Recognizes the October platform true-up (days / 365). Missed revenue can only be accrued.'),
 ('concession_credit','contra',   '4090', '1150', true,  'Approved concession not yet in the accrual: contra revenue (4090 is a PLACEHOLDER account).'),
 ('concession_credit','accrual',  '4010', '1150', false, 'Reduces the usage accrual directly in usage revenue.'),
 ('concession_credit','writeoff', '6900', '1150', false, 'Outside exercise policy: requires explicit Controller approval (6900 is a PLACEHOLDER account).'),
 ('contract_asset_reclass','policy','1160','2200', true,  'Fixed by policy: a customer platform net debit in 2200 moves to 1160. Incremental change only.');
alter table ref.treatment_account_pairs enable row level security;

-- Overrides of the policy-default treatment. A reason is mandatory (non-blank); there is no way to override without one.
create table ref.adjustment_treatments (
  line_id text primary key, treatment text not null check (treatment in ('accrual','contra','writeoff')),
  reason text not null check (length(btrim(reason)) > 0), set_by text not null, set_at timestamptz not null default now()
);
alter table ref.adjustment_treatments enable row level security;
create table ref.journal_approvals (
  external_id text primary key, approved_by text not null, approved_at timestamptz not null default now(), note text
);
alter table ref.journal_approvals enable row level security;

create function calc.set_treatment(p_line_id text, p_treatment text, p_reason text, p_by text) returns void language plpgsql as $$
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'override requires a reason'; end if;
  if not exists (select 1 from calc.v_adjustment_lines l join ref.treatment_account_pairs p on p.adjustment_kind = l.adjustment_kind and p.treatment = p_treatment
                 where l.line_id = p_line_id and p_treatment <> 'policy') then
    raise exception 'treatment % is not allowed for line %', p_treatment, p_line_id;
  end if;
  insert into ref.adjustment_treatments (line_id, treatment, reason, set_by) values (p_line_id, p_treatment, p_reason, p_by)
  on conflict (line_id) do update set treatment = excluded.treatment, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
end $$;

-- Base adjustment candidates (before treatment). One per customer per kind, tied to a Phase 4 finding.
create view calc.v_adjustment_base as
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
)
select * from usage_adj union all select * from plat_adj;

-- Incremental contract-asset reclass after corrected recognition (START_HERE: reverse prior reclass, recalculate, propose only the increment).
create view calc.v_reclass_incremental as
with adj as (select salesforce_account_id, sum(amount) as plat_adj from calc.v_adjustment_base where adjustment_kind = 'platform_increase' group by 1),
rf as (
  select s.salesforce_account_id, s.netsuite_customer_internal_id,
         max(case when r.account_number = '2200' then r.opening end) as open_2200,
         max(case when r.account_number = '1160' then r.opening end) as open_1160
  from calc.v_rollforward r join stg.customers s on s.netsuite_customer_internal_id = r.netsuite_customer_internal_id group by 1, 2),
g as (
  select customer_internal_id cust,
         sum(debit - credit) filter (where account_number = '2200' and memo not ilike '%contract asset%') as net_2200_ex_reclass,
         sum(debit - credit) filter (where account_number = '1160') as net_1160
  from raw.netsuite_gl_detail where posting_period = 'Oct 2026' group by 1)
select rf.salesforce_account_id, rf.netsuite_customer_internal_id,
       rf.open_2200 + coalesce(g.net_2200_ex_reclass, 0) + coalesce(adj.plat_adj, 0) as net_2200_before_reclass_after_adjustment,
       greatest(0, rf.open_2200 + coalesce(g.net_2200_ex_reclass, 0) + coalesce(adj.plat_adj, 0)) as required_1160,
       rf.open_1160 + coalesce(g.net_1160, 0) as existing_1160,
       greatest(0, rf.open_2200 + coalesce(g.net_2200_ex_reclass, 0) + coalesce(adj.plat_adj, 0)) - (rf.open_1160 + coalesce(g.net_1160, 0)) as incremental_reclass
from rf left join g on g.cust = rf.netsuite_customer_internal_id left join adj using (salesforce_account_id);

-- Adjustment lines with the selected treatment (policy default unless a reasoned override exists), accounts and placeholder flags.
create view calc.v_adjustment_lines as
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
       (select journal_posting_period from ref.close_params) as posting_period, (select journal_date from ref.close_params) as entry_date
from numbered n
left join ref.adjustment_treatments o on o.line_id = n.line_id
left join ref.treatment_account_pairs pr on pr.adjustment_kind = n.adjustment_kind
     and pr.treatment = case n.adjustment_kind when 'contract_asset_reclass' then 'policy'
                             else coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) end;

-- NetSuite journal lines: one debit row and one credit row per adjustment line; External ID repeated on every row; no total row.
create view calc.v_journal_lines as
select l.external_id, l.entry_date as date, l.posting_period, x.account_number,
       a.account_number || ' ' || a.account_name as account_label, a.placeholder as account_is_placeholder,
       x.debit, x.credit,
       replace(l.finding_check, '_', ' ') || ' ' || l.customer || ': ' || case l.adjustment_kind
         when 'usage_reduce' then 'reduce October usage accrual' when 'usage_increase' then 'accrue missing October usage revenue'
         when 'platform_increase' then 'recognize October platform upgrade true-up' when 'contract_asset_reclass' then 'contract asset reclass for increment (incremental change only)'
         when 'concession_credit' then 'approved concession' end
         || ' [' || l.selected_treatment || '] ' || l.calc_basis as memo,
       l.netsuite_customer_internal_id as name, l.line_id, l.line_order, x.side_order
from calc.v_adjustment_lines l
cross join lateral (values (l.debit_account, l.amount, null::numeric, 1), (l.credit_account, null::numeric, l.amount, 2)) as x(account_number, debit, credit, side_order)
join ref.chart_of_accounts a on a.account_number = x.account_number
where l.treatment_valid;

-- Billing corrections: separate objects dated in November, no revenue effect by themselves (revenue effect only via the October entry, if any).
create view calc.v_billing_corrections as
select f.finding_id, f.salesforce_account_id, f.customer, f.stream, f.direction,
       case f.direction when 'under' then 'supplemental invoice' else 'linked credit note' end as document_type,
       f.amount,
       (select proposed_billing_issue_date from ref.close_params) as proposed_issue_date, 'Nov 2026'::text as posting_period,
       (select period_start from ref.close_params) as service_period_start, (select period_end_exclusive from ref.close_params) as service_period_end_exclusive,
       case f.direction when 'under' then f.amount else -f.amount end as ar_effect,
       case when f.stream = 'platform' then case f.direction when 'under' then 'Dr 1100 / Cr 2200' end
            else case f.direction when 'under' then 'Dr 1100 / Cr 1150' else 'Dr 1150 / Cr 1100' end end as november_posting_pair,
       coalesce((select sum(case when l.adjustment_kind in ('usage_increase', 'platform_increase') then l.amount else -l.amount end)
                 from calc.v_adjustment_lines l where l.salesforce_account_id = f.salesforce_account_id and l.stream = f.stream and l.adjustment_kind <> 'contract_asset_reclass'), 0) as october_revenue_effect,
       'Controller approval required; not created in any live system' as status
from calc.v_findings f where f.in_variance_total and f.class = 'error';

-- Items reviewed that need NO October entry, with the reason (the data decides, not the mockup default).
create view calc.v_adjustments_considered as
select f.finding_id, f.customer, f.check_code, f.class, f.amount,
       case
         when f.check_code = 'concession' and f.class = 'valid_explanation' then
           'No October entry: the approved concession is already in the October accrual (' || f.detail || '). A contra-revenue entry would reduce revenue twice. The November credit note reduces AR and releases unbilled usage only.'
         when f.check_code = 'concession' and f.class = 'needs_info' then 'No entry: request is not approved by the Controller; it authorizes no credit and no revenue reduction.'
         when f.check_code = 'usage_variance' then 'No October entry: the October accrual already equals the contract-supported amount, so only the November billing correction applies.'
         when f.check_code = 'void_credit_note' then 'No entry: void credit note has no current effect and nothing was posted.'
         when f.check_code = 'unassigned_usage' then 'No entry: unverified usage is not accrued or assigned until Product Operations verifies ownership.'
         when f.check_code = 'missing_usage_invoice' then 'No separate entry: covered by the usage accrual line / not billable (see finding).'
         else 'No entry: diagnosis or timing item only (see finding).' end as reason
from calc.v_findings f
where not exists (select 1 from calc.v_adjustment_lines l where l.salesforce_account_id = f.salesforce_account_id and l.finding_check = f.check_code)
  and (f.salesforce_account_id is null or f.check_code in ('concession','usage_variance','void_credit_note','missing_usage_invoice','unassigned_usage'));

-- Net effect on October revenue (and on contra / expense, separately), by account.
create view calc.v_revenue_effect as
select a.account_number, a.account_name, a.placeholder as placeholder_account,
       coalesce(sum(j.credit) filter (where j.account_number = a.account_number), 0) - coalesce(sum(j.debit) filter (where j.account_number = a.account_number), 0) as credit_minus_debit
from ref.chart_of_accounts a left join calc.v_journal_lines j on j.account_number = a.account_number
where a.account_type in ('revenue', 'contra_revenue', 'expense') group by 1, 2, 3;

-- Rollforward including the proposed entries.
create view calc.v_rollforward_after_proposed as
select r.netsuite_customer_internal_id, r.salesforce_account_id, r.account_name, r.account_number, r.opening, r.oct_debits, r.oct_credits, r.closing_gl,
       coalesce(p.net, 0) as proposed_adjustment, r.closing_gl + coalesce(p.net, 0) as closing_after_proposed
from calc.v_rollforward r
left join (select name, account_number, sum(coalesce(debit, 0) - coalesce(credit, 0)) as net from calc.v_journal_lines group by 1, 2) p
  on p.name = r.netsuite_customer_internal_id and p.account_number = r.account_number;

-- Pre-export checks (pass / warning / pending / fail).
create view calc.v_journal_export_checks as
select 'Each journal balances' as check_name,
       case when (select count(*) from (select external_id from calc.v_journal_lines group by 1 having sum(coalesce(debit, 0)) <> sum(coalesce(credit, 0))) x) = 0 then 'pass' else 'fail' end as status,
       (select count(distinct external_id) || ' entries, ' || count(*) || ' lines, debits ' || sum(coalesce(debit, 0)) || ' = credits ' || sum(coalesce(credit, 0)) from calc.v_journal_lines) as detail
union all select 'Posting period is open',
       case when exists (select 1 from calc.v_journal_lines j join ref.accounting_periods p on p.period = j.posting_period where p.status = 'closed') then 'fail'
            when exists (select 1 from calc.v_journal_lines j left join ref.accounting_periods p on p.period = j.posting_period where p.period is null) then 'warning' else 'pass' end,
       (select string_agg(distinct j.posting_period || ' is ' || p.status || ' (' || p.source || ')', '; ') from calc.v_journal_lines j join ref.accounting_periods p on p.period = j.posting_period)
union all select 'Placeholder accounts used',
       case when exists (select 1 from calc.v_journal_lines where account_is_placeholder) then 'warning' else 'pass' end,
       coalesce((select string_agg(distinct account_label || ' (PLACEHOLDER)', '; ') from calc.v_journal_lines where account_is_placeholder), 'none (default treatments use only supplied accounts)')
union all select 'Controller approval',
       case when (select count(distinct external_id) from calc.v_journal_lines) > 0 and not exists (select 1 from calc.v_journal_lines j left join ref.journal_approvals a using (external_id) where a.external_id is null) then 'pass' else 'pending' end,
       (select count(*) from ref.journal_approvals) || ' of ' || (select count(distinct external_id) from calc.v_journal_lines) || ' entries approved'
union all select 'No write-off treatments selected',
       case when exists (select 1 from calc.v_adjustment_lines where selected_treatment = 'writeoff') then 'fail' else 'pass' end,
       'write-off is outside exercise policy and blocks export without explicit approval'
union all select 'Every override has a reason and an allowed treatment',
       case when exists (select 1 from calc.v_adjustment_lines where treatment_overridden and (coalesce(btrim(override_reason), '') = '' or not treatment_valid))
             or exists (select 1 from calc.v_adjustment_lines where not treatment_valid) then 'fail' else 'pass' end,
       (select count(*) from calc.v_adjustment_lines where treatment_overridden) || ' overrides';

revoke all on all tables in schema calc from anon, authenticated;
revoke all on all tables in schema ref from anon, authenticated;
