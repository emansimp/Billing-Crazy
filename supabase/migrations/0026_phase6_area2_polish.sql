-- 0026: journal descriptions in the mockup's wording for the customer accounting trail (display text only).
create or replace view public.ui_customer_gl_trail_live as
select s.salesforce_account_id, g.internal_id as journal, min(g.txn_date) as posting_date, min(g.created_at at time zone 'America/Denver')::date as created,
       case coalesce(max(g.memo) filter (where g.account_number <> '1100'), max(g.memo))
         when 'Platform billing' then 'Platform invoice'
         when 'Release prior service-month usage accrual' then 'Usage invoice'
         when 'October base platform recognition' then 'Platform recognition'
         when 'October usage accrual' then 'October usage accrual'
         when 'Period-end platform contract asset presentation' then 'Contract asset reclass'
         else coalesce(max(g.memo) filter (where g.account_number <> '1100'), max(g.memo)) end
       || ': Dr ' || string_agg(distinct g.account_number, '/') filter (where g.debit > 0) || ' / Cr ' || string_agg(distinct g.account_number, '/') filter (where g.credit > 0)
       || case when coalesce(max(g.memo) filter (where g.account_number <> '1100'), max(g.memo)) = 'Release prior service-month usage accrual' then ', releases the prior-month accrual' else '' end as entry,
       sum(g.debit) as amount
from raw.netsuite_gl_detail g join stg.customers s on s.netsuite_customer_internal_id = g.customer_internal_id
where g.posting_period = 'Oct 2026' group by 1, 2;
refresh materialized view public.ui_customer_gl_trail;
