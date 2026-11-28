-- 0025 (Phase 6, Area 2): read-only UI views for Reconciliation (Customers, Customer detail, Controls, Assumptions and open items).
-- Each ui_X is a materialized snapshot of ui_X_live (refreshed by ops.refresh_ui); only the snapshots are readable by the browser role.

create view public.ui_customers_live as select s.salesforce_account_id, split_part(s.account_name, ',', 1) as customer, s.account_name, s.netsuite_customer_internal_id as ns_id,
       e.expected_invoices_allocated_to_period as plat_exp_alloc, b.billed_allocated_to_period as plat_bill_alloc,
       greatest(e.expected_invoices_allocated_to_period - b.billed_allocated_to_period, 0) as plat_under_alloc,
       greatest(b.billed_allocated_to_period - e.expected_invoices_allocated_to_period, 0) as plat_over_alloc,
       e.expected_to_bill_for_period as plat_exp_inv, b.billed_invoiced_in_period as plat_bill_inv,
       greatest(e.expected_to_bill_for_period - b.billed_invoiced_in_period, 0) as plat_under_inv,
       greatest(b.billed_invoiced_in_period - e.expected_to_bill_for_period, 0) as plat_over_inv,
       case when v1.billing_frequency = 'annual' then 'Annual prepaid ' || to_char(v1.term_start, 'Mon FMDD')
            when v1.billing_anchor_day = 15 then 'Anchor on the 15th, two partial periods' else 'Monthly, Oct 1 anchor' end
         || case when e.expected_catch_up_required_unbilled > 0 then ' · Includes $' || to_char(e.expected_catch_up_required_unbilled, 'FM999,990.00') || ' upgrade catch-up' else '' end as plat_note,
       x.usage_expected_net as usage_exp, x.usage_billed_net as usage_bill, x.usage_under_billed as usage_under, x.usage_over_billed as usage_over,
       case when ev.attribution_status <> 'verified' then 'To be verified, no invoice'
            when uf.diagnosis = 'amended_allowance_not_applied' then 'Amended allowance'
            when uf.diagnosis = 'billed_rate_differs_from_contract' then 'Billed at the wrong rate'
            when uf.diagnosis = 'no_usage_invoice_issued' then 'No invoice issued'
            when uf.diagnosis is not null then 'Billed quantity differs from metering'
            when bu.credits_issued > 0 then '$' || to_char(bu.credits_issued, 'FM999,990.00') || ' approved credit issued ' || to_char(bu.first_credit_date, 'Mon FMDD')
            when bu.billed_usage_gross = 0 then 'No invoice, within allowance' else null end as usage_note,
       (x.platform_under_billed > 0 or x.platform_over_billed > 0 or x.usage_under_billed > 0 or x.usage_over_billed > 0) as has_variance,
       exists (select 1 from public.ui_findings_list_live f where f.salesforce_account_id = s.salesforce_account_id and f.class = 'needs_info') as has_needs_info,
       (select string_agg(f.display_id || ' ' || case f.class when 'error' then 'error' when 'valid_explanation' then 'valid' else 'info' end, ', ' order by f.sort_no)
          from public.ui_findings_list_live f where f.salesforce_account_id = s.salesforce_account_id) as flags,
       (ev.attribution_status <> 'verified') as usage_unattributed
from stg.customers s
join calc.v_expected_vs_billed x using (salesforce_account_id)
join calc.v_expected_platform e using (salesforce_account_id) join calc.v_billed_platform b using (salesforce_account_id)
join calc.v_expected_usage ev using (salesforce_account_id) join calc.v_billed_usage bu using (salesforce_account_id)
join ref.contract_term_versions v1 on v1.salesforce_account_id = s.salesforce_account_id and v1.version_no = 1
left join calc.usage_findings uf on uf.salesforce_account_id = s.salesforce_account_id;
create view public.ui_customers_summary_live as select sum(plat_under_alloc) + sum(usage_under) as under_billed, sum(plat_over_alloc) + sum(usage_over) as over_billed,
       count(*) filter (where has_variance) as customers_with_variance, count(*) as customers,
       (select count(*) from stg.v_unmapped_product_accounts) as unassigned_workspaces,
       sum(plat_exp_alloc) as plat_exp_alloc, sum(plat_bill_alloc) as plat_bill_alloc, sum(plat_under_alloc) as plat_under_alloc, sum(plat_over_alloc) as plat_over_alloc,
       sum(plat_exp_inv) as plat_exp_inv, sum(plat_bill_inv) as plat_bill_inv, sum(plat_under_inv) as plat_under_inv, sum(plat_over_inv) as plat_over_inv,
       sum(usage_exp) as usage_exp, sum(usage_bill) as usage_bill, sum(usage_under) as usage_under, sum(usage_over) as usage_over
from public.ui_customers_live;
create view public.ui_unassigned_workspace_live as select u.product_account_id, u.account_label, coalesce(m.unverified_units, 0) as october_runs, coalesce(m.record_count, 0) as october_records
from stg.v_unmapped_product_accounts u left join calc.unverified_usage_month m on m.product_account_id = u.product_account_id and m.month_start = (select period_start from ref.close_params);
create view public.ui_customer_header_live as select c.salesforce_account_id, split_part(c.account_name, ',', 1) as customer, c.account_name, c.stripe_customer_id, c.netsuite_customer_internal_id as ns_id,
       array_to_string(x.contract_ids, ', ') as contract_ids,
       case when x.product_account_count = 0 then 'No verified product account' else array_to_string(x.product_account_ids, ', ') || ', verified since ' || to_char((select min(m.effective_from) from raw.product_account_mapping m where m.salesforce_account_id = c.salesforce_account_id), 'Mon FMDD') end as product_accounts,
       (select count(*) from public.ui_findings_list_live f where f.salesforce_account_id = c.salesforce_account_id and f.class = 'error') as error_findings,
       (select string_agg(f.display_id, ', ' order by f.sort_no) from public.ui_findings_list_live f where f.salesforce_account_id = c.salesforce_account_id) as finding_ids
from stg.customers c join stg.v_customer_crosswalk x using (salesforce_account_id);
create view public.ui_customer_kpis_live as select e.salesforce_account_id,
       e.expected_invoices_allocated_to_period as plat_expected, b.billed_allocated_to_period as plat_billed,
       ev.expected_usage_net as usage_expected, bu.billed_usage_net as usage_billed, x.usage_under_billed, x.usage_over_billed, x.platform_under_billed, x.platform_over_billed,
       tp.gl_cr_4000 as plat_revenue_posted, tp.expected_total as plat_revenue_expected, r.service_days_in_period as plat_days, r.base_annual_fee as plat_fee_for_posted,
       tu.gl_cr_4010 as usage_accrual_posted, tu.expected_usage_net as usage_accrual_expected, tu.gl_cr_4010 - tu.expected_usage_net as usage_accrual_diff,
       (select v.platform_billing_amount from ref.contract_term_versions v where v.salesforce_account_id = e.salesforce_account_id and v.version_no = 1) as plat_invoice_amount
from calc.v_expected_platform e join calc.v_billed_platform b using (salesforce_account_id) join calc.v_expected_usage ev using (salesforce_account_id)
join calc.v_billed_usage bu using (salesforce_account_id) join calc.v_expected_vs_billed x using (salesforce_account_id)
join calc.v_tieout_platform_recognition tp using (salesforce_account_id) join calc.v_tieout_usage_accrual tu using (salesforce_account_id) join calc.v_expected_platform_revenue r using (salesforce_account_id);
create view public.ui_customer_versions_live as select v.salesforce_account_id, v.version_no, v.source_document_id as doc, case v.version_type when 'original' then 'Order form' else 'Amendment' end as type_label,
       case when v.version_type = 'original' then
              'Effective ' || to_char(v.term_start, 'Mon FMDD, YYYY') || ' to ' || to_char(v.term_end_exclusive - 1, 'Mon FMDD, YYYY') || '. ' || to_char(v.included_runs_per_month, 'FM999,999') || ' included runs per month, $' || to_char(v.overage_rate_per_run, 'FM0.00') || ' per extra run, platform $' || to_char(v.platform_fee_annual, 'FM999,999') || ' per year billed $' || to_char(v.platform_billing_amount, 'FM999,999') || case when v.billing_frequency = 'annual' then ' annually.' else ' monthly.' end
            else 'Signed ' || to_char(r.signed_at at time zone 'America/Denver', 'Mon FMDD') || ', effective ' || to_char(v.effective_from, 'Mon FMDD') || '. Changes only '
                 || (select string_agg(case t when 'included_runs_per_month' then 'the allowance, ' || to_char(b.included_runs_per_month, 'FM999,999') || ' to ' || to_char(v.included_runs_per_month, 'FM999,999') || ' per month'
                                            when 'platform_fee_annual' then 'the annual platform fee, $' || to_char(b.platform_fee_annual, 'FM999,999') || ' to $' || to_char(v.platform_fee_annual, 'FM999,999') || ' (monthly invoice $' || to_char(b.platform_billing_amount, 'FM999,999') || ' to $' || to_char(v.platform_billing_amount, 'FM999,999') || ' from Nov 1)'
                                            else null end, ' and ') from unnest(v.changed_terms) t where t <> 'platform_billing_amount')
                 || '. All other terms continue from the order form.' end as summary,
       (v.version_type = 'amendment' and r.billing_loaded_at is null) as billing_load_missing, v.approval_status
from ref.contract_term_versions v join raw.contract_register r on r.document_id = v.source_document_id
left join ref.contract_term_versions b on b.salesforce_account_id = v.salesforce_account_id and b.version_no = 1;
create view public.ui_customer_allowance_live as select salesforce_account_id, ord, label from (
  select v.salesforce_account_id, 1 as ord,
         'Oct ' || extract(day from greatest(v.effective_from, p.period_start))::int || '–' || extract(day from least(v.effective_to_exclusive, p.period_end_exclusive) - 1)::int
           || ' · ' || to_char(v.included_runs_per_month, 'FM999,999') || ' × ' || (least(v.effective_to_exclusive, p.period_end_exclusive) - greatest(v.effective_from, p.period_start)) || ' days' as label
  from ref.contract_term_versions v cross join ref.close_params p
  where v.approval_status = 'approved' and v.effective_from < p.period_end_exclusive and v.effective_to_exclusive > p.period_start
  union all
  select a.salesforce_account_id, 2, 'Weighted allowance = ' || to_char(a.allowance_unrounded, 'FM999,990.00') || ', rounded once to ' || to_char(a.allowance_runs, 'FM999,999') || ' runs'
  from calc.v_usage_allowance a) z;
create view public.ui_customer_usage_validation_live as select s.salesforce_account_id, x.product_account_count as accounts_verified, x.product_account_count as accounts_total,
       (select count(distinct u.service_date) from stg.usage_verified u where u.salesforce_account_id = s.salesforce_account_id and u.service_date >= p.period_start and u.service_date < p.period_end_exclusive) as days_with_records,
       (p.period_end_exclusive - p.period_start) as days_in_period,
       (select count(*) - count(distinct r.record_id) from raw.product_usage r join raw.product_account_mapping m using (product_account_id) where m.salesforce_account_id = s.salesforce_account_id) as duplicate_records,
       ev.verified_units as total_runs, ev.allowance_runs, ev.overage_units, ev.overage_rate_per_run, ev.expected_usage_gross,
       (ev.attribution_status <> 'verified') as no_verified_usage
from stg.customers s join stg.v_customer_crosswalk x using (salesforce_account_id) join calc.v_expected_usage ev using (salesforce_account_id) cross join ref.close_params p;
create view public.ui_customer_invoices_live as select l.salesforce_account_id, l.invoice_number as invoice, case l.stream when 'platform' then 'Platform' else 'Usage' end as type, l.issue_date as issued,
       to_char(l.period_start, 'Mon FMDD') || ' – ' || to_char(l.period_end_exclusive, 'Mon FMDD') as service_period, (l.amount_usd - l.discount_usd) as amount,
       initcap(l.invoice_status) as status,
       case when l.stream = 'platform' and l.period_end_exclusive <= '2026-10-01' then 'September service, context only'
            when l.stream = 'platform' and l.period_start >= '2026-11-01' then 'November service, follow-up only'
            when l.stream = 'platform' and (l.period_end_exclusive - l.period_start) > 62 then 'Annual prepaid, October revenue is a day-based allocation'
            when l.stream = 'platform' then 'October platform billing'
            when l.stream = 'usage' and l.period_start < '2026-10-01' then 'Releases Sep 30 accrual of $' || to_char(l.amount_usd - l.discount_usd, 'FM999,990.00')
            else 'October usage billing, ' || to_char(l.quantity, 'FM999,999') || ' runs at $' || to_char(l.unit_amount_decimal / 100, 'FM0.00') end as use_in_review
from calc.actual_invoice_lines l;
create view public.ui_customer_credit_notes_live as select a.account_id as salesforce_account_id, n.number, initcap(n.status) as status, n.amount::numeric / 100 as amount, (n.created at time zone 'America/Denver')::date as created,
       n.reason, case n.status when 'issued' then 'Issued: reduces billed October usage' else 'Void: no current credit effect' end as use_in_review
from raw.stripe_credit_notes n join raw.salesforce_accounts a on a.stripe_customer_id = n.customer_id;
create view public.ui_customer_gl_trail_live as select s.salesforce_account_id, g.internal_id as journal, min(g.txn_date) as posting_date, min(g.created_at at time zone 'America/Denver')::date as created,
       coalesce(max(g.memo) filter (where g.account_number not in ('1100')), max(g.memo)) || ': Dr ' || string_agg(distinct g.account_number, '/' ) filter (where g.debit > 0) || ' / Cr ' || string_agg(distinct g.account_number, '/') filter (where g.credit > 0) as entry,
       sum(g.debit) as amount
from raw.netsuite_gl_detail g join stg.customers s on s.netsuite_customer_internal_id = g.customer_internal_id
where g.posting_period = 'Oct 2026' group by 1, 2;
create view public.ui_customer_rollforward_live as with o as (select customer_internal_id c, account_number a, sum(debit_balance - credit_balance) bal from raw.netsuite_opening_balances group by 1, 2),
     g as (select customer_internal_id c,
             sum(credit) filter (where account_number = '1150' and transaction_type = 'Invoice') as rel_1150,
             sum(debit) filter (where account_number = '1150' and transaction_type = 'Journal') as acc_1150,
             sum(credit) filter (where account_number = '2200' and transaction_type = 'Invoice') as inv_2200,
             sum(debit) filter (where account_number = '2200' and memo not ilike '%contract asset%') as rec_2200,
             sum(credit) filter (where account_number = '2200' and memo ilike '%contract asset%') as reclass_2200
           from raw.netsuite_gl_detail where posting_period = 'Oct 2026' group by 1)
select s.salesforce_account_id, 1 as ord, '1150 unbilled usage' as account_label,
       to_char(o1150.bal, 'FM999,990.00') || ' − ' || to_char(coalesce(g.rel_1150, 0), 'FM999,990.00') || ' + ' || to_char(coalesce(g.acc_1150, 0), 'FM999,990.00') || ' = ' || to_char(o1150.bal - coalesce(g.rel_1150, 0) + coalesce(g.acc_1150, 0), 'FM999,990.00') || ' posted' as posted_text,
       'Expected after correction: ' || to_char(ev.expected_usage_net, 'FM999,990.00') as note
from stg.customers s join o o1150 on o1150.c = s.netsuite_customer_internal_id and o1150.a = '1150' left join g on g.c = s.netsuite_customer_internal_id
join calc.v_expected_usage ev on ev.salesforce_account_id = s.salesforce_account_id
union all
select s.salesforce_account_id, 2, '2200 deferred platform',
       case when -o2200.bal >= 0 then 'Cr ' else 'Dr ' end || to_char(abs(o2200.bal), 'FM999,990.00') || ' + Cr ' || to_char(coalesce(g.inv_2200, 0), 'FM999,990.00') || ' − Dr ' || to_char(coalesce(g.rec_2200, 0), 'FM999,990.00') || ' = '
         || case when (-o2200.bal + coalesce(g.inv_2200, 0) - coalesce(g.rec_2200, 0)) >= 0 then 'Cr ' else 'Dr ' end || to_char(abs(-o2200.bal + coalesce(g.inv_2200, 0) - coalesce(g.rec_2200, 0)), 'FM999,990.00'),
       case when (-o2200.bal + coalesce(g.inv_2200, 0) - coalesce(g.rec_2200, 0)) < 0 then 'Reclassified to 1160, per policy' else 'No net debit, no reclass needed' end
from stg.customers s join o o2200 on o2200.c = s.netsuite_customer_internal_id and o2200.a = '2200' left join g on g.c = s.netsuite_customer_internal_id;
create view public.ui_controls_live as select control_id, control_group, control_name, expected, found, status, source, detail from calc.v_controls;
create view public.ui_open_items_live as select ref, item, what_we_know, what_is_missing, exposure, owner, status from (
  select 'O-1' as ref, 1 as ord, 'Unverified workspace ' || u.product_account_id as item,
         u.october_records || ' October records totaling ' || to_char(u.october_runs, 'FM999,999') || ' runs. Registry label reads "' || u.account_label || '". It may be internal or belong to an existing customer.' as what_we_know,
         'Verified owner from Product Operations (MSG-2026-131). It must not be assigned by elimination or by account name.' as what_is_missing,
         'Conditional: $' || to_char((select min(incremental_charge_if_owned) from calc.unverified_conditional_exposure where month_start = '2026-10-01'), 'FM999,990.00') || ' to $' || to_char((select max(incremental_charge_if_owned) from calc.unverified_conditional_exposure where month_start = '2026-10-01'), 'FM999,990.00') || ' of October overage depending on the owner. Not included in any total.' as exposure,
         'Product Ops' as owner, 'Open' as status
  from public.ui_unassigned_workspace_live u
  union all
  select 'O-2', 2, 'Willow Passage concession request $' || to_char(a.amount, 'FM999,990.00'), 'Sales requested it (' || a.msg_id || '). No Controller approval exists, and the request does not establish ownership of any unverified workspace.',
         'Controller approval, if any.', 'None until approved. No credit or revenue reduction is proposed.', 'Controller', 'Open'
  from ref.approvals a where a.status = 'requested_unapproved'
  union all
  select 'O-3', 3, 'No October usage invoice',
         (select string_agg(split_part(f.customer, ',', 1) || ' (' || case f.class when 'needs_info' then 'usage unattributed' when 'valid_explanation' then 'within the allowance, valid' else 'overage exists, error' end || ')', ', ' order by f.customer) from calc.v_findings f where f.check_code = 'missing_usage_invoice')
           || '. No Nov 1 usage invoice was issued; that is valid only when usage stays within the allowance.',
         'Willow Passage: verified usage attribution. Yarrow Ridge: the missing invoice.', 'Yarrow Ridge: $' || to_char((select amount from calc.v_findings where check_code = 'usage_variance' and customer like 'Yarrow%'), 'FM999,990.00') || ' under-billed. Willow Passage: unknown until usage is attributed.', 'Revenue Acctg', 'Open'
  union all
  select 'O-4', 4, 'Zephyr Grove accrual basis',
         'Approved $' || to_char(q.approved_concessions, 'FM999,990.00') || ' concession (MSG-2026-109) says the accrual must already be net. Credit note issued ' || to_char((select min(c.created_date) from calc.actual_issued_credits c where c.salesforce_account_id = q.salesforce_account_id), 'Mon FMDD') || '. The posted October accrual is $' || to_char(a.gl_accrued, 'FM999,990.00') || ' and the expected net is $' || to_char(a.expected_net, 'FM999,990.00') || '.',
         'Confirmed: the posted accrual is net of the concession.', 'None. A contra-revenue entry would reduce revenue twice (selectable on Journal entries with a warning).', 'Revenue Acctg', 'Resolved'
  from calc.v_expected_usage q join calc.usage_accrual_comparison a using (salesforce_account_id) where q.approved_concessions > 0
  union all
  select 'O-5', 5, 'Later-service follow-up: Meridian Process Systems',
         'AM-OF-2026-164 sets $' || to_char((select platform_billing_amount from ref.contract_term_versions where base_document_id = 'OF-2026-164' and version_no = 2), 'FM999,990.00') || ' from Nov 1, but the Nov 1 platform invoice is $' || to_char((select sum(billed_amount) from calc.v_billed_platform_lines b join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%' and b.period_start >= '2026-11-01'), 'FM999,990.00') || '. Both amendments show no billing load date.',
         'Billing update before the next billing run. November is not reconciled in this review.', 'November is under-billed by $' || to_char((select amount from calc.v_findings where check_code = 'later_service_platform'), 'FM999,990.00') || ' per month until corrected.', 'Billing', 'Open'
  union all
  select 'O-6', 6, 'Meridian catch-up journal treatment', 'The $' || to_char((select amount from ref.contract_term_fees where kind = 'october_upgrade_catch_up'), 'FM999,990.00') || ' catch-up is treated as required (owner decision). The default accrual treatment is proposed.',
         'Owner to confirm or change the journal treatment on the Journal entries page.', 'Revenue timing only; the amount is fixed by the amendment.', 'Controller', 'Open'
  union all
  select 'O-7', 7, 'Controller approval and billing issue date', (select count(*) from ref.journal_approvals) || ' of ' || (select count(distinct external_id) from calc.v_adjustment_lines where posts_entry) || ' proposed entries approved. Proposed billing issue date is ' || to_char((select proposed_billing_issue_date from ref.close_params), 'Mon FMDD, YYYY') || '.',
         'Controller approval of the entries and confirmation of the November issue date.', 'None until approved. Nothing is posted from this app.', 'Controller', 'Open'
  union all
  select 'O-8', 8, 'Placeholder accounts 4090 and 6900', 'Accounts 4090 (contra revenue) and 6900 (write-off) are not in the supplied chart of accounts. No default entry uses them.',
         'Map to real NetSuite accounts before importing any entry that selects them.', 'None by default.', 'Revenue Acctg', 'Open'
  union all
  select 'O-9', 9, 'Beacon Marsh billed quantity', 'Billed ' || to_char(uf.billed_units, 'FM999,999') || ' overage runs against ' || to_char(uf.expected_overage_units, 'FM999,999') || ' metered; the metering ties to the batch controls.',
         'Billing to confirm why the invoice quantity is ' || to_char(uf.expected_overage_units - uf.billed_units, 'FM999,999') || ' runs short.', '$' || to_char(uf.billing_difference, 'FM999,990.00') || ' under-billed; the October accrual is already correct.', 'Billing', 'Open'
  from calc.usage_findings uf join stg.customers c using (salesforce_account_id) where c.account_name like 'Beacon%'
) z order by ord;
create view public.ui_assumptions_live as select ref, assumption, source, status from (values
 ('A-1', 1, 'Platform revenue is recognized by actual service days ÷ 365, independent of invoice frequency.', 'START_HERE, Accounting', 'Policy'),
 ('A-2', 2, 'Advance platform invoices are shown with a day-based allocation to October (an invoice-period view is also available). Annual prepaid fees are not billed again in October.', 'START_HERE, Billing basis', 'Basis chosen'),
 ('A-3', 3, 'Usage is summed across a customer''s verified product accounts before the calendar-month allowance. Records are deduplicated on record_id.', 'START_HERE, Usage', 'Policy'),
 ('A-4', 4, 'For an allowance amendment, each allowance is weighted by calendar days and rounded once to a whole run, half up. Charges round once to cents.', 'START_HERE, Usage; AM-OF-2026-157', 'Policy'),
 ('A-5', 5, 'Void credit notes have no current credit effect, so the voided $' || (select to_char(amount::numeric / 100, 'FM999,990') from raw.stripe_credit_notes where status = 'void' limit 1) || ' Alder note is ignored.', 'START_HERE, Credits; MSG-2026-116', 'Policy'),
 ('A-6', 6, 'An unapproved concession request does not authorize a credit or revenue reduction.', 'START_HERE, Unverified usage', 'Policy'),
 ('A-7', 7, 'Invoices issued by the ' || (select to_char(cutoff at time zone 'America/Denver', 'Mon FMDD, YYYY FMHH12:MI AM') || ' MT' from ref.close_params) || ' cutoff are included. Later invoices are not.', 'START_HERE, Billing', 'Policy'),
 ('A-8', 8, 'Proposed billing documents carry November issue dates. Supported October-service accounting corrections post to October.', 'START_HERE, Approval and dates', 'Policy'),
 ('A-9', 9, 'Contract terms are read from the executed PDFs and each term links to its page. The owner approved the extracted terms on ' || (select to_char(max(approved_at at time zone 'America/Denver'), 'Mon FMDD') from ref.contract_term_versions) || '.', 'START_HERE, Source precedence', 'Reviewed and approved'),
 ('A-10', 10, 'Tax, foreign currency, collections, processing fees and breakage are out of scope. Unpaid invoices alone imply no adjustment.', 'START_HERE, Company rules', 'Policy'),
 ('A-11', 11, 'Unverified usage is isolated and never assigned by elimination, by account name or by one-to-one assumption.', 'START_HERE, Unverified usage; MSG-2026-131', 'Policy'),
 ('A-12', 12, 'A billing correction is not an automatic revenue adjustment: an October entry exists only where the posted accrual or recognition differs from contract support.', 'START_HERE, Credits and Accounting', 'Policy')
) t(ref, ord, assumption, source, status) order by ord;
create materialized view public.ui_customers as select * from public.ui_customers_live;
grant select on public.ui_customers to anon, authenticated;
revoke all on public.ui_customers_live from anon, authenticated;
create materialized view public.ui_customers_summary as select * from public.ui_customers_summary_live;
grant select on public.ui_customers_summary to anon, authenticated;
revoke all on public.ui_customers_summary_live from anon, authenticated;
create materialized view public.ui_unassigned_workspace as select * from public.ui_unassigned_workspace_live;
grant select on public.ui_unassigned_workspace to anon, authenticated;
revoke all on public.ui_unassigned_workspace_live from anon, authenticated;
create materialized view public.ui_customer_header as select * from public.ui_customer_header_live;
grant select on public.ui_customer_header to anon, authenticated;
revoke all on public.ui_customer_header_live from anon, authenticated;
create materialized view public.ui_customer_kpis as select * from public.ui_customer_kpis_live;
grant select on public.ui_customer_kpis to anon, authenticated;
revoke all on public.ui_customer_kpis_live from anon, authenticated;
create materialized view public.ui_customer_versions as select * from public.ui_customer_versions_live;
grant select on public.ui_customer_versions to anon, authenticated;
revoke all on public.ui_customer_versions_live from anon, authenticated;
create materialized view public.ui_customer_allowance as select * from public.ui_customer_allowance_live;
grant select on public.ui_customer_allowance to anon, authenticated;
revoke all on public.ui_customer_allowance_live from anon, authenticated;
create materialized view public.ui_customer_usage_validation as select * from public.ui_customer_usage_validation_live;
grant select on public.ui_customer_usage_validation to anon, authenticated;
revoke all on public.ui_customer_usage_validation_live from anon, authenticated;
create materialized view public.ui_customer_invoices as select * from public.ui_customer_invoices_live;
grant select on public.ui_customer_invoices to anon, authenticated;
revoke all on public.ui_customer_invoices_live from anon, authenticated;
create materialized view public.ui_customer_credit_notes as select * from public.ui_customer_credit_notes_live;
grant select on public.ui_customer_credit_notes to anon, authenticated;
revoke all on public.ui_customer_credit_notes_live from anon, authenticated;
create materialized view public.ui_customer_gl_trail as select * from public.ui_customer_gl_trail_live;
grant select on public.ui_customer_gl_trail to anon, authenticated;
revoke all on public.ui_customer_gl_trail_live from anon, authenticated;
create materialized view public.ui_customer_rollforward as select * from public.ui_customer_rollforward_live;
grant select on public.ui_customer_rollforward to anon, authenticated;
revoke all on public.ui_customer_rollforward_live from anon, authenticated;
create materialized view public.ui_controls as select * from public.ui_controls_live;
grant select on public.ui_controls to anon, authenticated;
revoke all on public.ui_controls_live from anon, authenticated;
create materialized view public.ui_open_items as select * from public.ui_open_items_live;
grant select on public.ui_open_items to anon, authenticated;
revoke all on public.ui_open_items_live from anon, authenticated;
create materialized view public.ui_assumptions as select * from public.ui_assumptions_live;
grant select on public.ui_assumptions to anon, authenticated;
revoke all on public.ui_assumptions_live from anon, authenticated;

create or replace function ops.refresh_ui(p_scope text default 'all') returns void language plpgsql as $f$
begin
  if p_scope in ('all', 'findings') then
    refresh materialized view public.ui_findings_list; refresh materialized view public.ui_findings_counts;
    refresh materialized view public.ui_finding_detail; refresh materialized view public.ui_finding_evidence; refresh materialized view public.ui_finding_math;
    refresh materialized view public.ui_finding_math_notes; refresh materialized view public.ui_finding_action; refresh materialized view public.ui_finding_sources;
  end if;
  if p_scope in ('all', 'overview', 'journal') then
    refresh materialized view public.ui_close_header; refresh materialized view public.ui_overview_q1; refresh materialized view public.ui_overview_q2;
    refresh materialized view public.ui_overview_q3; refresh materialized view public.ui_overview_q3_summary; refresh materialized view public.ui_readiness;
  end if;
  if p_scope in ('all', 'corrections', 'journal') then refresh materialized view public.ui_billing_corrections; end if;
  if p_scope in ('all', 'recon') then
    refresh materialized view public.ui_customers;
    refresh materialized view public.ui_customers_summary;
    refresh materialized view public.ui_unassigned_workspace;
    refresh materialized view public.ui_customer_header;
    refresh materialized view public.ui_customer_kpis;
    refresh materialized view public.ui_customer_versions;
    refresh materialized view public.ui_customer_allowance;
    refresh materialized view public.ui_customer_usage_validation;
    refresh materialized view public.ui_customer_invoices;
    refresh materialized view public.ui_customer_credit_notes;
    refresh materialized view public.ui_customer_gl_trail;
    refresh materialized view public.ui_customer_rollforward;
    refresh materialized view public.ui_controls;
    refresh materialized view public.ui_open_items;
    refresh materialized view public.ui_assumptions;
  end if;
end $f$;
