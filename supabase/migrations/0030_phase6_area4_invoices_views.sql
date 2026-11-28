-- 0030 (Phase 6, Area 4): read-only UI views for Invoices (register, invoice detail, service-period coverage timeline).
-- Timeline bar positions are computed here (percent of the Sep 1 - Nov 30 range); the page only draws them.

create view public.ui_invoices_live as with cn as (select n.invoice_id, string_agg(n.number || ', $' || to_char(n.amount::numeric / 100, 'FM999,990.00') || ', ' || case n.status when 'void' then 'void, no effect' else 'issued ' || to_char(n.created at time zone 'America/Denver', 'Mon FMDD') end, '; ' order by n.number) as txt,
                   count(*) filter (where n.status = 'issued') as issued_n, count(*) filter (where n.status = 'void') as void_n from raw.stripe_credit_notes n group by 1),
     fnd as (select salesforce_account_id, stream, string_agg(display_id, ', ' order by sort_no) as ids from public.ui_findings_list_live group by 1, 2),
     alloc as (select line_id, allocated_to_period from calc.v_billed_platform_lines)
select l.invoice_id, l.invoice_number, c.salesforce_account_id, split_part(c.account_name, ',', 1) as customer, c.netsuite_customer_internal_id as ns_id,
       case when l.stream = 'usage' then 'Usage' when (l.period_end_exclusive - l.period_start) > 62 then 'Platform, annual' else 'Platform, monthly' end as type,
       l.stream, l.issue_date as issued, l.period_start, l.period_end_exclusive,
       to_char(l.period_start, 'Mon FMDD') || ' – ' || to_char(l.period_end_exclusive, 'Mon FMDD') || case when extract(year from l.period_end_exclusive) <> extract(year from l.period_start) then ', ' || extract(year from l.period_end_exclusive)::int else '' end as service_period,
       (l.amount_usd - l.discount_usd) as amount, initcap(l.invoice_status) as status,
       ((l.stream = 'platform' and l.period_start < '2026-11-01' and l.period_end_exclusive > '2026-10-01') or (l.stream = 'usage' and l.period_start >= '2026-10-01' and l.period_start < '2026-11-01')) as covers_october,
       case when l.stream = 'platform' and (l.period_end_exclusive - l.period_start) > 62 then 'Prepaid, $' || to_char(a.allocated_to_period, 'FM999,990.00') || ' allocated to October'
            when l.stream = 'platform' and extract(day from l.period_start) = 15 and l.period_start < '2026-11-01' and l.period_end_exclusive > '2026-10-01' then
                 'Covers Oct ' || extract(day from greatest(l.period_start, date '2026-10-01'))::int || '–' || extract(day from least(l.period_end_exclusive, date '2026-11-01') - 1)::int || ', day-based allocation'
            when l.stream = 'platform' and l.period_start >= '2026-11-01' then 'November service, follow-up only'
            when l.stream = 'platform' and l.period_end_exclusive <= '2026-10-01' then 'September service, context only'
            when l.stream = 'platform' then 'October platform billing'
            when l.period_start < '2026-10-01' then 'Releases Sep 30 accrual of $' || to_char(l.amount_usd - l.discount_usd, 'FM999,990.00')
            else 'October usage billing' end as role_in_review,
       case when (l.stream = 'platform' and l.period_start < '2026-11-01' and l.period_end_exclusive > '2026-10-01') or (l.stream = 'usage' and l.period_start >= '2026-10-01' and l.period_start < '2026-11-01') then f.ids end as finding_ids,
       cn.txt as credit_note_text
from calc.actual_invoice_lines l
join stg.customers c using (salesforce_account_id)
left join alloc a on a.line_id = l.line_id
left join fnd f on f.salesforce_account_id = l.salesforce_account_id and f.stream = l.stream
left join cn on cn.invoice_id = l.invoice_id;
create view public.ui_invoices_summary_live as select count(*) as invoices, count(*) filter (where status = 'Paid') as paid, count(*) filter (where status = 'Open') as open,
       count(*) filter (where covers_october) as covering_october,
       (select count(*) from raw.stripe_credit_notes) as credit_notes, (select count(*) from raw.stripe_credit_notes where status = 'issued') as credit_notes_issued,
       (select count(*) from raw.stripe_credit_notes where status = 'void') as credit_notes_void
from public.ui_invoices_live;
create view public.ui_invoice_detail_live as with gl as (
  select g.external_source_id as invoice_id, min(g.internal_id) as journal, min(g.txn_date) as posting_date,
         string_agg('Dr ' || g.account_number || ' ' || to_char(g.debit, 'FM999,990.00'), ' / ' order by g.line_id) filter (where g.debit > 0) as dr_text,
         string_agg('Cr ' || g.account_number || ' ' || to_char(g.credit, 'FM999,990.00'), ' / ' order by g.line_id) filter (where g.credit > 0) as cr_text,
         max(g.memo) filter (where g.account_number <> '1100') as memo
  from raw.netsuite_gl_detail g where g.transaction_type = 'Invoice' group by 1),
 exp_plat as (select e.salesforce_account_id, e.period_start, e.expected_amount from calc.v_expected_platform_invoices e where e.charge_kind = 'platform_advance'),
 corr as (select b.ref, b.customer, b.document, b.amount, b.linked_to, b.proposed_issue_date, b.finding_id from public.ui_billing_corrections_live b)
select i.invoice_id, i.invoice_number, i.customer, i.salesforce_account_id, i.ns_id, c.stripe_customer_id, i.type, i.stream, i.status, i.finding_ids,
       'Issued ' || to_char(h.created at time zone 'America/Denver', 'Mon FMDD, YYYY, FMHH12:MI AM') || ' MT' as issued_label,
       i.service_period || ', ' || extract(year from i.period_start)::int as service_period_label,
       ln.description as line_description, ln.quantity as quantity,
       case when i.stream = 'usage' then ln.unit_amount_decimal / 100 else i.amount end as unit_price, ln.discount_amount::numeric / 100 as discount, i.amount as invoice_total,
       case when i.stream = 'usage' and i.covers_october then ev.expected_usage_gross - ev.approved_concessions
            when i.stream = 'usage' then ub.expected_usage_charge
            else ep.expected_amount end as expected_amount,
       case when i.stream = 'usage' and i.covers_october then
              case when uf.diagnosis = 'amended_allowance_not_applied' then 'Expected under the amended allowance' else 'Expected under the contract' end
            when i.stream = 'usage' then 'Expected under the contract' else 'Expected platform invoice' end as expected_label,
       case when i.stream = 'usage' and i.covers_october then x.usage_over_billed end as over_billed, case when i.stream = 'usage' and i.covers_october then x.usage_under_billed end as under_billed,
       gl.journal, gl.posting_date, gl.dr_text, gl.cr_text,
       case when gl.memo = 'Release prior service-month usage accrual' then 'Releases the prior service-month accrual to the amount billed.' when gl.memo = 'Platform billing' then 'Records the advance platform billing in deferred platform revenue.' else gl.memo end as posting_note,
       (gl.journal is null) as outside_gl_extract, i.credit_note_text,
       corr.ref as correction_ref, corr.document as correction_document, corr.amount as correction_amount, corr.proposed_issue_date as correction_issue_date,
       (select d.decision from ops.finding_decisions d where d.finding_id = corr.finding_id) as correction_decision
from public.ui_invoices_live i
join stg.customers c using (salesforce_account_id)
join raw.stripe_invoices h on h.id = i.invoice_id
join raw.stripe_invoice_lines ln on ln.invoice_id = i.invoice_id
left join gl on gl.invoice_id = i.invoice_id
left join calc.v_expected_usage ev on ev.salesforce_account_id = i.salesforce_account_id
left join calc.usage_billing_comparison ub on ub.salesforce_account_id = i.salesforce_account_id and ub.month_start = date_trunc('month', i.period_start)::date
left join calc.usage_findings uf on uf.salesforce_account_id = i.salesforce_account_id
left join calc.v_expected_vs_billed x on x.salesforce_account_id = i.salesforce_account_id
left join exp_plat ep on ep.salesforce_account_id = i.salesforce_account_id and ep.period_start = i.period_start
left join corr on corr.customer = i.customer and i.covers_october and ((i.stream = 'usage' and corr.linked_to = i.invoice_number) or (i.stream = 'platform' and corr.document = 'Supplemental invoice' and corr.linked_to like '%catch-up' and i.period_start = date '2026-10-01'));
create view public.ui_coverage_meta_live as select date '2026-09-01' as range_start, date '2026-12-01' as range_end_exclusive, (date '2026-12-01' - date '2026-09-01') as range_days,
       round((date '2026-10-01' - date '2026-09-01')::numeric / (date '2026-12-01' - date '2026-09-01') * 100, 3) as october_left_pct,
       round((date '2026-11-01' - date '2026-10-01')::numeric / (date '2026-12-01' - date '2026-09-01') * 100, 3) as october_width_pct,
       round(((p.cutoff at time zone 'America/Denver')::date - date '2026-09-01')::numeric / (date '2026-12-01' - date '2026-09-01') * 100, 3) as cutoff_pct,
       to_char(p.cutoff at time zone 'America/Denver', 'Mon FMDD') as cutoff_label,
       round((date '2026-11-01' - date '2026-09-01')::numeric / (date '2026-12-01' - date '2026-09-01') * 100, 3) as november_left_pct
from ref.close_params p;
create view public.ui_coverage_live as with m as (select * from public.ui_coverage_meta_live),
fnd as (select salesforce_account_id, string_agg(display_id, ', ' order by sort_no) as ids from public.ui_findings_list_live group by 1),
later as (select e.salesforce_account_id, e.later_service_expected_issued_by_cutoff as exp_nov, b.later_service_billed_by_cutoff as bill_nov
          from calc.v_expected_platform e join calc.v_billed_platform b using (salesforce_account_id)),
amend as (select salesforce_account_id, effective_from from ref.contract_term_versions where version_no = 2),
bars as (
  select i.salesforce_account_id, i.customer, i.invoice_number,
         case i.stream when 'platform' then 1 else 2 end as row_order,
         case when i.stream = 'usage' then 'Usage'
              when i.type = 'Platform, annual' then 'Platform, annual prepaid'
              when extract(day from i.period_start) = 15 then 'Platform, anchor on the 15th' else 'Platform, monthly' end as row_label,
         i.stream as bar_kind, i.period_start, i.period_end_exclusive, i.covers_october, i.finding_ids,
         (i.type = 'Platform, annual') as continues_past,
         i.amount, i.status, i.issued, l.exp_nov, l.bill_nov, am.effective_from as amend_eff, i.invoice_id
  from public.ui_invoices_live i left join later l on l.salesforce_account_id = i.salesforce_account_id left join amend am on am.salesforce_account_id = i.salesforce_account_id
)
select b.salesforce_account_id, b.customer, b.row_order, b.row_label, b.bar_kind, b.invoice_number,
       round((greatest(b.period_start, m.range_start) - m.range_start)::numeric / m.range_days * 100, 3) as left_pct,
       round((least(b.period_end_exclusive, m.range_end_exclusive) - greatest(b.period_start, m.range_start))::numeric / m.range_days * 100, 3) as width_pct,
       case when b.continues_past then to_char(b.period_start, 'Mon FMDD, YYYY') || ' to ' || to_char(b.period_end_exclusive, 'Mon FMDD, YYYY') || ' · $' || to_char(b.amount, 'FM999,990.00') || ' prepaid · October allocation $' ||
              to_char((select a.allocated_to_period from calc.v_billed_platform_lines a where a.invoice_id = b.invoice_id), 'FM999,990.00') || ' (' || to_char(b.amount / 100, 'FM999,990') || '00 × 31 ÷ 365) · continues past this view'
            when b.bar_kind = 'platform' and extract(day from b.period_start) = 15 then to_char(b.period_start, 'Mon FMDD') || ' – ' || to_char(b.period_end_exclusive, 'Mon FMDD') || ' · $' || to_char(b.amount, 'FM999,990.00') || case when b.status = 'Paid' then ' · paid' else '' end
            when b.bar_kind = 'platform' then to_char(b.period_start, 'Mon') || ' · $' || to_char(b.amount, 'FM999,990.00') || case when b.status = 'Paid' then ' · paid' else '' end
                 || case when b.period_start >= '2026-11-01' then ' · later service' else '' end
                 || case when b.period_start >= '2026-11-01' and b.exp_nov is not null and b.exp_nov <> b.bill_nov then ', amendment says $' || to_char(b.exp_nov, 'FM999,990.00') else '' end
                 || case when b.amend_eff is not null and b.period_start <= b.amend_eff and b.period_end_exclusive > b.amend_eff and b.period_start >= '2026-10-01' and b.period_start < '2026-11-01' then ' · upgrade ' || to_char(b.amend_eff, 'Mon FMDD') else '' end
            else to_char(b.period_start, 'Mon') || ' usage · invoiced ' || to_char(b.issued, 'Mon FMDD') || ' · $' || to_char(b.amount, 'FM999,990.00') end as label,
       b.finding_ids, b.covers_october, b.continues_past, b.amount,
       (select ids from fnd where fnd.salesforce_account_id = b.salesforce_account_id) as customer_finding_ids,
       (b.finding_ids is not null) as has_finding
from bars b cross join m
union all
select i.salesforce_account_id, split_part(c.account_name, ',', 1), 2, 'Usage', 'credit_note', n.number,
       round((((n.created at time zone 'America/Denver')::date) - m.range_start)::numeric / m.range_days * 100, 3), 0::numeric,
       case n.status when 'void' then 'Credit note ' || to_char(n.created at time zone 'America/Denver', 'Mon FMDD') || ', $' || to_char(n.amount::numeric / 100, 'FM999,990.00') || ', void, no effect'
                     else 'Credit note ' || to_char(n.created at time zone 'America/Denver', 'Mon FMDD') || ', $' || to_char(n.amount::numeric / 100, 'FM999,990.00') end,
       null, true, false, n.amount::numeric / 100, (select ids from fnd where fnd.salesforce_account_id = i.salesforce_account_id), false
from raw.stripe_credit_notes n join raw.stripe_invoices h on h.id = n.invoice_id
join stg.customers c on c.stripe_customer_id = h.customer_id
join (select distinct invoice_id, salesforce_account_id from public.ui_invoices_live) i on i.invoice_id = n.invoice_id cross join m;
create materialized view public.ui_invoices as select * from public.ui_invoices_live;
grant select on public.ui_invoices to anon, authenticated;
revoke all on public.ui_invoices_live from anon, authenticated;
create materialized view public.ui_invoices_summary as select * from public.ui_invoices_summary_live;
grant select on public.ui_invoices_summary to anon, authenticated;
revoke all on public.ui_invoices_summary_live from anon, authenticated;
create materialized view public.ui_invoice_detail as select * from public.ui_invoice_detail_live;
grant select on public.ui_invoice_detail to anon, authenticated;
revoke all on public.ui_invoice_detail_live from anon, authenticated;
create materialized view public.ui_coverage_meta as select * from public.ui_coverage_meta_live;
grant select on public.ui_coverage_meta to anon, authenticated;
revoke all on public.ui_coverage_meta_live from anon, authenticated;
create materialized view public.ui_coverage as select * from public.ui_coverage_live;
grant select on public.ui_coverage to anon, authenticated;
revoke all on public.ui_coverage_live from anon, authenticated;