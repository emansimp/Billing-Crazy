-- 0009 (Phase 2): versioned contract terms. One row per customer per version (original order form, then one row per amendment).
-- Built from the PDF extraction in 0002 (ref.contract_terms / ref.contract_amendment_terms) plus executed date / payment terms read from each PDF.
-- Nothing is guessed: cross-checks against contract_register.csv and arithmetic decide status; failures become needs_info with the quote.
create table ref.contract_doc_extras (
  document_id text primary key, executed_date date not null, payment_terms text, currency text
);
insert into ref.contract_doc_extras values
('AM-OF-2026-157','2026-10-14',NULL,NULL),
('AM-OF-2026-164','2026-10-14',NULL,NULL),
('OF-2026-118','2026-08-25','Net 30','USD'),
('OF-2026-122','2026-08-25','Net 30','USD'),
('OF-2026-133','2026-08-25','Net 30','USD'),
('OF-2026-144','2026-08-25','Net 30','USD'),
('OF-2026-155','2026-08-25','Net 30','USD'),
('OF-2026-157','2026-08-25','Net 30','USD'),
('OF-2026-164','2026-08-25','Net 30','USD'),
('OF-2026-166','2026-08-25','Net 30','USD'),
('OF-2026-177','2026-08-25','Net 30','USD'),
('OF-2026-188','2026-08-25','Net 30','USD'),
('OF-2026-199','2026-08-25','Net 30','USD'),
('OF-2026-210','2026-08-25','Net 30','USD'),
('OF-2026-221','2026-08-25','Net 30','USD'),
('OF-2026-232','2026-08-25','Net 30','USD'),
('OF-2026-243','2026-08-25','Net 30','USD'),
('OF-2026-254','2026-08-25','Net 30','USD'),
('OF-2026-265','2026-08-25','Net 30','USD'),
('OF-2026-276','2026-08-25','Net 30','USD'),
('OF-2026-287','2026-08-25','Net 30','USD'),
('OF-2026-298','2026-08-25','Net 30','USD'),
('OF-2026-309','2026-08-25','Net 30','USD'),
('OF-2026-320','2026-08-25','Net 30','USD'),
('OF-2026-331','2026-08-25','Net 30','USD'),
('OF-2026-342','2026-08-25','Net 30','USD'),
('OF-2026-375','2026-08-25','Net 30','USD'),
('OF-2026-386','2026-08-25','Net 30','USD'),
('OF-2026-397','2026-08-25','Net 30','USD'),
('OF-2026-408','2026-08-25','Net 30','USD'),
('OF-2026-419','2026-08-25','Net 30','USD'),
('OF-2026-430','2026-08-25','Net 30','USD');

create table ref.contract_term_versions (
  version_id text primary key,
  salesforce_account_id text not null,
  customer_name text not null,
  contract_id text not null,
  source_document_id text not null,
  base_document_id text not null,
  version_no integer not null,
  version_type text not null check (version_type in ('original','amendment')),
  effective_from date not null,
  effective_to_exclusive date not null,          -- start-inclusive / end-exclusive, like all normalized service intervals
  term_start date not null,
  term_end_exclusive date not null,
  billing_frequency text not null check (billing_frequency in ('annual','monthly')),
  billing_anchor_day smallint not null,
  platform_fee_annual numeric(14,2) not null,
  platform_billing_amount numeric(14,2) not null,  -- amount per platform invoice under this version
  platform_billing_basis text not null,
  included_runs_per_month integer not null,
  overage_rate_per_run numeric(10,4) not null,
  invoice_discounts numeric(14,2) not null default 0,
  payment_terms text, currency text, executed_date date,
  changed_terms text[] not null default '{}',
  source_citation text not null,
  evidence jsonb not null,
  confidence text not null default 'pending',
  status text not null default 'pending' check (status in ('pending','extracted','needs_info')),
  needs_info_reason text,
  approval_status text not null default 'pending_review' check (approval_status in ('pending_review','approved','rejected')),
  approved_by text, approved_at timestamptz
);

-- v1: original order forms.
insert into ref.contract_term_versions (version_id, salesforce_account_id, customer_name, contract_id, source_document_id, base_document_id, version_no, version_type,
  effective_from, effective_to_exclusive, term_start, term_end_exclusive, billing_frequency, billing_anchor_day, platform_fee_annual, platform_billing_amount,
  platform_billing_basis, included_runs_per_month, overage_rate_per_run, payment_terms, currency, executed_date, source_citation, evidence)
select t.document_id || ':v1', r.salesforce_account_id, t.customer_name, t.contract_id, t.document_id, t.document_id, 1, 'original',
  t.service_start,
  coalesce((select min(a.effective_from) from ref.contract_amendment_terms a join raw.contract_register ar on ar.document_id = a.amendment_document_id
            where ar.supersedes_document_id = t.document_id), t.service_end_exclusive),
  t.service_start, t.service_end_exclusive, t.billing_frequency, t.billing_anchor_day,
  t.annual_platform_commitment, t.platform_fee,
  case t.billing_frequency when 'annual' then 'one annual invoice in advance on service start' else 'monthly invoice in advance on day ' || t.billing_anchor_day end,
  t.included_runs_per_month, t.overage_rate_per_run, x.payment_terms, x.currency, x.executed_date,
  t.document_id || '.pdf p.1/1: 02 Subscription Term and Payment; 03 Services and Fees; 04 Billing and Commercial Terms',
  t.evidence
from ref.contract_terms t join raw.contract_register r using (document_id) join ref.contract_doc_extras x using (document_id);

-- v2: amendments. Unchanged terms persist from the base order form (START_HERE: an amendment changes only named terms).
insert into ref.contract_term_versions (version_id, salesforce_account_id, customer_name, contract_id, source_document_id, base_document_id, version_no, version_type,
  effective_from, effective_to_exclusive, term_start, term_end_exclusive, billing_frequency, billing_anchor_day, platform_fee_annual, platform_billing_amount,
  platform_billing_basis, included_runs_per_month, overage_rate_per_run, payment_terms, currency, executed_date, changed_terms, source_citation, evidence)
select a.amendment_document_id || ':v2', b.salesforce_account_id, b.customer_name, b.contract_id, a.amendment_document_id, b.base_document_id, 2, 'amendment',
  a.eff, b.term_end_exclusive, b.term_start, b.term_end_exclusive, b.billing_frequency, b.billing_anchor_day,
  coalesce(a.annual_fee, b.platform_fee_annual), coalesce(a.monthly_invoice, b.platform_billing_amount),
  case when a.monthly_invoice is distinct from b.platform_billing_amount and a.monthly_invoice is not null
       then 'monthly invoice in advance; amended amount applies from the November 2026 invoice (October upgrade catch-up is a separate charge)' else b.platform_billing_basis end,
  coalesce(a.runs, b.included_runs_per_month), coalesce(a.rate, b.overage_rate_per_run), b.payment_terms, b.currency, x.executed_date,
  a.changed, a.amendment_document_id || '.pdf p.1/1: 03 Changes to Commercial Terms; 04 Application and Other Terms (unchanged terms carried from ' || b.base_document_id || ')',
  a.evidence
from (
  select am.amendment_document_id, am.original_document_id, min(am.effective_from) as eff,
         max(am.numeric_value) filter (where am.term = 'annual_platform_rate') as annual_fee,
         max(am.numeric_value) filter (where am.term = 'monthly_platform_invoice' and am.new_value like '%from%') as monthly_invoice,
         max(am.numeric_value) filter (where am.term = 'included_runs_per_month')::int as runs,
         null::numeric as rate,
         array_remove(array[ case when bool_or(am.term = 'annual_platform_rate') then 'platform_fee_annual' end,
                             case when bool_or(am.term = 'monthly_platform_invoice' and am.new_value like '%from%') then 'platform_billing_amount' end,
                             case when bool_or(am.term = 'included_runs_per_month') then 'included_runs_per_month' end ], null) as changed,
         jsonb_object_agg(am.term, jsonb_build_object('prior', am.prior_value, 'new', am.new_value, 'quote', am.evidence)) as evidence
  from ref.contract_amendment_terms am group by 1, 2
) a
join ref.contract_term_versions b on b.version_id = a.original_document_id || ':v1'
join ref.contract_doc_extras x on x.document_id = a.amendment_document_id;

-- Fees and credits stated in the documents (separate rows, each with its own status and quote).
create table ref.contract_term_fees (
  id serial primary key,
  version_id text not null references ref.contract_term_versions(version_id),
  kind text not null,
  amount numeric(14,2) not null,
  effective_from date,
  basis text not null,
  quote text not null,
  source_citation text not null,
  status text not null check (status in ('extracted','needs_info')),
  needs_info_reason text
);
insert into ref.contract_term_fees (version_id, kind, amount, effective_from, basis, quote, source_citation, status, needs_info_reason)
select 'AM-OF-2026-164:v2', a.term, a.numeric_value, a.effective_from,
  case a.term when 'october_upgrade_catch_up' then 'additional October-service charge: USD 12,000 x 16 / 365, rounded half up'
              when 'incremental_consideration_remaining_term' then 'incremental consideration for the 320 remaining service days'
              when 'final_invoice_credit' then 'credit on the final platform invoice reconciling the monthly billing convention' end,
  a.evidence, a.source_file || ' p.1/1: 03 Changes to Commercial Terms; 04 Application and Other Terms',
  case when a.term = 'october_upgrade_catch_up' then 'needs_info' else 'extracted' end,
  case when a.term = 'october_upgrade_catch_up' then 'Quote says the charge "may be invoiced separately": permissive wording. The amount is stated but no obligation or invoice date is. Controller to confirm a supplemental invoice is required.' end
from ref.contract_amendment_terms a
where a.amendment_document_id = 'AM-OF-2026-164' and a.term in ('october_upgrade_catch_up','incremental_consideration_remaining_term','final_invoice_credit');

-- Checks against contract_register.csv and arithmetic. A failed check is never overridden; it becomes needs_info.
create view ref.v_contract_term_checks as
select v.version_id,
  (r.contract_id = v.contract_id) as c_contract_id,
  (s.account_name = v.customer_name) as c_customer_name,
  (r.effective_from = v.effective_from) as c_effective_from,
  (r.effective_to = v.term_end_exclusive) as c_term_end,
  ((r.signed_at at time zone 'America/Denver')::date = v.executed_date) as c_executed_date,
  (v.platform_fee_annual = v.platform_billing_amount * case v.billing_frequency when 'monthly' then 12 else 1 end) as c_annual_equals_billing,
  ((v.term_end_exclusive - v.term_start) = 365) as c_term_365_days,
  (v.payment_terms = 'Net 30' and v.currency = 'USD') as c_net30_usd,
  (extract(day from v.term_start) = v.billing_anchor_day) as c_anchor_matches_term_start,
  (v.version_type = 'original' or r.supersedes_document_id = v.base_document_id) as c_supersedes_matches
from ref.contract_term_versions v
join raw.contract_register r on r.document_id = v.source_document_id
join raw.salesforce_accounts s on s.account_id = v.salesforce_account_id;

update ref.contract_term_versions v set
  status = case when c.c_contract_id and c.c_customer_name and c.c_effective_from and c.c_term_end and c.c_executed_date and c.c_annual_equals_billing
                     and c.c_term_365_days and c.c_net30_usd and c.c_anchor_matches_term_start and c.c_supersedes_matches then 'extracted' else 'needs_info' end,
  confidence = case when c.c_contract_id and c.c_customer_name and c.c_effective_from and c.c_term_end and c.c_executed_date and c.c_annual_equals_billing
                     and c.c_term_365_days and c.c_net30_usd and c.c_anchor_matches_term_start and c.c_supersedes_matches then 'high' else 'low' end,
  needs_info_reason = nullif(concat_ws('; ',
      case when not c.c_contract_id then 'contract_id differs from register' end, case when not c.c_customer_name then 'customer name differs from Salesforce' end,
      case when not c.c_effective_from then 'effective date differs from register' end, case when not c.c_term_end then 'term end differs from register' end,
      case when not c.c_executed_date then 'executed date differs from register signed_at' end, case when not c.c_annual_equals_billing then 'annual fee does not equal billing amount x periods' end,
      case when not c.c_term_365_days then 'term is not 365 days' end, case when not c.c_net30_usd then 'payment terms/currency not Net 30 USD' end,
      case when not c.c_anchor_matches_term_start then 'anchor day differs from term start day' end, case when not c.c_supersedes_matches then 'supersedes link differs from register' end), '')
from ref.v_contract_term_checks c where c.version_id = v.version_id;

-- Sanity checks: recomputed independently from the stated inputs, then compared with the document's stated figure. Not forced.
create view ref.v_contract_sanity_checks as
with m as (select * from ref.contract_term_versions where source_document_id = 'AM-OF-2026-164' or version_id = 'OF-2026-164:v1'),
     c as (select * from ref.contract_term_versions where source_document_id = 'AM-OF-2026-157' or version_id = 'OF-2026-157:v1'),
     f as (select kind, amount from ref.contract_term_fees where version_id = 'AM-OF-2026-164:v2'),
     eff as (select effective_from from ref.contract_term_versions where version_id = 'AM-OF-2026-164:v2')
select 'Meridian annual platform fee before' as check_name, '48000.00' as expected, (select platform_fee_annual::text from m where version_no = 1) as actual
union all select 'Meridian annual platform fee after', '60000.00', (select platform_fee_annual::text from m where version_no = 2)
union all select 'Meridian upgrade effective date', '2026-10-16', (select effective_from::text from eff)
union all select 'Meridian October catch-up: stated amount', '526.03', (select amount::text from f where kind = 'october_upgrade_catch_up')
union all select 'Meridian October catch-up: recomputed (12,000 x 16 / 365, half up)', '526.03',
   (select round(((select platform_fee_annual from m where version_no = 2) - (select platform_fee_annual from m where version_no = 1)) * (date '2026-11-01' - (select effective_from from eff)) / 365.0, 2)::text)
union all select 'Meridian incremental consideration, remaining days', '320',
   (select ((select term_end_exclusive from m where version_no = 2) - (select effective_from from eff))::text)
union all select 'Meridian incremental consideration: stated', '10520.55', (select amount::text from f where kind = 'incremental_consideration_remaining_term')
union all select 'Meridian incremental consideration: recomputed (12,000 x 320 / 365)', '10520.55',
   (select round(((select platform_fee_annual from m where version_no = 2) - (select platform_fee_annual from m where version_no = 1)) * ((select term_end_exclusive from m where version_no = 2) - (select effective_from from eff)) / 365.0, 2)::text)
union all select 'Meridian final-invoice credit: stated', '5.48', (select amount::text from f where kind = 'final_invoice_credit')
union all select 'Meridian final-invoice credit: recomputed (catch-up + 10 monthly +1,000 increments - incremental)', '5.48',
   (select ((select amount from f where kind = 'october_upgrade_catch_up') + 10 * ((select platform_billing_amount from m where version_no = 2) - (select platform_billing_amount from m where version_no = 1)) - (select amount from f where kind = 'incremental_consideration_remaining_term'))::text)
union all select 'Cedar Harbor allowance before', '30000', (select included_runs_per_month::text from c where version_no = 1)
union all select 'Cedar Harbor allowance after', '45000', (select included_runs_per_month::text from c where version_no = 2)
union all select 'Cedar Harbor amendment effective date', '2026-10-16', (select effective_from::text from c where version_no = 2)
union all select 'Cedar Harbor annual platform fee unchanged', '48000.00', (select platform_fee_annual::text from c where version_no = 2)
union all select 'Cedar Harbor overage rate unchanged', '0.4000', (select overage_rate_per_run::text from c where version_no = 2);

-- Review table: one row per customer (current terms as of 2026-10-31 plus the original where an amendment applies).
create view ref.v_contract_terms_review as
select s.account_name as customer, v1.contract_id, v1.source_document_id as order_form, a.source_document_id as amendment,
  v1.term_start, v1.term_end_exclusive - 1 as term_end_inclusive, v1.billing_frequency, v1.billing_anchor_day,
  v1.platform_fee_annual as annual_fee_original, coalesce(a.platform_fee_annual, v1.platform_fee_annual) as annual_fee_current,
  coalesce(a.platform_billing_amount, v1.platform_billing_amount) as invoice_amount_current,
  v1.included_runs_per_month as allowance_original, coalesce(a.included_runs_per_month, v1.included_runs_per_month) as allowance_current,
  coalesce(a.overage_rate_per_run, v1.overage_rate_per_run) as overage_rate, a.effective_from as amendment_effective_from,
  v1.payment_terms, v1.currency,
  (select string_agg(f.kind || ' ' || f.amount || case when f.status = 'needs_info' then ' [needs_info]' end, '; ' order by f.id) from ref.contract_term_fees f where f.version_id = a.version_id) as fees_and_credits,
  case when v1.status = 'extracted' and coalesce(a.status, 'extracted') = 'extracted'
        and not exists (select 1 from ref.contract_term_fees f where f.version_id = a.version_id and f.status = 'needs_info') then 'extracted' else 'needs_info' end as status,
  case when v1.confidence = 'high' and coalesce(a.confidence, 'high') = 'high' and not exists (select 1 from ref.contract_term_fees f where f.version_id = a.version_id and f.status = 'needs_info') then 'high' else 'medium' end as confidence,
  concat_ws('; ', v1.needs_info_reason, a.needs_info_reason, (select string_agg(f.needs_info_reason, '; ') from ref.contract_term_fees f where f.version_id = a.version_id and f.status = 'needs_info')) as needs_info_reason,
  v1.source_citation || coalesce(' | ' || a.source_citation, '') as citation,
  coalesce(a.approval_status, v1.approval_status) as approval_status
from ref.contract_term_versions v1
join raw.salesforce_accounts s on s.account_id = v1.salesforce_account_id
left join ref.contract_term_versions a on a.base_document_id = v1.source_document_id and a.version_no = 2
where v1.version_no = 1;

alter table ref.contract_doc_extras enable row level security;
alter table ref.contract_term_versions enable row level security;
alter table ref.contract_term_fees enable row level security;
revoke all on all tables in schema ref from anon, authenticated;
