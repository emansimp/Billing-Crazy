-- 0028: performance. The treatment-independent adjustment base (what must be adjusted and by how much) is snapshotted; the treatment layer
-- (v_adjustment_lines and everything below it) stays live and now reads the snapshots, so treatment changes show immediately and cheaply.
-- The snapshots refresh whenever a run is recorded (ops.refresh_calc), i.e. whenever the underlying data could have changed.
create materialized view calc.mv_adjustment_base as select * from calc.v_adjustment_base;
create materialized view calc.mv_reclass_incremental as select * from calc.v_reclass_incremental;
create function ops.refresh_calc() returns void language plpgsql as $f$
begin
  refresh materialized view calc.mv_adjustment_base;
  refresh materialized view calc.mv_reclass_incremental;
end $f$;

create or replace view calc.v_adjustment_lines as
with lines as (
  select 'ADJ:' || b.finding_check || ':' || b.salesforce_account_id as line_id, b.salesforce_account_id, b.account_name, b.netsuite_customer_internal_id,
         b.stream, b.adjustment_kind, b.amount, b.direction, b.finding_check, b.calc_basis, 1 as line_order
  from calc.mv_adjustment_base b
  union all
  select 'ADJ:reclass:' || r.salesforce_account_id, r.salesforce_account_id, c.account_name, r.netsuite_customer_internal_id, 'platform', 'contract_asset_reclass',
         r.incremental_reclass, 'under', 'platform_variance',
         'required 1160 ' || round(r.required_1160, 2) || ' (net debit in 2200 after corrected recognition) minus existing 1160 ' || round(r.existing_1160, 2), 2
  from calc.mv_reclass_incremental r join stg.customers c using (salesforce_account_id) where r.incremental_reclass <> 0
), numbered as (
  select l.*, dense_rank() over (order by l.account_name) as entry_no from lines l
)
select n.line_id, 'BR-OCT26-JE' || lpad(n.entry_no::text, 2, '0') as external_id, n.salesforce_account_id, n.account_name as customer, n.netsuite_customer_internal_id,
       n.stream, n.adjustment_kind, n.direction, round(n.amount, 2) as amount, n.line_order,
       (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default) as policy_default_treatment,
       coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) as selected_treatment,
       (o.treatment is not null and o.treatment <> (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) as treatment_overridden,
       o.reason as override_reason,
       (select array_agg(p.treatment order by p.treatment) from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind) as allowed_treatments,
       pr.debit_account, pr.credit_account,
       (pr.adjustment_kind is not null) as treatment_valid,
       exists (select 1 from ref.chart_of_accounts a where a.account_number in (pr.debit_account, pr.credit_account) and a.placeholder) as uses_placeholder_account,
       (select string_agg(a.account_number || ' ' || a.account_name || ' is a PLACEHOLDER account (not in the supplied chart of accounts): map it to a real NetSuite account before import', '; ')
          from ref.chart_of_accounts a where a.account_number in (pr.debit_account, pr.credit_account) and a.placeholder) as placeholder_warning,
       (select f.finding_id from calc.v_findings f where f.check_code = n.finding_check and f.salesforce_account_id = n.salesforce_account_id) as finding_id,
       n.finding_check, n.calc_basis, pr.note as treatment_note,
       (select journal_posting_period from ref.close_params) as posting_period, (select journal_date from ref.close_params) as entry_date,
       (coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) <> 'none') as posts_entry,
       case when n.adjustment_kind = 'concession_already_reflected'
                 and coalesce(o.treatment, 'none') <> 'none'
            then 'DOUBLE-COUNT WARNING: ' || n.calc_basis || '. Posting this entry reduces October revenue a second time.' end as double_count_warning
from numbered n
left join ref.adjustment_treatments o on o.line_id = n.line_id
left join ref.treatment_account_pairs pr on pr.adjustment_kind = n.adjustment_kind
     and pr.treatment = case n.adjustment_kind when 'contract_asset_reclass' then 'policy'
                             else coalesce(o.treatment, (select p.treatment from ref.treatment_account_pairs p where p.adjustment_kind = n.adjustment_kind and p.is_policy_default)) end;


create or replace function ops.refresh_ui(p_scope text default 'all') returns void language plpgsql as $f$
begin
  if p_scope in ('all', 'data') then perform ops.refresh_calc(); end if;
  if p_scope in ('all', 'findings') then
    refresh materialized view public.ui_findings_list; refresh materialized view public.ui_findings_counts;
    refresh materialized view public.ui_finding_detail; refresh materialized view public.ui_finding_evidence; refresh materialized view public.ui_finding_math;
    refresh materialized view public.ui_finding_math_notes; refresh materialized view public.ui_finding_action; refresh materialized view public.ui_finding_sources;
  end if;
  if p_scope in ('all', 'overview', 'journal') then
    refresh materialized view public.ui_close_header; refresh materialized view public.ui_overview_q1; refresh materialized view public.ui_overview_q2;
    refresh materialized view public.ui_overview_q3; refresh materialized view public.ui_overview_q3_summary; refresh materialized view public.ui_readiness;
  end if;
  if p_scope in ('all', 'corrections', 'journal') then refresh materialized view public.ui_billing_corrections; end if;
  if p_scope in ('all', 'recon') then
    refresh materialized view public.ui_customers; refresh materialized view public.ui_customers_summary; refresh materialized view public.ui_unassigned_workspace;
    refresh materialized view public.ui_customer_header; refresh materialized view public.ui_customer_kpis; refresh materialized view public.ui_customer_versions;
    refresh materialized view public.ui_customer_allowance; refresh materialized view public.ui_customer_usage_validation; refresh materialized view public.ui_customer_invoices;
    refresh materialized view public.ui_customer_credit_notes; refresh materialized view public.ui_customer_gl_trail; refresh materialized view public.ui_customer_rollforward;
    refresh materialized view public.ui_controls; refresh materialized view public.ui_open_items; refresh materialized view public.ui_assumptions;
  end if;
end $f$;
