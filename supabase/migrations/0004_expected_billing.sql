-- 0004: expected billing from contract terms. SQL computes every number; platform and usage stay separate.

-- Allowance schedule: base order form + amendments that change included_runs_per_month.
create view calc.allowance_schedule as
select r.salesforce_account_id, t.document_id as source_document_id, t.service_start as effective_from,
       t.included_runs_per_month as runs
from ref.contract_terms t join raw.contract_register r using (document_id)
union all
select r.salesforce_account_id, a.amendment_document_id, a.effective_from, a.numeric_value::int
from ref.contract_amendment_terms a join raw.contract_register r on r.document_id = a.amendment_document_id
where a.term = 'included_runs_per_month';

create view calc.months as
select m::date as month_start, (m + interval '1 month')::date as month_end_exclusive,
       ((m + interval '1 month')::date - m::date) as days_in_month
from generate_series('2026-09-01'::date, '2026-10-01'::date, interval '1 month') m;

-- Allowance per customer-month: sum(daily allowance over ACTIVE days) / days_in_month, rounded once half up.
-- Covers partial first month (x active days / days) and amendment weighting (prior x days + new x days) / days.
create view calc.customer_month_allowance as
select r.salesforce_account_id, t.document_id as contract_document_id, mo.month_start, mo.days_in_month,
       count(d.day) filter (where d.day >= t.service_start and d.day < t.service_end_exclusive) as active_days,
       coalesce(sum(s.runs) filter (where d.day >= t.service_start and d.day < t.service_end_exclusive), 0) as weighted_run_days,
       floor(coalesce(sum(s.runs) filter (where d.day >= t.service_start and d.day < t.service_end_exclusive), 0)::numeric
             / mo.days_in_month + 0.5)::bigint as allowance_runs,
       t.included_runs_per_month as base_allowance, t.overage_rate_per_run
from ref.contract_terms t
join raw.contract_register r using (document_id)
cross join calc.months mo
cross join lateral generate_series(mo.month_start, mo.month_end_exclusive - 1, interval '1 day') as g(day_ts)
cross join lateral (select g.day_ts::date as day) d
left join lateral (
  select sc.runs from calc.allowance_schedule sc
  where sc.salesforce_account_id = r.salesforce_account_id and sc.effective_from <= d.day
  order by sc.effective_from desc limit 1) s on true
group by r.salesforce_account_id, t.document_id, mo.month_start, mo.days_in_month, t.included_runs_per_month, t.overage_rate_per_run;

-- Verified usage per customer-month (aggregate across the customer's verified product accounts first).
create view calc.verified_usage_month as
select salesforce_account_id, date_trunc('month', service_date)::date as month_start,
       sum(units) as verified_units, count(*) as record_count,
       count(distinct product_account_id) as product_accounts,
       array_agg(distinct product_account_id order by product_account_id) as product_account_ids
from stg.usage_verified group by 1, 2;

-- Expected usage billing: max(0, units - allowance) x rate, rounded once to cents half up.
create view calc.expected_usage_billing as
select a.salesforce_account_id, c.account_name, a.contract_document_id, a.month_start,
       a.active_days, a.days_in_month, a.weighted_run_days, a.allowance_runs,
       coalesce(v.verified_units, 0) as verified_units, v.record_count, v.product_account_ids,
       greatest(0, coalesce(v.verified_units, 0) - a.allowance_runs) as overage_units,
       a.overage_rate_per_run,
       round(greatest(0, coalesce(v.verified_units, 0) - a.allowance_runs) * a.overage_rate_per_run, 2) as expected_usage_charge,
       (a.month_start + interval '1 month')::date as usage_invoice_date,
       case when v.verified_units is null then 'no_verified_product_account_usage' else 'verified' end as attribution_status
from calc.customer_month_allowance a
join stg.customers c using (salesforce_account_id)
left join calc.verified_usage_month v using (salesforce_account_id, month_start)
where a.active_days > 0;

-- Expected platform charges (advance billing). Annual: one invoice on service start. Monthly: on the anchor day each month.
-- Includes invoices issued by cutoff only. Meridian's upgrade catch-up is a separate additional October-service charge.
create view calc.expected_platform_charges as
with base as (
  select r.salesforce_account_id, t.document_id, t.billing_frequency, t.billing_anchor_day, t.service_start,
         t.service_end_exclusive, t.platform_fee, t.annual_platform_commitment
  from ref.contract_terms t join raw.contract_register r using (document_id)
), sched as (
  select b.*, (b.service_start + (n || ' month')::interval)::date as invoice_date
  from base b cross join generate_series(0, 14) n
  where b.billing_frequency = 'monthly'
  union all
  select b.*, b.service_start from base b where b.billing_frequency = 'annual'
), lines as (
  select s.salesforce_account_id, s.document_id, s.invoice_date,
         s.invoice_date as period_start,
         case when s.billing_frequency = 'annual' then s.service_end_exclusive
              else (s.invoice_date + interval '1 month')::date end as period_end_exclusive,
         coalesce((select a.numeric_value from ref.contract_amendment_terms a
                   join raw.contract_register ar on ar.document_id = a.amendment_document_id
                   where ar.salesforce_account_id = s.salesforce_account_id
                     and a.term = 'monthly_platform_invoice' and a.effective_from <= s.invoice_date
                     and a.new_value like '%from%'                 -- only amendments that reprice the invoice
                   order by a.effective_from desc limit 1), s.platform_fee) as expected_amount,
         'platform_advance'::text as charge_kind
  from sched s
  where s.invoice_date >= s.service_start and s.invoice_date < s.service_end_exclusive
    and s.invoice_date <= (select cutoff from ref.close_params)::date
)
select * from lines
union all
-- Upgrade catch-up: contract states USD 12,000 x 16 / 365 -> 526.03. Recomputed here and checked against the stated amount.
select r.salesforce_account_id, a.amendment_document_id, null::date, a.effective_from, '2026-11-01'::date,
       a.numeric_value, 'upgrade_catch_up'
from ref.contract_amendment_terms a join raw.contract_register r on r.document_id = a.amendment_document_id
where a.term = 'october_upgrade_catch_up';

create view calc.upgrade_catch_up_check as
select a.amendment_document_id, a.numeric_value as stated_amount,
       round(((60000 - 48000)::numeric * (date '2026-11-01' - a.effective_from) / 365), 2) as recomputed_amount
from ref.contract_amendment_terms a where a.term = 'october_upgrade_catch_up';

-- Unverified usage: isolated. Hypothetical exposure is shown only as "IF owned by customer C"; never assigned.
create view calc.unverified_usage_month as
select product_account_id, date_trunc('month', service_date)::date as month_start,
       sum(units) as unverified_units, count(*) as record_count,
       array_agg(record_id order by service_date) as record_ids
from stg.usage_unverified group by 1, 2;

create view calc.unverified_conditional_exposure as
select u.product_account_id, u.month_start, u.unverified_units, e.salesforce_account_id as if_owned_by, e.account_name,
       e.verified_units as customer_mapped_units, e.allowance_runs,
       round(greatest(0, e.verified_units + u.unverified_units - e.allowance_runs) * e.overage_rate_per_run, 2)
       - e.expected_usage_charge as incremental_charge_if_owned
from calc.unverified_usage_month u
join calc.expected_usage_billing e using (month_start);

do $$ declare s text; begin
  foreach s in array array['stg','calc','ref'] loop
    execute format('revoke all on all tables in schema %I from anon, authenticated', s);
  end loop;
end $$;
