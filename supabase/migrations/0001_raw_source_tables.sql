-- 0001: raw source tables. One table per supplied CSV, loaded as-is (no business logic).
-- Money: Stripe = integer cents (bigint); NetSuite = numeric(14,2). No floats anywhere.
create schema if not exists raw;

create table raw.salesforce_accounts (
  account_id text primary key,
  account_name text not null,
  parent_id text,
  billing_country text,
  stripe_customer_id text,
  netsuite_customer_internal_id text,
  account_owner text
);

create table raw.contract_register (
  document_id text primary key,
  contract_id text not null,
  salesforce_account_id text not null,
  document_type text not null,
  document_filename text not null,
  signed_at timestamptz,
  effective_from date,
  effective_to date,
  supersedes_document_id text,
  billing_loaded_at timestamptz,
  approval_reference text
);

create table raw.product_account_mapping (
  product_account_id text primary key,
  salesforce_account_id text,
  account_label text,
  effective_from date,
  effective_to date,
  mapping_updated_at timestamptz
);

-- record_id is the dedup key but the export may repeat it, so no PK on it; src_row preserves file order.
create table raw.product_usage (
  src_row integer generated always as identity primary key,
  record_id text not null,
  product_account_id text not null,
  sku text not null,
  service_date date not null,
  units bigint,
  ingested_at timestamptz,
  record_status text,
  replaces_record_id text,
  batch_id text
);
create index on raw.product_usage (record_id);
create index on raw.product_usage (product_account_id, service_date);

create table raw.usage_batch_controls (
  service_date date primary key,
  batch_id text not null,
  distinct_active_record_count integer not null,
  active_units_total bigint not null,
  extracted_at timestamptz
);

create table raw.stripe_invoices (
  id text primary key,
  number text,
  customer_id text not null,
  status text,
  created timestamptz,
  finalized_at timestamptz,
  currency text,
  subtotal bigint,
  total_discount_amount bigint,
  total bigint,
  source_system text
);

create table raw.stripe_invoice_lines (
  id text primary key,
  invoice_id text not null,
  description text,
  product_id text,
  price_id text,
  quantity bigint,
  unit_amount_decimal numeric,
  amount bigint,
  discount_amount bigint,
  period_start timestamptz,
  period_end timestamptz,
  proration boolean
);
create index on raw.stripe_invoice_lines (invoice_id);

create table raw.stripe_credit_notes (
  id text primary key,
  number text,
  invoice_id text,
  customer_id text,
  status text,
  created timestamptz,
  voided_at timestamptz,
  currency text,
  amount bigint,
  reason text
);

create table raw.stripe_credit_note_lines (
  id text primary key,
  credit_note_id text not null,
  invoice_line_item_id text,
  description text,
  amount bigint,
  quantity bigint,
  service_start date,
  service_end_exclusive date,
  service_period_source text
);

create table raw.netsuite_gl_detail (
  internal_id text not null,
  line_id integer not null,
  transaction_type text,
  document_number text,
  txn_date date,
  posting_period text,
  account_number text not null,
  customer_internal_id text,
  debit numeric(14,2) not null default 0,
  credit numeric(14,2) not null default 0,
  memo text,
  external_source_id text,
  revenue_plan_id text,
  created_at timestamptz,
  primary key (internal_id, line_id)
);

create table raw.netsuite_opening_balances (
  customer_internal_id text not null,
  account_number text not null,
  account_name text,
  as_of_date date,
  debit_balance numeric(14,2) not null default 0,
  credit_balance numeric(14,2) not null default 0,
  source_reference text,
  primary key (customer_internal_id, account_number)
);

create table raw.netsuite_revenue_plan_detail (
  src_row integer generated always as identity primary key,
  revenue_plan_id text not null,
  revenue_element_id text,
  customer_internal_id text,
  source_document_id text,
  plan_type text,
  recognition_start date,
  recognition_end_exclusive date,
  posting_period text,
  planned_amount numeric(14,2),
  recognized_amount numeric(14,2),
  journal_internal_id text,
  plan_updated_at timestamptz
);

-- Lock down: raw data is server-side only, never exposed to the browser roles.
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname='raw' loop
    execute format('alter table raw.%I enable row level security', t);
  end loop;
end $$;
revoke all on schema raw from anon, authenticated;
revoke all on all tables in schema raw from anon, authenticated;
