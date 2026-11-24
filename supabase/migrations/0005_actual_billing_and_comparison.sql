-- 0005: actual Stripe billing + expected-vs-actual comparison. Platform and usage stay separate;
-- under-billing and over-billing are separate columns. Void credit notes have no effect.

create table ref.approvals (
  msg_id text primary key,
  salesforce_account_id text,
  item text not null,
  amount numeric(14,2),
  status text not null check (status in ('approved','requested_unapproved','info')),
  applies_to_month date,
  evidence text not null
);
insert into ref.approvals (msg_id, salesforce_account_id, item, amount, status, applies_to_month, evidence)
select 'MSG-2026-109', (select account_id from raw.salesforce_accounts where account_name like 'Zephyr Grove%'), 'usage_concession', 100.00, 'approved', date '2026-10-01',
  'Priya Shah (Controller), billing_followups.pdf p1: "Approved: reduce Zephyr Grove October usage consideration by USD 100... ensure the October accrual is already net of this approved concession. Do not apply a second concession."'
union all select 'MSG-2026-108', (select account_id from raw.salesforce_accounts where account_name like 'Zephyr Grove%'), 'usage_concession_request', 100.00, 'info', date '2026-10-01',
  'Morgan Lee request; superseded by MSG-2026-109 approval (same $100, not additive).'
union all select 'MSG-2026-132', (select account_id from raw.salesforce_accounts where account_name like 'Willow Passage%'), 'usage_concession_request', 250.00, 'requested_unapproved', date '2026-10-01',
  'Morgan Lee, billing_followups.pdf p2: request only; no Controller approval; does not establish ownership of any unverified workspace.'
union all select 'MSG-2026-116', (select account_id from raw.salesforce_accounts where account_name like 'Alder Fieldworks%'), 'credit_note_voided', 50.00, 'info', date '2026-10-01',
  'Alex Chen: cn_82a7ddd6e88e69 created in error and voided; no credit or reversal posted. Void status governs; no effect.';

create view calc.actual_invoice_lines as
select a.account_id as salesforce_account_id, i.id as invoice_id, i.number as invoice_number,
       (i.created at time zone 'America/Denver')::date as issue_date, i.status as invoice_status,
       l.id as line_id, l.product_id,
       case l.product_id when 'prod_platform' then 'platform' when 'prod_workflow_run' then 'usage' else 'other' end as stream,
       l.quantity, l.unit_amount_decimal,
       (l.amount::numeric / 100) as amount_usd, (l.discount_amount::numeric / 100) as discount_usd,
       (l.period_start at time zone 'America/Denver')::date as period_start,
       (l.period_end at time zone 'America/Denver')::date as period_end_exclusive
from raw.stripe_invoice_lines l
join raw.stripe_invoices i on i.id = l.invoice_id
join raw.salesforce_accounts a on a.stripe_customer_id = i.customer_id
where i.created <= (select cutoff from ref.close_params);

create view calc.actual_issued_credits as
select a.account_id as salesforce_account_id, n.id as credit_note_id, n.number, n.created::date as created_date,
       cl.invoice_line_item_id, il.product_id, (cl.amount::numeric / 100) as amount_usd,
       cl.service_start, cl.service_end_exclusive, n.invoice_id
from raw.stripe_credit_notes n
join raw.stripe_credit_note_lines cl on cl.credit_note_id = n.id
join raw.stripe_invoice_lines il on il.id = cl.invoice_line_item_id
join raw.salesforce_accounts a on a.stripe_customer_id = n.customer_id
where n.status = 'issued' and n.created <= (select cutoff from ref.close_params);

-- USAGE: expected (contract x verified usage, net of Controller-approved concessions) vs billed (invoice lines net of issued credits).
create view calc.usage_billing_comparison as
with billed as (
  select salesforce_account_id, date_trunc('month', period_start)::date as month_start,
         sum(amount_usd) as billed_gross, array_agg(invoice_number order by invoice_number) as invoice_numbers,
         array_agg(line_id order by line_id) as line_ids, sum(quantity) as billed_units, min(unit_amount_decimal) as billed_rate_cents
  from calc.actual_invoice_lines where stream = 'usage' group by 1, 2
), cred as (
  select salesforce_account_id, date_trunc('month', service_start)::date as month_start, sum(amount_usd) as credits_issued,
         array_agg(credit_note_id) as credit_note_ids
  from calc.actual_issued_credits where product_id = 'prod_workflow_run' group by 1, 2
), appr as (
  select salesforce_account_id, applies_to_month as month_start, sum(amount) as approved_concessions, array_agg(msg_id) as approval_ids
  from ref.approvals where status = 'approved' and item = 'usage_concession' group by 1, 2
)
select e.salesforce_account_id, e.account_name, e.month_start,
       e.verified_units, e.allowance_runs, e.overage_units as expected_overage_units, e.overage_rate_per_run,
       e.expected_usage_charge, coalesce(ap.approved_concessions, 0) as approved_concessions,
       e.expected_usage_charge - coalesce(ap.approved_concessions, 0) as expected_net,
       coalesce(b.billed_gross, 0) as billed_gross, b.billed_units, coalesce(c.credits_issued, 0) as credits_issued,
       coalesce(b.billed_gross, 0) - coalesce(c.credits_issued, 0) as billed_net,
       (coalesce(b.billed_gross, 0) - coalesce(c.credits_issued, 0)) - (e.expected_usage_charge - coalesce(ap.approved_concessions, 0)) as difference,
       greatest((e.expected_usage_charge - coalesce(ap.approved_concessions, 0)) - (coalesce(b.billed_gross, 0) - coalesce(c.credits_issued, 0)), 0) as under_billed,
       greatest((coalesce(b.billed_gross, 0) - coalesce(c.credits_issued, 0)) - (e.expected_usage_charge - coalesce(ap.approved_concessions, 0)), 0) as over_billed,
       b.invoice_numbers, b.line_ids, c.credit_note_ids, ap.approval_ids, e.attribution_status
from calc.expected_usage_billing e
left join billed b using (salesforce_account_id, month_start)
left join cred c using (salesforce_account_id, month_start)
left join appr ap using (salesforce_account_id, month_start);

-- PLATFORM: expected advance invoices (and the Meridian catch-up) vs Stripe platform lines, matched on customer + period start.
create view calc.platform_billing_comparison as
with exp as (
  select salesforce_account_id, charge_kind, period_start, period_end_exclusive, expected_amount, document_id from calc.expected_platform_charges
), act as (
  select salesforce_account_id, period_start, period_end_exclusive, sum(amount_usd) as billed_amount, array_agg(invoice_number) as invoice_numbers,
         array_agg(line_id) as line_ids, min(issue_date) as issue_date
  from calc.actual_invoice_lines where stream = 'platform' group by 1, 2, 3
)
select coalesce(e.salesforce_account_id, a.salesforce_account_id) as salesforce_account_id,
       coalesce(e.charge_kind, 'billed_not_expected') as charge_kind,
       coalesce(e.period_start, a.period_start) as period_start,
       coalesce(e.period_end_exclusive, a.period_end_exclusive) as period_end_exclusive,
       case when coalesce(e.period_start, a.period_start) < (select period_end_exclusive from ref.close_params)
             and coalesce(e.period_end_exclusive, a.period_end_exclusive) > (select period_start from ref.close_params)
            then 'covers_october' when coalesce(e.period_start, a.period_start) >= (select period_end_exclusive from ref.close_params)
            then 'later_service' else 'prior_service' end as october_relevance,
       e.expected_amount, a.billed_amount, a.issue_date, a.invoice_numbers, a.line_ids,
       greatest(coalesce(e.expected_amount, 0) - coalesce(a.billed_amount, 0), 0) as under_billed,
       greatest(coalesce(a.billed_amount, 0) - coalesce(e.expected_amount, 0), 0) as over_billed
from exp e full outer join act a
  on a.salesforce_account_id = e.salesforce_account_id and a.period_start = e.period_start and e.charge_kind = 'platform_advance';

do $$ declare s text; begin
  foreach s in array array['calc','ref'] loop
    execute format('revoke all on all tables in schema %I from anon, authenticated', s);
  end loop;
end $$;
alter table ref.approvals enable row level security;
