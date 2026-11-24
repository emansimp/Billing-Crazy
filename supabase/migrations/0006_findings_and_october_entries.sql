-- 0006: findings + proposed October journal entries. All amounts come from SQL views; text is only a label.
-- Billing correction (Nov-dated supplemental invoice / credit note) is decided separately from an October
-- accounting adjustment (posted in Oct 2026) - the second exists only where the Oct accrual/recognition differs from contract support.

-- Oct usage: contract-expected net revenue vs what NetSuite accrued (4010 credits in Oct 2026).
create view calc.usage_accrual_comparison as
select c.salesforce_account_id, c.account_name, s.netsuite_customer_internal_id, c.month_start, c.expected_net,
       coalesce(g.accrued, 0) as gl_accrued, c.expected_net - coalesce(g.accrued, 0) as accrual_adjustment_needed
from calc.usage_billing_comparison c
join raw.salesforce_accounts s on s.account_id = c.salesforce_account_id
left join (select customer_internal_id, sum(credit - debit) as accrued from raw.netsuite_gl_detail
           where account_number = '4010' and posting_period = 'Oct 2026' group by 1) g on g.customer_internal_id = s.netsuite_customer_internal_id
where c.month_start = '2026-10-01';

create view calc.usage_findings as
select c.salesforce_account_id, c.account_name, c.month_start,
       case when c.under_billed > 0 then 'under_billed' else 'over_billed' end as direction,
       greatest(c.under_billed, c.over_billed) as billing_difference,
       case when c.billed_gross = 0 then 'no_usage_invoice_issued'
            when a.allowance_runs <> a.base_allowance and c.billed_units = c.verified_units - a.base_allowance then 'amended_allowance_not_applied'
            when c.billed_units <> c.expected_overage_units then 'billed_quantity_differs_from_metered_overage'
            when br.rate is distinct from c.overage_rate_per_run * 100 then 'billed_rate_differs_from_contract'
            else 'other' end as diagnosis,
       c.expected_overage_units, c.billed_units, c.overage_rate_per_run * 100 as contract_rate_cents, br.rate as billed_rate_cents,
       q.accrual_adjustment_needed,
       case when q.accrual_adjustment_needed = 0 then 'billing correction only - October accrual already matches contract' else 'billing correction AND October accounting adjustment' end as action,
       c.invoice_numbers, c.line_ids
from calc.usage_billing_comparison c
join calc.customer_month_allowance a on a.salesforce_account_id = c.salesforce_account_id and a.month_start = c.month_start
join calc.usage_accrual_comparison q on q.salesforce_account_id = c.salesforce_account_id and q.month_start = c.month_start
left join lateral (select min(l.unit_amount_decimal) as rate from calc.actual_invoice_lines l where l.line_id = any(c.line_ids)) br on true
where c.month_start = '2026-10-01' and (c.under_billed <> 0 or c.over_billed <> 0);

-- Platform recognition for October: base schedule preserved, upgrade increment added (days/365, rounded once to cents).
create view calc.platform_recognition_oct as
with base as (
  select r.salesforce_account_id, s.netsuite_customer_internal_id cust,
         round(t.annual_platform_commitment * (least(date '2026-11-01', t.service_end_exclusive) - greatest(date '2026-10-01', t.service_start)) / 365.0, 2) as expected_base
  from ref.contract_terms t join raw.contract_register r using (document_id)
  join raw.salesforce_accounts s on s.account_id = r.salesforce_account_id
), inc as (
  select salesforce_account_id, recomputed_amount as expected_increment
  from calc.upgrade_catch_up_check u join raw.contract_register r on r.document_id = u.amendment_document_id
), gl as (
  select customer_internal_id cust, sum(credit - debit) as gl_oct_recognition
  from raw.netsuite_gl_detail where account_number = '4000' and posting_period = 'Oct 2026' group by 1
)
select b.salesforce_account_id, b.cust as netsuite_customer_internal_id, b.expected_base, coalesce(i.expected_increment, 0) as expected_increment,
       b.expected_base + coalesce(i.expected_increment, 0) as expected_total, coalesce(g.gl_oct_recognition, 0) as gl_recognized,
       b.expected_base + coalesce(i.expected_increment, 0) - coalesce(g.gl_oct_recognition, 0) as recognition_adjustment_needed
from base b left join inc i using (salesforce_account_id) left join gl g using (cust);

-- Proposed October entries (posting period Oct 2026). Proposals only; nothing is posted.
create view calc.proposed_october_entries as
with usage_adj as (
  select netsuite_customer_internal_id cust, salesforce_account_id sf, accrual_adjustment_needed d
  from calc.usage_accrual_comparison where accrual_adjustment_needed <> 0
), recog as (
  select netsuite_customer_internal_id cust, salesforce_account_id sf, recognition_adjustment_needed d
  from calc.platform_recognition_oct where recognition_adjustment_needed <> 0
), bal as (
  select o.customer_internal_id cust,
         sum(case when o.account_number = '2200' then o.credit_balance - o.debit_balance end) ob2200,
         sum(case when o.account_number = '1160' then o.debit_balance - o.credit_balance end) ob1160
  from raw.netsuite_opening_balances o group by 1
), glb as (
  select customer_internal_id cust,
         sum(case when account_number = '2200' and memo not ilike '%contract asset%' and posting_period = 'Oct 2026' then credit - debit else 0 end) oct2200_ex_reclass,
         sum(case when account_number = '1160' and posting_period = 'Oct 2026' then debit - credit else 0 end) oct1160
  from raw.netsuite_gl_detail group by 1
), reclass as (
  select b.cust, s.account_id sf,
         greatest(0, -(b.ob2200 + g.oct2200_ex_reclass - coalesce(r.d, 0))) - (b.ob1160 + g.oct1160) as d
  from bal b join glb g using (cust) join raw.salesforce_accounts s on s.netsuite_customer_internal_id = b.cust
  left join recog r on r.cust = b.cust
), legs as (
  select 'USAGE-ACCRUAL' k, cust, sf, case when d > 0 then '1150' else '4010' end acct_dr, case when d > 0 then '4010' else '1150' end acct_cr, abs(d) amt,
         'Correct October usage accrual to contract-supported amount' memo from usage_adj
  union all select 'PLATFORM-RECOG', cust, sf, '2200', '4000', d, 'October upgrade increment recognition (base schedule unchanged)' from recog where d > 0
  union all select 'PLATFORM-RECLASS', cust, sf, case when d > 0 then '1160' else '2200' end, case when d > 0 then '2200' else '1160' end, abs(d),
         'Incremental platform contract asset reclass after corrected recognition' from reclass where d <> 0
)
select l.k || '-' || l.cust as entry_key, 'Oct 2026'::text as posting_period, l.sf as salesforce_account_id, l.cust as netsuite_customer_internal_id,
       x.account_number, x.debit, x.credit, l.memo
from legs l cross join lateral (values (l.acct_dr, l.amt, 0::numeric), (l.acct_cr, 0::numeric, l.amt)) as x(account_number, debit, credit);

do $$ declare s text; begin
  foreach s in array array['calc','ref'] loop
    execute format('revoke all on all tables in schema %I from anon, authenticated', s);
  end loop;
end $$;
