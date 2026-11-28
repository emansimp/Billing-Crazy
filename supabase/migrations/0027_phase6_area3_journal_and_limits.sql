-- 0027 (Phase 6, Area 3 + decision limits): journal entry views (live, because treatment selection changes them immediately), server-only write RPCs,
-- decision history, live corrections status, run history.

select setval(pg_get_serial_sequence('ops.runs', 'run_id'), (select coalesce(max(run_id), 1) from ops.runs));

-- ---------- decision history (limit 3) and reset-to-draft (limit 1) ----------
create table ops.finding_decision_log (
  id serial primary key, finding_id text not null, decision text not null, decided_by text not null, decided_at timestamptz not null default now()
);
alter table ops.finding_decision_log enable row level security; revoke all on ops.finding_decision_log from anon, authenticated;
insert into ops.finding_decision_log (finding_id, decision, decided_by, decided_at) select finding_id, decision, decided_by, decided_at from ops.finding_decisions;

drop function if exists public.ui_record_finding_decision(text, text);
create function public.ui_record_finding_decision(p_display_id text, p_decision text, p_by text default null) returns void
language plpgsql security definer set search_path = ops, public, calc, ref as $$
declare fid text; who text := coalesce(nullif(btrim(p_by), ''), 'Controller (demo, no sign-in)');
begin
  select finding_id into fid from public.ui_findings_list where display_id = p_display_id;
  if fid is null then raise exception 'unknown finding %', p_display_id; end if;
  insert into ops.finding_decisions (finding_id, decision, decided_by) values (fid, p_decision, who)
  on conflict (finding_id) do update set decision = excluded.decision, decided_by = excluded.decided_by, decided_at = now();
  insert into ops.finding_decision_log (finding_id, decision, decided_by) values (fid, p_decision, who);
end $$;
revoke all on function public.ui_record_finding_decision(text, text, text) from public, anon, authenticated;
grant execute on function public.ui_record_finding_decision(text, text, text) to service_role;

create view public.ui_finding_decision_log as select finding_id, decision, decided_by, decided_at from ops.finding_decision_log;
grant select on public.ui_finding_decision_log to anon, authenticated;

-- live corrections status (limit 2): the snapshot now carries finding_id so the app can overlay the live decision
create or replace view public.ui_billing_corrections_live as
with bc as (
  select b.finding_id, b.customer, case b.document_type when 'linked credit note' then 'Credit note' else 'Supplemental invoice' end as document,
         case when b.stream = 'platform' then coalesce((select r.document_id from raw.contract_register r where r.salesforce_account_id = b.salesforce_account_id and r.document_type = 'amendment' limit 1) || ' catch-up', 'platform invoice')
              else coalesce((select ub.invoice_numbers[1] from calc.v_billed_usage ub where ub.salesforce_account_id = b.salesforce_account_id), 'No October usage invoice') end as linked_to,
         b.amount, b.proposed_issue_date, b.stream, 'Awaiting approval' as base_status
  from calc.v_billing_corrections b
  union all
  select null, c.account_name, 'No new document', (select cc.number from calc.actual_issued_credits cc where cc.salesforce_account_id = c.salesforce_account_id limit 1), c.credits_issued, null, 'usage', 'Already issued'
  from calc.v_billed_usage c where c.credits_issued > 0
), lab as (
  select bc.*, coalesce((select l.sort_no from ref.finding_labels l where l.finding_id = bc.finding_id),
                        (select l.sort_no from ref.finding_labels l join calc.v_findings f using (finding_id) where f.check_code = 'concession' and f.customer = bc.customer limit 1), 99) as sort_no from bc)
select 'CORR-' || lpad(row_number() over (order by sort_no, customer)::text, 2, '0') as ref, split_part(customer, ',', 1) as customer, document, linked_to, amount, proposed_issue_date,
       base_status as status, finding_id
from lab;
drop materialized view public.ui_billing_corrections;
create materialized view public.ui_billing_corrections as select * from public.ui_billing_corrections_live;
grant select on public.ui_billing_corrections to anon, authenticated;

-- ---------- journal views (live) ----------
create view public.ui_je_lines as
select l.line_id, l.external_id, l.customer, f.display_id, l.adjustment_kind,
       case l.adjustment_kind when 'usage_reduce' then 'Reduce October usage accrual' when 'usage_increase' then 'Accrue missing October usage revenue'
            when 'platform_increase' then 'Platform recognition true-up' when 'contract_asset_reclass' then 'Contract asset reclass'
            when 'concession_credit' then 'Net October usage accrual of approved credit' when 'concession_already_reflected' then 'Approved concession (already in the accrual)' end as adjustment_label,
       l.calc_basis, l.amount, l.direction, l.selected_treatment, l.policy_default_treatment, l.treatment_overridden, l.override_reason, l.posts_entry,
       (l.adjustment_kind = 'contract_asset_reclass') as fixed_by_policy, l.debit_account, l.credit_account,
       da.account_number || ' ' || da.account_name as debit_label, ca.account_number || ' ' || ca.account_name as credit_label,
       l.uses_placeholder_account, l.placeholder_warning, l.double_count_warning, l.line_order
from calc.v_adjustment_lines l
left join public.ui_findings_list f on f.finding_id = l.finding_id
left join ref.chart_of_accounts da on da.account_number = l.debit_account left join ref.chart_of_accounts ca on ca.account_number = l.credit_account;

create view public.ui_je_options as
select o.line_id, o.option_treatment, o.is_policy_default, o.is_selected, o.requires_reason, o.uses_placeholder_account, o.warning, o.note,
       da.account_number || ' ' || da.account_name as debit_label, ca.account_number || ' ' || ca.account_name as credit_label
from calc.v_treatment_options o
left join ref.chart_of_accounts da on da.account_number = o.debit_account left join ref.chart_of_accounts ca on ca.account_number = o.credit_account;

create view public.ui_je_entries as
select l.external_id, min(l.customer) as customer, min(l.display_id) as display_id, min(l.line_order) as ord,
       (array_agg(l.adjustment_kind order by l.line_order))[1] as primary_kind,
       case (array_agg(l.adjustment_kind order by l.line_order))[1]
         when 'usage_reduce' then 'Reduce October usage accrual to the contract-supported amount' when 'usage_increase' then 'Accrue missing October usage revenue'
         when 'platform_increase' then 'Recognize the platform upgrade increment for October' when 'concession_credit' then 'Approved concession on October usage'
         when 'concession_already_reflected' then 'Approved concession on October usage (already in the accrual)' end as title,
       (select journal_posting_period from ref.close_params) as posting_period,
       case when exists (select 1 from ref.journal_approvals a where a.external_id = l.external_id) then 'Approved' else 'Draft' end as status,
       bool_or(l.posts_entry) as posts_entry
from public.ui_je_lines l group by l.external_id;

create view public.ui_je_summary as
select coalesce(sum(debit), 0) as debits, coalesce(sum(credit), 0) as credits, (coalesce(sum(debit), 0) = coalesce(sum(credit), 0)) as balanced,
       (select count(distinct external_id) from calc.v_journal_lines) as entries, count(*) as lines,
       (select coalesce(sum(credit_minus_debit), 0) from calc.v_revenue_effect where account_number in ('4000', '4010')) as net_revenue_effect,
       (select coalesce(sum(credit_minus_debit), 0) from calc.v_revenue_effect where account_number = '4010') as usage_effect,
       (select coalesce(sum(credit_minus_debit), 0) from calc.v_revenue_effect where account_number = '4000') as platform_effect,
       (select coalesce(sum(credit_minus_debit), 0) from calc.v_revenue_effect where account_number = '4090') as contra_effect,
       (select coalesce(sum(credit_minus_debit), 0) from calc.v_revenue_effect where account_number = '6900') as writeoff_effect,
       (select count(*) from ref.journal_approvals a where a.external_id in (select external_id from calc.v_journal_lines)) as approved_entries,
       (select count(*) from calc.v_adjustment_lines where selected_treatment = 'writeoff') as writeoff_lines,
       (select count(*) from calc.v_adjustment_lines where treatment_overridden) as overrides,
       (select count(*) from calc.v_adjustment_lines where double_count_warning is not null) as double_count_lines,
       (select count(*) from calc.v_adjustment_lines where uses_placeholder_account and posts_entry) as placeholder_lines
from calc.v_journal_lines;

create view public.ui_export_checks as select check_name, status, detail from calc.v_journal_export_checks;
create view public.ui_export_lines as select external_id, date, posting_period, account_label, account_is_placeholder, debit, credit, memo, name, line_order, side_order from calc.v_journal_lines;
create view public.ui_coa as
select a.account_number, a.account_name, a.account_type, a.placeholder, case when a.placeholder then 'Placeholder' else 'Supplied' end as status, a.coa_version,
       exists (select 1 from calc.v_journal_lines j where j.account_number = a.account_number) as used_in_export
from ref.chart_of_accounts a;
create view public.ui_run_history as
select r.run_id, r.period, r.started_at, r.finished_at, r.git_commit, r.input_counts, r.output_totals,
       case when r.run_id = (select max(run_id) from ops.runs) then 'Complete' else 'Superseded' end as result
from ops.runs r;
grant select on public.ui_je_lines, public.ui_je_options, public.ui_je_entries, public.ui_je_summary, public.ui_export_checks, public.ui_export_lines, public.ui_coa, public.ui_run_history to anon, authenticated;

-- ---------- server-only write RPCs ----------
create function public.ui_set_treatment(p_line_id text, p_treatment text, p_reason text, p_by text default null) returns void
language plpgsql security definer set search_path = ops, public, calc, ref as $$
declare eid text;
begin
  select external_id into eid from calc.v_adjustment_lines where line_id = p_line_id;
  perform calc.set_treatment(p_line_id, p_treatment, p_reason, coalesce(nullif(btrim(p_by), ''), 'Controller (demo, no sign-in)'));
  delete from ref.journal_approvals where external_id = eid;   -- changing a treatment changes the entry: its approval no longer applies
end $$;
create function public.ui_clear_treatment(p_line_id text) returns void
language plpgsql security definer set search_path = ops, public, calc, ref as $$
declare eid text;
begin
  select external_id into eid from calc.v_adjustment_lines where line_id = p_line_id;
  perform calc.clear_treatment(p_line_id);
  delete from ref.journal_approvals where external_id = eid;
end $$;
create function public.ui_approve_entries(p_by text default null) returns int
language plpgsql security definer set search_path = ops, public, calc, ref as $$
declare n int;
begin
  insert into ref.journal_approvals (external_id, approved_by, note)
  select distinct external_id, coalesce(nullif(btrim(p_by), ''), 'Controller (demo, no sign-in)'), 'approved in app' from calc.v_journal_lines on conflict (external_id) do nothing;
  get diagnostics n = row_count; return n;
end $$;
create function public.ui_revoke_approvals() returns void language sql security definer set search_path = ops, public, calc, ref as 'delete from ref.journal_approvals';
create function public.ui_record_run(p_commit text) returns int language sql security definer set search_path = ops, public, calc, ref as 'select ops.record_run(p_commit, ''Oct 2026'')';
create function public.ui_refresh_snapshots(p_scope text default 'all') returns void language sql security definer set search_path = ops, public, calc, ref as 'select ops.refresh_ui(p_scope)';
create function public.ui_reset_demo() returns void language plpgsql security definer set search_path = ops, public, calc, ref as $$
begin
  delete from ops.finding_decisions; delete from ops.finding_decision_log; delete from ref.adjustment_treatments; delete from ref.journal_approvals;
end $$;
do $$ declare f text; begin
  foreach f in array array['ui_set_treatment(text,text,text,text)', 'ui_clear_treatment(text)', 'ui_approve_entries(text)', 'ui_revoke_approvals()', 'ui_record_run(text)', 'ui_refresh_snapshots(text)', 'ui_reset_demo()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;

-- performance: evaluate each calc view once (the first version re-evaluated them per column and timed out)
create or replace view public.ui_je_summary as
with jl as materialized (select * from calc.v_journal_lines),
     al as materialized (select * from calc.v_adjustment_lines),
     re as materialized (select * from calc.v_revenue_effect),
     ap as materialized (select external_id from ref.journal_approvals)
select (select coalesce(sum(debit), 0) from jl) as debits, (select coalesce(sum(credit), 0) from jl) as credits,
       ((select coalesce(sum(debit), 0) from jl) = (select coalesce(sum(credit), 0) from jl)) as balanced,
       (select count(distinct external_id) from jl) as entries, (select count(*) from jl) as lines,
       (select coalesce(sum(credit_minus_debit), 0) from re where account_number in ('4000', '4010')) as net_revenue_effect,
       (select coalesce(sum(credit_minus_debit), 0) from re where account_number = '4010') as usage_effect,
       (select coalesce(sum(credit_minus_debit), 0) from re where account_number = '4000') as platform_effect,
       (select coalesce(sum(credit_minus_debit), 0) from re where account_number = '4090') as contra_effect,
       (select coalesce(sum(credit_minus_debit), 0) from re where account_number = '6900') as writeoff_effect,
       (select count(*) from ap where external_id in (select external_id from jl)) as approved_entries,
       (select count(*) from al where selected_treatment = 'writeoff') as writeoff_lines,
       (select count(*) from al where treatment_overridden) as overrides,
       (select count(*) from al where double_count_warning is not null) as double_count_lines,
       (select count(*) from al where uses_placeholder_account and posts_entry) as placeholder_lines;
