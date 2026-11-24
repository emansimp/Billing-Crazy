-- 0007: Phase 0 provenance. Keeps the typed raw tables from 0001 (staging views depend on them) and adds
-- load_batch_id + source_file to each, a batch/file ledger, the START_HERE manifest, and a counts-only public view.
create table raw.load_batches (
  load_batch_id uuid primary key default gen_random_uuid(),
  loaded_at timestamptz not null default now(),
  source_folder text,
  git_commit text
);
create table raw.source_manifest (
  source_file text primary key,
  raw_table text not null,
  expected_rows integer not null,
  basis text not null
);
create table raw.load_files (
  load_batch_id uuid not null references raw.load_batches(load_batch_id),
  source_file text not null references raw.source_manifest(source_file),
  csv_rows integer not null,
  db_rows integer not null,
  expected_rows integer not null,
  status text not null check (status in ('PASS','FAIL')),
  primary key (load_batch_id, source_file)
);
-- ref tables pointed FKs at raw.contract_register; drop so raw can be truncated and reloaded. Integrity is re-checked in SQL.
alter table ref.contract_terms drop constraint if exists contract_terms_document_id_fkey;
alter table ref.contract_amendment_terms drop constraint if exists contract_amendment_terms_amendment_document_id_fkey;

alter table raw.contract_register add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.netsuite_gl_detail add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.netsuite_opening_balances add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.netsuite_revenue_plan_detail add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.product_account_mapping add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.product_usage add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.salesforce_accounts add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.stripe_credit_note_lines add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.stripe_credit_notes add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.stripe_invoice_lines add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.stripe_invoices add column if not exists load_batch_id uuid, add column if not exists source_file text;
alter table raw.usage_batch_controls add column if not exists load_batch_id uuid, add column if not exists source_file text;
insert into raw.source_manifest values
('contract_register.csv','contract_register',32,'START_HERE p5'),
('netsuite_gl_detail.csv','netsuite_gl_detail',340,'START_HERE p5'),
('netsuite_opening_balances.csv','netsuite_opening_balances',120,'START_HERE p5'),
('netsuite_revenue_plan_detail.csv','netsuite_revenue_plan_detail',362,'START_HERE p5'),
('product_account_mapping.csv','product_account_mapping',32,'START_HERE p5'),
('product_usage.csv','product_usage',1925,'Phase 0 brief: 1,925 physical rows incl. one duplicate (ur_7352010ec2e04c); START_HERE: 1,924 unique'),
('salesforce_accounts.csv','salesforce_accounts',30,'START_HERE p5'),
('stripe_credit_note_lines.csv','stripe_credit_note_lines',2,'START_HERE p5'),
('stripe_credit_notes.csv','stripe_credit_notes',2,'START_HERE p5'),
('stripe_invoice_lines.csv','stripe_invoice_lines',124,'START_HERE p5'),
('stripe_invoices.csv','stripe_invoices',124,'START_HERE p5'),
('usage_batch_controls.csv','usage_batch_controls',61,'START_HERE p3: 61 service dates');

-- Counts only; no business data. Readable by the browser role so the page can show it without a service key.
create view public.load_manifest_check as
with latest as (select load_batch_id from raw.load_batches order by loaded_at desc limit 1),
c as (select 'contract_register.csv' as source_file, 32 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.contract_register
union all
select 'netsuite_gl_detail.csv' as source_file, 340 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.netsuite_gl_detail
union all
select 'netsuite_opening_balances.csv' as source_file, 120 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.netsuite_opening_balances
union all
select 'netsuite_revenue_plan_detail.csv' as source_file, 362 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.netsuite_revenue_plan_detail
union all
select 'product_account_mapping.csv' as source_file, 32 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.product_account_mapping
union all
select 'product_usage.csv' as source_file, 1925 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.product_usage
union all
select 'salesforce_accounts.csv' as source_file, 30 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.salesforce_accounts
union all
select 'stripe_credit_note_lines.csv' as source_file, 2 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.stripe_credit_note_lines
union all
select 'stripe_credit_notes.csv' as source_file, 2 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.stripe_credit_notes
union all
select 'stripe_invoice_lines.csv' as source_file, 124 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.stripe_invoice_lines
union all
select 'stripe_invoices.csv' as source_file, 124 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.stripe_invoices
union all
select 'usage_batch_controls.csv' as source_file, 61 as expected_rows, count(*) filter (where load_batch_id = (select load_batch_id from latest)) as db_rows from raw.usage_batch_controls),
files as (
  select c.source_file, c.expected_rows, lf.csv_rows, c.db_rows,
         case when c.db_rows = c.expected_rows and lf.csv_rows = c.expected_rows then 'PASS' else 'FAIL' end as status, m.basis
  from c join raw.source_manifest m using (source_file)
  left join raw.load_files lf on lf.source_file = c.source_file and lf.load_batch_id = (select load_batch_id from latest)
)
select source_file, expected_rows, csv_rows, db_rows, status, basis from files
union all
select 'product_usage.csv (distinct record_id)', 1924, null,
       (select count(distinct record_id) from raw.product_usage where load_batch_id = (select load_batch_id from latest)),
       case when (select count(distinct record_id) from raw.product_usage where load_batch_id = (select load_batch_id from latest)) = 1924 then 'PASS' else 'FAIL' end,
       'START_HERE p3: 1,924 unique source daily usage records'
union all
select 'product_usage.csv (duplicate ur_7352010ec2e04c rows, left in staging)', 2, null,
       (select count(*) from raw.product_usage where record_id = 'ur_7352010ec2e04c' and load_batch_id = (select load_batch_id from latest)),
       case when (select count(*) from raw.product_usage where record_id = 'ur_7352010ec2e04c' and load_batch_id = (select load_batch_id from latest)) = 2 then 'PASS' else 'FAIL' end,
       'Phase 0 brief: one repeated source ID retained in staging; removed in stg.usage_deduped'
order by 1;
grant select on public.load_manifest_check to anon, authenticated;
alter table raw.load_batches enable row level security;
alter table raw.source_manifest enable row level security;
alter table raw.load_files enable row level security;
revoke all on all tables in schema raw from anon, authenticated;
