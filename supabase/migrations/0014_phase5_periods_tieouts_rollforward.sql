-- 0014 (Phase 5, part 1): accounting periods, parameters, and tie-outs to the NetSuite files.
-- Sign convention in rollforwards: debit-positive (Dr - Cr); a credit balance is negative.

create table ref.accounting_periods (
  period text primary key, status text not null check (status in ('open','closed')), source text not null
);
insert into ref.accounting_periods values
 ('Sep 2026', 'closed', 'billing_followups.pdf MSG-2026-125: "September balances are finalized"'),
 ('Oct 2026', 'open',   'billing_followups.pdf MSG-2026-125: "October remains open for supported adjustments"'),
 ('Nov 2026', 'open',   'Current period (close in progress); no source states it closed');
alter table ref.accounting_periods enable row level security;

-- Dates used by the proposals. The issue date is a proposal parameter for the Controller to confirm (November, per MSG-2026-133).
alter table ref.close_params add column if not exists journal_date date not null default '2026-10-31',
                             add column if not exists journal_posting_period text not null default 'Oct 2026',
                             add column if not exists proposed_billing_issue_date date not null default '2026-11-12';

-- Tie-out 1: October platform recognition (Dr 2200 / Cr 4000): NetSuite GL vs revenue plan vs the engine (policy), per customer.
create view calc.v_tieout_platform_recognition as
with gl as (select customer_internal_id cust, sum(credit - debit) as gl_recognized from raw.netsuite_gl_detail where account_number = '4000' and posting_period = 'Oct 2026' group by 1),
     gl2200 as (select customer_internal_id cust, sum(debit) as dr_2200_recognition from raw.netsuite_gl_detail where account_number = '2200' and posting_period = 'Oct 2026' and memo ilike '%recognition%' group by 1),
     pl as (select customer_internal_id cust, sum(recognized_amount) as plan_recognized, sum(planned_amount) as plan_planned from raw.netsuite_revenue_plan_detail where posting_period = 'Oct 2026' group by 1)
select c.salesforce_account_id, c.account_name, c.netsuite_customer_internal_id,
       coalesce(gl.gl_recognized, 0) as gl_cr_4000, coalesce(gl2200.dr_2200_recognition, 0) as gl_dr_2200,
       coalesce(pl.plan_recognized, 0) as plan_recognized, coalesce(pl.plan_planned, 0) as plan_planned,
       e.base_revenue as expected_base, e.expected_revenue as expected_total,
       coalesce(gl.gl_recognized, 0) - coalesce(pl.plan_recognized, 0) as gl_minus_plan,
       coalesce(gl.gl_recognized, 0) - e.expected_revenue as gl_minus_expected
from stg.customers c
left join gl on gl.cust = c.netsuite_customer_internal_id left join gl2200 on gl2200.cust = c.netsuite_customer_internal_id left join pl on pl.cust = c.netsuite_customer_internal_id
join calc.v_expected_platform_revenue e using (salesforce_account_id);

-- Tie-out 2: October usage accrual (Dr 1150 / Cr 4010): NetSuite GL vs engine (expected net of approved concessions), per customer.
create view calc.v_tieout_usage_accrual as
with a as (select customer_internal_id cust, sum(credit - debit) as gl_cr_4010 from raw.netsuite_gl_detail where account_number = '4010' and posting_period = 'Oct 2026' group by 1),
     b as (select customer_internal_id cust, sum(debit - credit) as gl_dr_1150_accrual from raw.netsuite_gl_detail where account_number = '1150' and posting_period = 'Oct 2026' and transaction_type = 'Journal' group by 1)
select c.salesforce_account_id, c.account_name, c.netsuite_customer_internal_id,
       coalesce(a.gl_cr_4010, 0) as gl_cr_4010, coalesce(b.gl_dr_1150_accrual, 0) as gl_dr_1150,
       e.expected_usage_gross, e.approved_concessions, e.expected_usage_net,
       coalesce(a.gl_cr_4010, 0) - coalesce(b.gl_dr_1150_accrual, 0) as legs_difference,
       coalesce(a.gl_cr_4010, 0) - e.expected_usage_net as gl_minus_expected
from stg.customers c left join a on a.cust = c.netsuite_customer_internal_id left join b on b.cust = c.netsuite_customer_internal_id
join calc.v_expected_usage e using (salesforce_account_id);

-- Tie-out 3: opening balance + October activity = closing, accounts 1100, 1150, 1160, 2200, per customer, against the supporting sub-ledgers.
--   1100 supported = opening + Stripe invoices issued in October - issued credit notes issued in October
--   1150 supported = opening - Stripe usage invoices issued in October (they release the prior accrual) + October accrual journal
--   2200 supported = opening + Stripe platform invoices issued in October - plan recognition posted in October + contract-asset reclass
--   1160 supported = policy-required contract asset = max(0, net debit in 2200 before reclass)  (prior reclass reversed, then recalculated)
create view calc.v_rollforward as
with base as (
  select o.customer_internal_id cust, o.account_number acct, max(o.account_name) account_name, sum(o.debit_balance - o.credit_balance) as opening
  from raw.netsuite_opening_balances o group by 1, 2),
act as (select customer_internal_id cust, account_number acct, sum(debit) dr, sum(credit) cr from raw.netsuite_gl_detail where posting_period = 'Oct 2026' group by 1, 2),
sl as (
  select a.netsuite_customer_internal_id cust,
         coalesce(sum(l.amount_usd - l.discount_usd) filter (where l.stream = 'platform' and l.issue_date >= '2026-10-01' and l.issue_date < '2026-11-01'), 0) as plat_inv_oct,
         coalesce(sum(l.amount_usd - l.discount_usd) filter (where l.stream = 'usage' and l.issue_date >= '2026-10-01' and l.issue_date < '2026-11-01'), 0) as usage_inv_oct
  from stg.customers a left join calc.actual_invoice_lines l using (salesforce_account_id) group by 1),
cred as (select a.netsuite_customer_internal_id cust, coalesce(sum(c.amount_usd) filter (where c.created_date >= '2026-10-01' and c.created_date < '2026-11-01'), 0) as credits_oct
         from stg.customers a left join calc.actual_issued_credits c using (salesforce_account_id) group by 1),
plan as (select customer_internal_id cust, sum(recognized_amount) as rec from raw.netsuite_revenue_plan_detail where posting_period = 'Oct 2026' group by 1),
rcl as (select customer_internal_id cust, sum(debit) filter (where account_number = '1160') as reclass_dr, sum(credit) filter (where account_number = '2200') as reclass_cr
        from raw.netsuite_gl_detail where posting_period = 'Oct 2026' and memo ilike '%contract asset%' group by 1),
b2200 as (select cust, opening from base where acct = '2200'),
accr as (select customer_internal_id cust, sum(debit - credit) as accrual_1150 from raw.netsuite_gl_detail where posting_period = 'Oct 2026' and account_number = '1150' and transaction_type = 'Journal' group by 1)
select b.cust as netsuite_customer_internal_id, s.salesforce_account_id, s.account_name, b.acct as account_number, b.account_name as account_label,
       b.opening, coalesce(a.dr, 0) as oct_debits, coalesce(a.cr, 0) as oct_credits,
       b.opening + coalesce(a.dr, 0) - coalesce(a.cr, 0) as closing_gl,
       case b.acct
         when '1100' then b.opening + sl.plat_inv_oct + sl.usage_inv_oct - cred.credits_oct
         when '1150' then b.opening - sl.usage_inv_oct + coalesce(accr.accrual_1150, 0)
         when '2200' then b.opening - sl.plat_inv_oct + coalesce(plan.rec, 0) + 0 - coalesce(rcl.reclass_cr, 0)
         when '1160' then greatest(0, b2200.opening - sl.plat_inv_oct + coalesce(plan.rec, 0)) end as supported_closing,
       (b.opening + coalesce(a.dr, 0) - coalesce(a.cr, 0)) -
       case b.acct
         when '1100' then b.opening + sl.plat_inv_oct + sl.usage_inv_oct - cred.credits_oct
         when '1150' then b.opening - sl.usage_inv_oct + coalesce(accr.accrual_1150, 0)
         when '2200' then b.opening - sl.plat_inv_oct + coalesce(plan.rec, 0) - coalesce(rcl.reclass_cr, 0)
         when '1160' then greatest(0, b2200.opening - sl.plat_inv_oct + coalesce(plan.rec, 0)) end as tie_difference
from base b
join stg.customers s on s.netsuite_customer_internal_id = b.cust
left join act a on a.cust = b.cust and a.acct = b.acct
left join sl on sl.cust = b.cust left join cred on cred.cust = b.cust left join plan on plan.cust = b.cust left join rcl on rcl.cust = b.cust
left join b2200 on b2200.cust = b.cust left join accr on accr.cust = b.cust;

revoke all on all tables in schema calc from anon, authenticated;
revoke all on all tables in schema ref from anon, authenticated;
