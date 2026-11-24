-- 0008 (Phase 1): identifier crosswalk and canonical usage views.
-- raw.* tables are already typed (dates, numeric units) from 0001, so no second typed copy is made; the v_* views below
-- are the canonical layer and sit on the existing stg.usage_deduped / usage_verified / usage_unverified views.

-- One row per customer (Salesforce account). Product accounts are verified mappings only; flags show any missing identifier.
create view stg.v_customer_crosswalk as
with docs as (
  select salesforce_account_id,
         array_agg(contract_id order by document_id) filter (where document_type = 'order_form') as contract_ids,
         array_agg(document_id order by document_id) as contract_document_ids,
         count(*) filter (where document_type = 'order_form') as order_forms,
         count(*) filter (where document_type = 'amendment') as amendments
  from raw.contract_register group by 1
), pa as (
  select salesforce_account_id, array_agg(product_account_id order by product_account_id) as product_account_ids,
         count(*) as product_account_count
  from raw.product_account_mapping where salesforce_account_id is not null group by 1
)
select a.account_id as salesforce_account_id, a.account_name, a.stripe_customer_id, a.netsuite_customer_internal_id,
       d.contract_ids, d.contract_document_ids, d.order_forms, d.amendments,
       coalesce(pa.product_account_ids, '{}') as product_account_ids, coalesce(pa.product_account_count, 0) as product_account_count,
       (a.stripe_customer_id is null)                                             as missing_stripe_id,
       (a.netsuite_customer_internal_id is null)                                  as missing_netsuite_id,
       (pa.product_account_count is null)                                         as missing_product_account,
       (d.order_forms is null)                                                    as missing_contract,
       (a.stripe_customer_id is not null and not exists (select 1 from raw.stripe_invoices i where i.customer_id = a.stripe_customer_id)) as stripe_id_not_in_invoices,
       (a.netsuite_customer_internal_id is not null and not exists (select 1 from raw.netsuite_opening_balances o where o.customer_internal_id = a.netsuite_customer_internal_id)) as netsuite_id_not_in_opening_balances,
       (a.stripe_customer_id is null or a.netsuite_customer_internal_id is null or pa.product_account_count is null or d.order_forms is null) as any_identifier_missing
from raw.salesforce_accounts a left join docs d on d.salesforce_account_id = a.account_id left join pa on pa.salesforce_account_id = a.account_id;

-- Product accounts with no verified customer (never assigned by elimination).
create view stg.v_unmapped_product_accounts as
select m.product_account_id, m.account_label, m.effective_from, m.mapping_updated_at
from raw.product_account_mapping m where m.salesforce_account_id is null;

-- Canonical usage: active records deduplicated on record_id (exact repeats are not new activity), all attributions.
create view stg.v_usage_clean as select * from stg.usage_deduped;

-- Unverified usage, isolated. Never assigned to a customer.
create view stg.v_usage_unassigned as select * from stg.usage_unverified;

-- Per customer per day, aggregated across ALL of the customer's verified product accounts (daily records are additive).
create view stg.v_usage_by_customer_day as
select salesforce_account_id, service_date, sum(units) as units, count(*) as records,
       array_agg(product_account_id order by product_account_id) as product_account_ids
from stg.usage_verified group by 1, 2;

create view stg.v_usage_by_customer_month as
select c.salesforce_account_id, c.account_name, mo.month_start, v.verified_units, v.record_count, v.product_accounts, v.product_account_ids
from stg.customers c cross join calc.months mo
left join calc.verified_usage_month v on v.salesforce_account_id = c.salesforce_account_id and v.month_start = mo.month_start;

-- Per batch (= service date): physical rows -> clean records -> controls, with differences and an explanation.
create view stg.v_usage_batch_reconciliation as
with phys as (select service_date, count(*) as physical_rows, sum(units) as physical_units from raw.product_usage group by 1),
     cl as (select service_date, count(*) as clean_records, sum(units) as clean_units,
                   count(*) filter (where attribution = 'verified') as verified_records, sum(units) filter (where attribution = 'verified') as verified_units,
                   count(*) filter (where attribution = 'unverified') as unassigned_records, coalesce(sum(units) filter (where attribution = 'unverified'), 0) as unassigned_units
            from stg.v_usage_clean group by 1)
select c.service_date, c.batch_id, p.physical_rows, cl.clean_records, c.distinct_active_record_count as control_records,
       cl.clean_records - c.distinct_active_record_count as record_diff,
       p.physical_units, cl.clean_units, c.active_units_total as control_units, cl.clean_units - c.active_units_total as unit_diff,
       p.physical_rows - c.distinct_active_record_count as physical_vs_control_rows,
       cl.verified_records, cl.verified_units, cl.unassigned_records, cl.unassigned_units,
       case when cl.clean_records = c.distinct_active_record_count and cl.clean_units = c.active_units_total
              then case when p.physical_rows <> c.distinct_active_record_count
                        then 'explained: physical export has ' || (p.physical_rows - c.distinct_active_record_count) || ' exact repeated record_id row(s); clean matches control'
                        else 'match' end
            else 'OPEN ITEM: clean differs from control' end as status
from raw.usage_batch_controls c left join phys p using (service_date) left join cl using (service_date);

revoke all on all tables in schema stg from anon, authenticated;
