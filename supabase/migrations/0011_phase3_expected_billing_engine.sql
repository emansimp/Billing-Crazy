-- 0011 (Phase 3): expected-billing engine. Exact numeric only. Platform and usage stay separate throughout.
-- Reads ONLY approved contract versions (ref.contract_term_versions). Period comes from ref.close_params (October 2026).
-- Rounding: PostgreSQL round(numeric, 2) rounds half away from zero = half up for positive amounts.

-- ---------- PLATFORM: expected revenue = fee x service days / 365, split by contract version ----------
-- START_HERE: "preserve the original base schedule when adding an upgrade increment". Components, each rounded once to cents:
--   base      = v1 annual fee x all service days in the period / 365
--   increment = (version k fee - v1 fee) x days in version k / 365   (k > 1)
-- The plain per-version split (fee_k x days_k / 365, each rounded) is shown alongside as a cross-check.
create view calc.v_expected_platform_revenue as
with p as (select period_start ps, period_end_exclusive pe from ref.close_params),
seg as (
  select v.salesforce_account_id, v.version_id, v.version_no, v.platform_fee_annual as fee,
         greatest(v.effective_from, p.ps) as s, least(v.effective_to_exclusive, p.pe) as e
  from ref.contract_term_versions v cross join p where v.approval_status = 'approved'
), seg2 as (select *, (e - s) as days from seg where e > s),
v1 as (select salesforce_account_id, platform_fee_annual as base_fee from ref.contract_term_versions where version_no = 1 and approval_status = 'approved'),
tot as (select salesforce_account_id, sum(days) as service_days from seg2 group by 1),
inc as (select s.salesforce_account_id, sum(round((s.fee - v1.base_fee) * s.days / 365, 2)) as increment_revenue,
               string_agg(s.version_id || ': ' || s.days || ' days', '; ' order by s.version_no) as increment_basis
        from seg2 s join v1 using (salesforce_account_id) where s.version_no > 1 group by 1),
spl as (select salesforce_account_id, sum(round(fee * days / 365, 2)) as version_split_revenue,
               string_agg(version_id || ' ' || days || 'd @ ' || fee, ' | ' order by version_no) as version_split_basis from seg2 group by 1)
select c.salesforce_account_id, c.account_name, coalesce(tot.service_days, 0) as service_days_in_period, v1.base_fee as base_annual_fee,
       round(v1.base_fee * coalesce(tot.service_days, 0) / 365, 2) as base_revenue,
       coalesce(inc.increment_revenue, 0) as increment_revenue,
       round(v1.base_fee * coalesce(tot.service_days, 0) / 365, 2) + coalesce(inc.increment_revenue, 0) as expected_revenue,
       spl.version_split_revenue,
       round(v1.base_fee * coalesce(tot.service_days, 0) / 365, 2) + coalesce(inc.increment_revenue, 0) - spl.version_split_revenue as rounding_difference_vs_split,
       spl.version_split_basis, inc.increment_basis
from stg.customers c join v1 using (salesforce_account_id) left join tot using (salesforce_account_id)
left join inc using (salesforce_account_id) left join spl using (salesforce_account_id);

-- ---------- PLATFORM: expected invoices (advance billing), incl. 15th-anchor customers and the required Meridian catch-up ----------
-- Monthly customers: one invoice per month on the anchor day (1st or 15th), covering [invoice date, invoice date + 1 month).
-- Annual customers: one invoice on service start covering the term. Invoice amount = amount of the version in effect on the invoice date.
create view calc.v_expected_platform_invoices as
with p as (select period_start ps, period_end_exclusive pe, cutoff from ref.close_params),
orig as (select * from ref.contract_term_versions where version_no = 1 and approval_status = 'approved'),
sched as (
  select o.salesforce_account_id, o.billing_anchor_day, o.billing_frequency, o.term_end_exclusive,
         (o.term_start + (n || ' month')::interval)::date as invoice_date
  from orig o cross join generate_series(0, 13) n where o.billing_frequency = 'monthly'
  union all select o.salesforce_account_id, o.billing_anchor_day, o.billing_frequency, o.term_end_exclusive, o.term_start from orig o where o.billing_frequency = 'annual'
), inv as (
  select s.salesforce_account_id, s.billing_anchor_day, 'platform_advance'::text as charge_kind, s.invoice_date,
         s.invoice_date as period_start,
         case when s.billing_frequency = 'annual' then s.term_end_exclusive else least((s.invoice_date + interval '1 month')::date, s.term_end_exclusive) end as period_end_exclusive,
         (select v.platform_billing_amount from ref.contract_term_versions v
           where v.salesforce_account_id = s.salesforce_account_id and v.approval_status = 'approved'
             and v.effective_from <= s.invoice_date and s.invoice_date < v.effective_to_exclusive) as amount,
         (select v.version_id from ref.contract_term_versions v
           where v.salesforce_account_id = s.salesforce_account_id and v.approval_status = 'approved'
             and v.effective_from <= s.invoice_date and s.invoice_date < v.effective_to_exclusive) as version_id
  from sched s cross join p where s.invoice_date < s.term_end_exclusive and s.invoice_date <= p.cutoff::date
  union all
  -- Required upgrade catch-up (owner decision 2026-11-23). Not yet billed; proposed Nov-dated invoice. Period = rest of the amendment month.
  select v.salesforce_account_id, v.billing_anchor_day, 'upgrade_catch_up', null::date, f.effective_from,
         (date_trunc('month', f.effective_from) + interval '1 month')::date, f.amount, v.version_id
  from ref.contract_term_fees f join ref.contract_term_versions v on v.version_id = f.version_id
  where f.kind = 'october_upgrade_catch_up' and f.status = 'extracted' and f.owner_decision = 'treat_as_required'
)
select i.salesforce_account_id, i.charge_kind, i.billing_anchor_day, i.version_id, i.invoice_date, i.period_start, i.period_end_exclusive,
       (i.period_end_exclusive - i.period_start) as period_days,
       greatest(0, least(i.period_end_exclusive, p.pe) - greatest(i.period_start, p.ps)) as days_in_report_period,
       i.amount as expected_amount,
       round(i.amount * greatest(0, least(i.period_end_exclusive, p.pe) - greatest(i.period_start, p.ps)) / (i.period_end_exclusive - i.period_start), 2) as allocated_to_period,
       (i.invoice_date >= p.ps and i.invoice_date < p.pe) as issued_in_period,
       (i.period_start < p.pe and i.period_end_exclusive > p.ps) as covers_period,
       (i.period_start < p.pe and i.period_end_exclusive > p.pe) as crosses_period_end,
       (i.period_start < p.ps and i.period_end_exclusive > p.ps) as crosses_period_start
from inv i cross join p;

-- Expected platform per customer for the period. Two bases, never mixed:
--  revenue basis  = fee x days / 365 (accounting), invoice basis = invoices issued in the period (+ required catch-up).
create view calc.v_expected_platform as
select c.salesforce_account_id, c.account_name, x.billing_anchor_day,
       r.expected_revenue, r.base_revenue, r.increment_revenue, r.service_days_in_period,
       coalesce(sum(i.expected_amount) filter (where i.charge_kind = 'platform_advance' and i.issued_in_period), 0) as expected_invoiced_in_period,
       coalesce(sum(i.expected_amount) filter (where i.charge_kind = 'upgrade_catch_up'), 0) as expected_catch_up_required_unbilled,
       coalesce(sum(i.expected_amount) filter (where (i.charge_kind = 'platform_advance' and i.issued_in_period) or i.charge_kind = 'upgrade_catch_up'), 0) as expected_to_bill_for_period,
       coalesce(sum(i.allocated_to_period) filter (where i.covers_period), 0) as expected_invoices_allocated_to_period,
       coalesce(sum(i.expected_amount) filter (where i.charge_kind = 'platform_advance' and i.period_start >= (select period_end_exclusive from ref.close_params)), 0) as later_service_expected_issued_by_cutoff,
       (x.billing_anchor_day = 15) as is_15th_anchor
from stg.customers c
join calc.v_expected_platform_revenue r using (salesforce_account_id)
join (select distinct salesforce_account_id, billing_anchor_day from ref.contract_term_versions where version_no = 1) x using (salesforce_account_id)
left join calc.v_expected_platform_invoices i using (salesforce_account_id)
group by c.salesforce_account_id, c.account_name, x.billing_anchor_day, r.expected_revenue, r.base_revenue, r.increment_revenue, r.service_days_in_period;

-- ---------- PLATFORM: billed (Stripe lines with product prod_platform) ----------
create view calc.v_billed_platform_lines as
with p as (select period_start ps, period_end_exclusive pe from ref.close_params)
select l.salesforce_account_id, l.invoice_id, l.invoice_number, l.issue_date, l.invoice_status, l.line_id, l.period_start, l.period_end_exclusive,
       (l.amount_usd - l.discount_usd) as billed_amount,
       (l.period_end_exclusive - l.period_start) as period_days,
       greatest(0, least(l.period_end_exclusive, p.pe) - greatest(l.period_start, p.ps)) as days_in_report_period,
       round((l.amount_usd - l.discount_usd) * greatest(0, least(l.period_end_exclusive, p.pe) - greatest(l.period_start, p.ps)) / (l.period_end_exclusive - l.period_start), 2) as allocated_to_period,
       (l.issue_date >= p.ps and l.issue_date < p.pe) as issued_in_period,
       (l.period_start < p.pe and l.period_end_exclusive > p.ps) as covers_period,
       (extract(day from l.period_start) = 15) as is_15th_anchor_line
from calc.actual_invoice_lines l cross join p where l.stream = 'platform';

create view calc.v_billed_platform as
select c.salesforce_account_id, c.account_name,
       coalesce(sum(b.billed_amount) filter (where b.issued_in_period), 0) as billed_invoiced_in_period,
       coalesce(sum(b.allocated_to_period) filter (where b.covers_period), 0) as billed_allocated_to_period,
       coalesce(sum(b.billed_amount) filter (where b.period_start >= (select period_end_exclusive from ref.close_params)), 0) as later_service_billed_by_cutoff,
       array_agg(b.invoice_number order by b.invoice_number) filter (where b.covers_period) as invoice_numbers_covering_period,
       array_agg(b.line_id order by b.line_id) filter (where b.covers_period) as line_ids_covering_period
from stg.customers c left join calc.v_billed_platform_lines b using (salesforce_account_id)
group by c.salesforce_account_id, c.account_name;

-- ---------- USAGE: allowance from approved versions, weighted by calendar days, rounded once half up ----------
create view calc.v_usage_allowance as
with p as (select period_start ms, period_end_exclusive me from ref.close_params),
cu as (select distinct salesforce_account_id from ref.contract_term_versions where approval_status = 'approved')
select cu.salesforce_account_id, (p.me - p.ms) as days_in_month,
       count(ver.version_id) as active_days,
       coalesce(sum(ver.included_runs_per_month), 0) as weighted_run_days,
       floor(coalesce(sum(ver.included_runs_per_month), 0)::numeric / (p.me - p.ms) + 0.5)::bigint as allowance_runs,
       coalesce(sum(ver.included_runs_per_month), 0)::numeric / (p.me - p.ms) as allowance_unrounded,
       count(distinct ver.overage_rate_per_run) as distinct_rates_in_month,
       (select v.overage_rate_per_run from ref.contract_term_versions v where v.salesforce_account_id = cu.salesforce_account_id and v.approval_status = 'approved'
          and v.effective_from <= p.me - 1 and p.me - 1 < v.effective_to_exclusive) as overage_rate_per_run,
       array_agg(distinct ver.version_id) filter (where ver.version_id is not null) as version_ids
from p cross join cu
cross join lateral generate_series(p.ms, p.me - 1, interval '1 day') as g(day_ts)
left join ref.contract_term_versions ver on ver.salesforce_account_id = cu.salesforce_account_id and ver.approval_status = 'approved'
     and ver.effective_from <= g.day_ts::date and g.day_ts::date < ver.effective_to_exclusive
group by cu.salesforce_account_id, p.ms, p.me;

-- Expected usage: max(0, units - allowance) x rate, rounded once to cents. Approved concessions reduce the NET; unapproved requests authorize nothing.
create view calc.v_expected_usage as
select c.salesforce_account_id, c.account_name, p.period_start as month_start,
       a.active_days, a.days_in_month, a.weighted_run_days, a.allowance_unrounded, a.allowance_runs,
       coalesce(v.verified_units, 0) as verified_units, v.record_count, v.product_account_ids,
       greatest(0, coalesce(v.verified_units, 0) - a.allowance_runs) as overage_units,
       a.overage_rate_per_run, (a.distinct_rates_in_month > 1) as rate_changed_in_month,
       round(greatest(0, coalesce(v.verified_units, 0) - a.allowance_runs) * a.overage_rate_per_run, 2) as expected_usage_gross,
       coalesce(ap.approved, 0) as approved_concessions,
       round(greatest(0, coalesce(v.verified_units, 0) - a.allowance_runs) * a.overage_rate_per_run, 2) - coalesce(ap.approved, 0) as expected_usage_net,
       coalesce(un.requested, 0) as unapproved_requests_not_applied,
       case when v.verified_units is null then 'no_verified_product_account_usage' else 'verified' end as attribution_status,
       (p.period_end_exclusive) as usage_invoice_due_date
from stg.customers c cross join ref.close_params p
join calc.v_usage_allowance a using (salesforce_account_id)
left join calc.verified_usage_month v on v.salesforce_account_id = c.salesforce_account_id and v.month_start = p.period_start
left join (select salesforce_account_id, applies_to_month, sum(amount) approved from ref.approvals where status = 'approved' and item = 'usage_concession' group by 1, 2) ap
       on ap.salesforce_account_id = c.salesforce_account_id and ap.applies_to_month = p.period_start
left join (select salesforce_account_id, applies_to_month, sum(amount) requested from ref.approvals where status = 'requested_unapproved' group by 1, 2) un
       on un.salesforce_account_id = c.salesforce_account_id and un.applies_to_month = p.period_start;

-- Billed usage: Stripe lines with product prod_workflow_run for the service month; ISSUED credit notes only (void have no effect).
create view calc.v_billed_usage as
with p as (select period_start ms from ref.close_params),
bl as (select l.salesforce_account_id, sum(l.amount_usd - l.discount_usd) gross, sum(l.quantity) units,
              array_agg(l.invoice_number order by l.invoice_number) invoice_numbers, array_agg(l.line_id order by l.line_id) line_ids
       from calc.actual_invoice_lines l, p where l.stream = 'usage' and date_trunc('month', l.period_start)::date = p.ms group by 1),
cr as (select cc.salesforce_account_id, sum(cc.amount_usd) issued, array_agg(cc.credit_note_id) note_ids, min(cc.created_date) first_created
       from calc.actual_issued_credits cc, p where cc.product_id = 'prod_workflow_run' and date_trunc('month', cc.service_start)::date = p.ms group by 1),
vd as (select a.account_id as salesforce_account_id, sum(cl.amount::numeric / 100) void_amount, array_agg(n.id) void_note_ids
       from raw.stripe_credit_notes n join raw.stripe_credit_note_lines cl on cl.credit_note_id = n.id
       join raw.salesforce_accounts a on a.stripe_customer_id = n.customer_id, p
       where n.status = 'void' and date_trunc('month', cl.service_start)::date = p.ms group by 1)
select c.salesforce_account_id, c.account_name, coalesce(bl.gross, 0) as billed_usage_gross, bl.units as billed_units,
       coalesce(cr.issued, 0) as credits_issued, coalesce(bl.gross, 0) - coalesce(cr.issued, 0) as billed_usage_net,
       coalesce(vd.void_amount, 0) as void_credits_ignored,
       bl.invoice_numbers, bl.line_ids, cr.note_ids as issued_credit_note_ids, cr.first_created as first_credit_date, vd.void_note_ids
from stg.customers c left join bl using (salesforce_account_id) left join cr using (salesforce_account_id) left join vd using (salesforce_account_id);

-- Every invoice line must map to exactly one stream.
create view calc.v_invoice_line_stream_check as
select stream, count(*) as lines, sum(amount_usd) as amount_usd from calc.actual_invoice_lines group by 1;

-- ---------- Expected vs billed, one row per customer, platform and usage in separate column groups ----------
create view calc.v_expected_vs_billed as
select e.salesforce_account_id, e.account_name,
       -- platform, invoice basis
       pe.expected_to_bill_for_period as platform_expected_to_bill, pb.billed_invoiced_in_period as platform_billed_in_period,
       greatest(pe.expected_to_bill_for_period - pb.billed_invoiced_in_period, 0) as platform_under_billed,
       greatest(pb.billed_invoiced_in_period - pe.expected_to_bill_for_period, 0) as platform_over_billed,
       -- platform, revenue vs allocation basis (informational; an invoice or its allocation is not automatically revenue)
       pe.expected_revenue as platform_expected_revenue, pb.billed_allocated_to_period as platform_billed_allocated_to_period,
       pe.expected_revenue - pb.billed_allocated_to_period as platform_revenue_minus_allocation,
       -- usage
       e.expected_usage_net as usage_expected_net, ub.billed_usage_net as usage_billed_net,
       greatest(e.expected_usage_net - ub.billed_usage_net, 0) as usage_under_billed,
       greatest(ub.billed_usage_net - e.expected_usage_net, 0) as usage_over_billed,
       e.attribution_status as usage_attribution_status
from calc.v_expected_usage e
join calc.v_expected_platform pe using (salesforce_account_id)
join calc.v_billed_platform pb using (salesforce_account_id)
join calc.v_billed_usage ub using (salesforce_account_id);

-- Totals, one row per stream (streams are never added together).
create view calc.v_expected_vs_billed_totals as
select 'platform (invoice basis)' as stream, count(*) as customers, sum(platform_expected_to_bill) as expected, sum(platform_billed_in_period) as billed,
       sum(platform_under_billed) as under_billed, sum(platform_over_billed) as over_billed from calc.v_expected_vs_billed
union all
select 'platform (revenue vs allocation basis)', count(*), sum(platform_expected_revenue), sum(platform_billed_allocated_to_period), null, null from calc.v_expected_vs_billed
union all
select 'usage (net of approved concessions)', count(*), sum(usage_expected_net), sum(usage_billed_net), sum(usage_under_billed), sum(usage_over_billed) from calc.v_expected_vs_billed;

do $$ declare s text; begin
  foreach s in array array['calc'] loop execute format('revoke all on all tables in schema %I from anon, authenticated', s); end loop;
end $$;
