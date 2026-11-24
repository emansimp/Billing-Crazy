-- 0023: performance. Through the API the ui_ views took 2-10 s each, so the UI layer is materialized (ui_X = snapshot of ui_X_live).
-- Snapshots refresh when a run is recorded (ops.record_run) or on demand (ops.refresh_ui). Finding decisions stay LIVE via ui_finding_decisions
-- so a click shows immediately. The browser role can read only the snapshots and the live decision view.

alter view public.ui_close_header rename to ui_close_header_live;
create materialized view public.ui_close_header as select * from public.ui_close_header_live;
grant select on public.ui_close_header to anon, authenticated;
revoke all on public.ui_close_header_live from anon, authenticated;
alter view public.ui_overview_q1 rename to ui_overview_q1_live;
create materialized view public.ui_overview_q1 as select * from public.ui_overview_q1_live;
grant select on public.ui_overview_q1 to anon, authenticated;
revoke all on public.ui_overview_q1_live from anon, authenticated;
alter view public.ui_overview_q2 rename to ui_overview_q2_live;
create materialized view public.ui_overview_q2 as select * from public.ui_overview_q2_live;
grant select on public.ui_overview_q2 to anon, authenticated;
revoke all on public.ui_overview_q2_live from anon, authenticated;
alter view public.ui_overview_q3 rename to ui_overview_q3_live;
create materialized view public.ui_overview_q3 as select * from public.ui_overview_q3_live;
grant select on public.ui_overview_q3 to anon, authenticated;
revoke all on public.ui_overview_q3_live from anon, authenticated;
alter view public.ui_overview_q3_summary rename to ui_overview_q3_summary_live;
create materialized view public.ui_overview_q3_summary as select * from public.ui_overview_q3_summary_live;
grant select on public.ui_overview_q3_summary to anon, authenticated;
revoke all on public.ui_overview_q3_summary_live from anon, authenticated;
alter view public.ui_findings_list rename to ui_findings_list_live;
create materialized view public.ui_findings_list as select * from public.ui_findings_list_live;
grant select on public.ui_findings_list to anon, authenticated;
revoke all on public.ui_findings_list_live from anon, authenticated;
alter view public.ui_findings_counts rename to ui_findings_counts_live;
create materialized view public.ui_findings_counts as select * from public.ui_findings_counts_live;
grant select on public.ui_findings_counts to anon, authenticated;
revoke all on public.ui_findings_counts_live from anon, authenticated;
alter view public.ui_billing_corrections rename to ui_billing_corrections_live;
create materialized view public.ui_billing_corrections as select * from public.ui_billing_corrections_live;
grant select on public.ui_billing_corrections to anon, authenticated;
revoke all on public.ui_billing_corrections_live from anon, authenticated;
alter view public.ui_readiness rename to ui_readiness_live;
create materialized view public.ui_readiness as select * from public.ui_readiness_live;
grant select on public.ui_readiness to anon, authenticated;
revoke all on public.ui_readiness_live from anon, authenticated;
alter view public.ui_finding_detail rename to ui_finding_detail_live;
create materialized view public.ui_finding_detail as select * from public.ui_finding_detail_live;
grant select on public.ui_finding_detail to anon, authenticated;
revoke all on public.ui_finding_detail_live from anon, authenticated;
alter view public.ui_finding_evidence rename to ui_finding_evidence_live;
create materialized view public.ui_finding_evidence as select * from public.ui_finding_evidence_live;
grant select on public.ui_finding_evidence to anon, authenticated;
revoke all on public.ui_finding_evidence_live from anon, authenticated;
alter view public.ui_finding_math rename to ui_finding_math_live;
create materialized view public.ui_finding_math as select * from public.ui_finding_math_live;
grant select on public.ui_finding_math to anon, authenticated;
revoke all on public.ui_finding_math_live from anon, authenticated;
alter view public.ui_finding_math_notes rename to ui_finding_math_notes_live;
create materialized view public.ui_finding_math_notes as select * from public.ui_finding_math_notes_live;
grant select on public.ui_finding_math_notes to anon, authenticated;
revoke all on public.ui_finding_math_notes_live from anon, authenticated;
alter view public.ui_finding_action rename to ui_finding_action_live;
create materialized view public.ui_finding_action as select * from public.ui_finding_action_live;
grant select on public.ui_finding_action to anon, authenticated;
revoke all on public.ui_finding_action_live from anon, authenticated;
alter view public.ui_finding_sources rename to ui_finding_sources_live;
create materialized view public.ui_finding_sources as select * from public.ui_finding_sources_live;
grant select on public.ui_finding_sources to anon, authenticated;
revoke all on public.ui_finding_sources_live from anon, authenticated;

create view public.ui_finding_decisions as select finding_id, decision, decided_at from ops.finding_decisions;
grant select on public.ui_finding_decisions to anon, authenticated;

create or replace function ops.refresh_ui(p_scope text default 'all') returns void language plpgsql as $$
begin
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
end $$;

-- record_run now also refreshes the UI snapshots (after the findings matrix)
create or replace function ops.record_run(p_commit text, p_period text default 'Oct 2026') returns int language plpgsql as $$
declare rid int; t0 timestamptz := clock_timestamp();
begin
  perform calc.refresh_findings();
  perform ops.refresh_ui('all');
  insert into ops.runs (period, started_at, finished_at, git_commit, input_counts, output_totals)
  select p_period, t0, clock_timestamp(), p_commit,
    (select jsonb_object_agg(source_file, db_rows) from public.load_manifest_check),
    jsonb_build_object(
      'platform_expected_alloc', (select sum(expected_invoices_allocated_to_period) from calc.v_expected_platform),
      'platform_billed_alloc', (select sum(billed_allocated_to_period) from calc.v_billed_platform),
      'usage_expected_net', (select sum(usage_expected_net) from calc.v_expected_vs_billed),
      'usage_billed_net', (select sum(usage_billed_net) from calc.v_expected_vs_billed),
      'under_billed_usage', (select sum(usage_under_billed) from calc.v_expected_vs_billed),
      'over_billed_usage', (select sum(usage_over_billed) from calc.v_expected_vs_billed),
      'under_billed_platform', (select sum(platform_under_billed) from calc.v_expected_vs_billed),
      'findings', (select count(*) from calc.v_findings),
      'entries', (select count(distinct external_id) from calc.v_journal_lines),
      'journal_debits', (select sum(debit) from calc.v_journal_lines),
      'controls_pass', (select count(*) from calc.v_controls where status = 'pass'))
  returning run_id into rid;
  return rid;
end $$;
