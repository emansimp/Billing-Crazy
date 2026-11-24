-- 0003: run parameters + staging views (dedup, attribution). No business pricing logic here.
create table ref.close_params (
  id boolean primary key default true check (id),         -- single-row table
  period_start date not null,                              -- inclusive
  period_end_exclusive date not null,
  cutoff timestamptz not null,                             -- evidence cutoff (America/Denver)
  source text not null
);
insert into ref.close_params values (true, '2026-10-01', '2026-11-01', '2026-11-11T18:00:00-07:00',
  'START_HERE.pdf p1: October 1-31, 2026 service; close cutoff 2026-11-11T18:00:00-07:00');

create schema if not exists stg;
create schema if not exists calc;

-- Every source usage row with dedup + attribution status. record_id is the dedup key (START_HERE p2-3).
create view stg.usage_deduped as
with ranked as (
  select u.*, row_number() over (partition by u.record_id order by u.src_row) as rn
  from raw.product_usage u
)
select r.src_row, r.record_id, r.product_account_id, r.sku, r.service_date, r.units, r.ingested_at,
       r.record_status, r.replaces_record_id, r.batch_id,
       (r.rn > 1) as is_exact_duplicate,
       m.salesforce_account_id,
       case when m.salesforce_account_id is not null then 'verified' else 'unverified' end as attribution
from ranked r
left join raw.product_account_mapping m
  on m.product_account_id = r.product_account_id
 and r.service_date >= m.effective_from
 and (m.effective_to is null or r.service_date < m.effective_to)   -- effective_to treated as exclusive; all blank in this release
where r.rn = 1
  and r.record_status = 'active'
  and r.ingested_at <= (select cutoff from ref.close_params);

create view stg.usage_verified   as select * from stg.usage_deduped where attribution = 'verified';
create view stg.usage_unverified as select * from stg.usage_deduped where attribution = 'unverified';

-- Per-date control reconciliation: counts and units AFTER dedup, BEFORE dropping unmatched accounts.
create view stg.usage_control_reconciliation as
with phys as (select service_date, count(*) physical_rows from raw.product_usage group by 1),
     ded  as (select service_date, count(*) distinct_active_records, sum(units) active_units from stg.usage_deduped group by 1)
select c.service_date, c.batch_id, p.physical_rows, d.distinct_active_records, c.distinct_active_record_count as control_records,
       d.active_units, c.active_units_total as control_units,
       d.distinct_active_records - c.distinct_active_record_count as record_diff,
       d.active_units - c.active_units_total as unit_diff
from raw.usage_batch_controls c
left join phys p using (service_date) left join ded d using (service_date);

create view stg.customers as
select a.account_id as salesforce_account_id, a.account_name, a.stripe_customer_id, a.netsuite_customer_internal_id
from raw.salesforce_accounts a;

do $$ declare s text; begin
  foreach s in array array['stg','calc','ref'] loop
    execute format('revoke all on schema %I from anon, authenticated', s);
    execute format('revoke all on all tables in schema %I from anon, authenticated', s);
  end loop;
end $$;
alter table ref.close_params enable row level security;
