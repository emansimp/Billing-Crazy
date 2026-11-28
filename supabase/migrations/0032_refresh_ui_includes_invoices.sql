-- 0032: the full UI refresh (run) now includes the Area 4 invoice snapshots; scope 'invoices' refreshes them alone.
create or replace function ops.refresh_ui(p_scope text default 'all') returns void language plpgsql as $f$
begin
  if p_scope in ('all', 'data') then perform ops.refresh_calc(); end if;
  if p_scope in ('all', 'invoices') then perform ops.refresh_invoices(); end if;
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
