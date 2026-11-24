-- 0019 (Phase 6, Area 1 part 2): read-only UI views for the Close overview. Granted to the browser role; everything is computed in SQL.

create view public.ui_footer as
select r.run_id, r.finished_at as last_run_at, r.git_commit as run_commit, r.period from ops.runs r order by r.run_id desc limit 1;

create view public.ui_close_header as
select (select count(*) from stg.customers) as customers, p.cutoff, p.period_start, p.period_end_exclusive,
       case when (select count(distinct external_id) from calc.v_journal_lines) > 0
                 and (select count(*) from ref.journal_approvals) >= (select count(distinct external_id) from calc.v_journal_lines) then 'Approved by Controller'
            else 'Awaiting Controller review' end as status_label
from ref.close_params p;

-- Question 1: expected vs billed. Platform uses the day-based allocation to October (invoices allocated by service days); usage is net of approved credits.
-- Under- and over-billing are computed per customer and summed separately; they are never netted.
create view public.ui_overview_q1 as
with plat as (
  select sum(e.expected_invoices_allocated_to_period) as expected, sum(b.billed_allocated_to_period) as billed,
         sum(greatest(e.expected_invoices_allocated_to_period - b.billed_allocated_to_period, 0)) as under_billed,
         sum(greatest(b.billed_allocated_to_period - e.expected_invoices_allocated_to_period, 0)) as over_billed
  from calc.v_expected_platform e join calc.v_billed_platform b using (salesforce_account_id)),
use as (
  select sum(usage_expected_net) as expected, sum(usage_billed_net) as billed, sum(usage_under_billed) as under_billed, sum(usage_over_billed) as over_billed from calc.v_expected_vs_billed)
select 1 as sort_no, 'Platform subscription' as stream, expected, billed, under_billed, over_billed from plat
union all select 2, 'Workflow-run usage', expected, billed, under_billed, over_billed from use
union all select 3, 'Total', plat.expected + use.expected, plat.billed + use.billed, plat.under_billed + use.under_billed, plat.over_billed + use.over_billed from plat, use;

-- primary findings (diagnosis rows are shown inside the finding they explain, not as separate list rows)
create view public.ui_findings_list as
with f as (
  select f.*, l.sort_no as label_no from calc.v_findings f left join ref.finding_labels l using (finding_id)
  where not (f.check_code = 'amendment_not_loaded' or (f.check_code = 'missing_usage_invoice' and f.class = 'error'))
), n as (
  select f.*, coalesce(f.label_no, (select coalesce(max(sort_no), 0) from ref.finding_labels)
           + row_number() over (partition by (f.label_no is null) order by case f.class when 'error' then 1 when 'needs_info' then 2 else 3 end, f.check_code, f.customer)) as sort_no
  from f)
select 'F-' || lpad(n.sort_no::text, 2, '0') as display_id, n.sort_no, n.finding_id, n.check_code, n.salesforce_account_id,
       split_part(n.customer, ',', 1) as customer, n.stream, n.class,
       case n.class when 'error' then 'Error' when 'valid_explanation' then 'Valid explanation' else 'Needs info' end as class_label,
       case n.direction when 'over' then 'Over-billed' when 'under' then 'Under-billed' end as direction_label,
       case when n.check_code = 'platform_variance' then 'Oct ' || (select extract(day from effective_from)::int from ref.contract_term_versions v where v.salesforce_account_id = n.salesforce_account_id and v.version_no = 2) || '–31'
            when n.check_code = 'later_service_platform' then 'Nov 1–30' else 'Oct 1–31' end as period_label,
       case n.check_code
         when 'usage_variance' then (select case uf.diagnosis
              when 'amended_allowance_not_applied' then 'Allowance amendment effective ' || to_char((select v.effective_from from ref.contract_term_versions v where v.salesforce_account_id = n.salesforce_account_id and v.version_no = 2), 'Mon FMDD') || ' not loaded to billing, usage over-billed'
              when 'billed_rate_differs_from_contract' then 'Usage billed at $' || to_char(uf.billed_rate_cents / 100, 'FM0.00') || ' per run, contract rate is $' || to_char(uf.contract_rate_cents / 100, 'FM0.00') || '; usage under-billed'
              when 'no_usage_invoice_issued' then 'No October usage invoice issued although verified usage exceeds the allowance; usage under-billed'
              when 'billed_quantity_differs_from_metered_overage' then 'Invoice bills ' || to_char(uf.billed_units, 'FM999,999') || ' overage runs, metering supports ' || to_char(uf.expected_overage_units, 'FM999,999') || '; usage under-billed'
              else n.detail end from calc.usage_findings uf where uf.salesforce_account_id = n.salesforce_account_id)
         when 'platform_variance' then 'Platform upgrade to $' || to_char((select v.platform_fee_annual from ref.contract_term_versions v where v.salesforce_account_id = n.salesforce_account_id and v.version_no = 2), 'FM999,999') || ' per year, effective ' || to_char((select v.effective_from from ref.contract_term_versions v where v.salesforce_account_id = n.salesforce_account_id and v.version_no = 2), 'Mon FMDD') || ', not reflected in billing'
         when 'concession' then case n.class when 'valid_explanation' then 'Controller-approved $' || to_char(n.amount, 'FM999,990.00') || ' concession, credit note ' || (select c.number from calc.actual_issued_credits c where c.salesforce_account_id = n.salesforce_account_id limit 1) || ' issued ' || to_char((select c.created_date from calc.actual_issued_credits c where c.salesforce_account_id = n.salesforce_account_id limit 1), 'Mon FMDD')
                                            else '$' || to_char(n.amount, 'FM999,990.00') || ' concession requested, no Controller approval on file' end
         when 'void_credit_note' then 'Credit note ' || (select cn.number from raw.stripe_credit_notes cn join raw.salesforce_accounts a on a.stripe_customer_id = cn.customer_id where a.account_id = n.salesforce_account_id and cn.status = 'void' limit 1) || ' ($' || to_char(n.amount, 'FM999,990.00') || ') is void, no current credit effect'
         when 'unassigned_usage' then 'Workspace ' || substring(n.customer from 'pa_[0-9a-f]+') || ' has October metering but no verified owner'
         when 'missing_usage_invoice' then case n.class when 'needs_info' then 'No October usage invoice found, confirm no overage exists' else 'No October usage invoice: verified usage is within the allowance, no overage' end
         when '15th_anchor_timing' then 'Platform invoices on the 15th anchor cover two partial October periods'
         when 'duplicate_usage_record' then 'Repeated usage record ' || (n.evidence->'usage_record_ids'->>0) || ' is not new activity; excluded, billing matches'
         when 'later_service_platform' then 'November-service platform invoice billed $' || to_char((select sum(billed_amount) from calc.v_billed_platform_lines b where b.salesforce_account_id = n.salesforce_account_id and b.period_start >= '2026-11-01'), 'FM999,990.00') || ' vs $' || to_char((select later_service_expected_issued_by_cutoff from calc.v_expected_platform e where e.salesforce_account_id = n.salesforce_account_id), 'FM999,990.00') || ' expected: follow-up, not October'
         else n.detail end as what_we_found,
       case when n.class = 'error' then '$' || to_char(n.amount, 'FM999,990.00')
            when n.check_code in ('void_credit_note', '15th_anchor_timing', 'duplicate_usage_record', 'missing_usage_invoice') and n.class = 'valid_explanation' then '$0.00'
            when n.check_code = 'concession' and n.class = 'valid_explanation' then '$' || to_char(n.amount, 'FM999,990.00')
            when n.check_code = 'concession' then '$' || to_char(n.amount, 'FM999,990.00') || ' requested'
            when n.check_code = 'unassigned_usage' then 'Conditional' else 'TBD' end as amount_display,
       n.amount,
       case n.check_code
         when 'usage_variance' then case n.direction when 'over' then 'Linked credit note' else 'Supplemental invoice' end
                                    || case when (select q.accrual_adjustment_needed from calc.usage_accrual_comparison q where q.salesforce_account_id = n.salesforce_account_id) <> 0 then ', accrual adjustment' else '' end
         when 'platform_variance' then 'Supplemental invoice for the catch-up, recognition true-up'
         when 'concession' then case n.class when 'valid_explanation' then 'None. Accrual already net of the concession' else 'No credit until approved' end
         when 'void_credit_note' then 'None. Void status per MSG-2026-116'
         when 'unassigned_usage' then 'Request ownership evidence, do not force a mapping'
         when 'missing_usage_invoice' then case n.class when 'needs_info' then 'Verify usage against allowance' else 'None. No overage, no invoice due' end
         when '15th_anchor_timing' then 'Day-based allocation to October documented'
         when 'duplicate_usage_record' then 'None. Excluded in the clean usage view'
         when 'later_service_platform' then 'Correct the recurring platform invoice amount in billing' else 'See finding' end as next_step,
       case n.owner when 'Billing (Alex Chen)' then 'Billing' when 'Billing (Alex Chen) with Sales (Morgan Lee)' then 'Billing' when 'Controller (Priya Shah)' then 'Controller'
                    when 'Product Operations' then 'Product Ops' when 'Revenue Accounting (Alex Chen)' then 'Revenue Acctg' else n.owner end as owner,
       exists (select 1 from calc.v_billing_corrections bc where bc.finding_id = n.finding_id) as has_billing_correction,
       exists (select 1 from calc.v_adjustment_lines l where l.finding_id = n.finding_id and l.posts_entry) as has_october_adjustment,
       coalesce((select d.decision from ops.finding_decisions d where d.finding_id = n.finding_id), 'draft') as decision
from n;

create view public.ui_findings_counts as
select count(*) as total, count(*) filter (where class = 'error') as errors, count(*) filter (where class = 'valid_explanation') as valid_explanations,
       count(*) filter (where class = 'needs_info') as needs_info from public.ui_findings_list;

create view public.ui_overview_q2 as
select (select count(*) from calc.v_billing_corrections) as billing_corrections,
       (select count(distinct external_id) from calc.v_adjustment_lines where posts_entry) as october_accounting_adjustments,
       (select count(*) from public.ui_findings_list where class = 'needs_info') as need_more_information,
       (select count(*) from public.ui_findings_list where class = 'valid_explanation') as valid_explanations;

create view public.ui_overview_q3 as
select sort_no, label, amount from (
  select 1 as sort_no, 'Usage accrual reduction (over-billed)' as label, sum(amount) as amount from calc.v_adjustment_lines where posts_entry and adjustment_kind = 'usage_reduce'
  union all select 2, 'Usage accrual increase (under-billed)', sum(amount) from calc.v_adjustment_lines where posts_entry and adjustment_kind = 'usage_increase'
  union all select 3, 'Platform recognition true-up (upgrade)', sum(amount) from calc.v_adjustment_lines where posts_entry and adjustment_kind = 'platform_increase'
  union all select 4, 'Contra revenue, approved credit (placeholder account 4090)', sum(amount) from calc.v_adjustment_lines where posts_entry and selected_treatment = 'contra'
) x where amount is not null and amount <> 0;

create view public.ui_overview_q3_summary as
select (select count(distinct external_id) from calc.v_adjustment_lines where posts_entry) as proposed_entries,
       (select coalesce(sum(credit_minus_debit), 0) from calc.v_revenue_effect where account_number in ('4000', '4010')) as net_revenue_effect,
       (select count(*) from calc.v_adjustment_lines where adjustment_kind = 'concession_already_reflected' and not posts_entry) as concessions_already_reflected,
       (select count(*) from calc.v_adjustment_lines where uses_placeholder_account and posts_entry) as lines_using_placeholder_accounts;

create view public.ui_billing_corrections as
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
       coalesce((select case d.decision when 'approved' then 'Approved' else base_status end from ops.finding_decisions d where d.finding_id = lab.finding_id), base_status) as status
from lab;

create view public.ui_readiness as
select count(*) filter (where status = 'pass') as verified, count(*) as total, count(*) filter (where status = 'pending') as pending, count(*) filter (where status = 'fail') as failed,
       coalesce(string_agg(control_name, '; ') filter (where status = 'pending'), 'none') as pending_names
from calc.v_controls;

grant select on public.ui_footer, public.ui_close_header, public.ui_overview_q1, public.ui_findings_list, public.ui_findings_counts, public.ui_overview_q2,
      public.ui_overview_q3, public.ui_overview_q3_summary, public.ui_billing_corrections, public.ui_readiness to anon, authenticated;
