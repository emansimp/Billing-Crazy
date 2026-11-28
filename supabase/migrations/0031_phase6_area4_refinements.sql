-- 0031: Area 4 refinements: thousands separator in the annual-invoice coverage label; the November follow-up finding attaches to the November platform invoice only.
create or replace view public.ui_invoices_live as with cn as (select n.invoice_id, string_agg(n.number || ', $' || to_char(n.amount::numeric / 100, 'FM999,990.00') || ', ' || case n.status when 'void' then 'void, no effect' else 'issued ' || to_char(n.created at time zone 'America/Denver', 'Mon FMDD') end, '; ' order by n.number) as txt,
                   count(*) filter (where n.status = 'issued') as issued_n, count(*) filter (where n.status = 'void') as void_n from raw.stripe_credit_notes n group by 1),
     fnd as (select salesforce_account_id, stream, string_agg(display_id, ', ' order by sort_no) as ids from public.ui_findings_list_live where period_label <> 'Nov 1–30' group by 1, 2),
     fnd_nov as (select salesforce_account_id, stream, string_agg(display_id, ', ' order by sort_no) as ids from public.ui_findings_list_live where period_label = 'Nov 1–30' group by 1, 2),
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
       case when (l.stream = 'platform' and l.period_start < '2026-11-01' and l.period_end_exclusive > '2026-10-01') or (l.stream = 'usage' and l.period_start >= '2026-10-01' and l.period_start < '2026-11-01') then f.ids when l.stream = 'platform' and l.period_start >= '2026-11-01' then fn.ids end as finding_ids,
       cn.txt as credit_note_text
from calc.actual_invoice_lines l
join stg.customers c using (salesforce_account_id)
left join alloc a on a.line_id = l.line_id
left join fnd f on f.salesforce_account_id = l.salesforce_account_id and f.stream = l.stream
left join fnd_nov fn on fn.salesforce_account_id = l.salesforce_account_id and fn.stream = l.stream
left join cn on cn.invoice_id = l.invoice_id;
create or replace view public.ui_coverage_live as with m as (select * from public.ui_coverage_meta_live),
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
              to_char((select a.allocated_to_period from calc.v_billed_platform_lines a where a.invoice_id = b.invoice_id), 'FM999,990.00') || ' (' || to_char(b.amount, 'FM999,990') || ' × 31 ÷ 365) · continues past this view'
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
refresh materialized view public.ui_invoices; refresh materialized view public.ui_invoices_summary; refresh materialized view public.ui_invoice_detail; refresh materialized view public.ui_coverage;

create or replace function ops.refresh_invoices() returns void language plpgsql as $f$
begin
  refresh materialized view public.ui_invoices; refresh materialized view public.ui_invoices_summary; refresh materialized view public.ui_invoice_detail;
  refresh materialized view public.ui_coverage_meta; refresh materialized view public.ui_coverage;
end $f$;
