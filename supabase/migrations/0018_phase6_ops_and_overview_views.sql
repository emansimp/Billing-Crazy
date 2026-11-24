-- 0018 (Phase 6, Area 1 part 1): run records, finding labels/decisions, and read-only UI views for the Close overview.
-- UI views live in schema public with a ui_ prefix and are the ONLY objects the browser role can read. They return SQL-computed values; the
-- front end only formats them. Writes (decisions, treatments, runs) go through server routes, never through these views.

create schema if not exists ops;
create table ops.runs (
  run_id serial primary key, period text not null, started_at timestamptz not null default now(), finished_at timestamptz,
  status text not null default 'complete', git_commit text, input_counts jsonb, output_totals jsonb
);
create table ops.finding_decisions (
  finding_id text primary key, decision text not null check (decision in ('draft','more_info_requested','valid_explanation_marked','approved')),
  note text, decided_by text not null default 'Controller (demo, no sign-in)', decided_at timestamptz not null default now()
);
alter table ops.runs enable row level security; alter table ops.finding_decisions enable row level security;
revoke all on schema ops from anon, authenticated; revoke all on all tables in schema ops from anon, authenticated;

-- Records a run: refreshes the findings matrix, snapshots input row counts and output totals.
create function ops.record_run(p_commit text, p_period text default 'Oct 2026') returns int language plpgsql as $$
declare rid int; t0 timestamptz := clock_timestamp();
begin
  perform calc.refresh_findings();
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

-- Stable display labels for findings (F-01 ...). Baseline order follows the mockup (F-01 Cedar, F-02 Meridian, F-03 Zephyr, ...), then class, check, customer.
create table ref.finding_labels (finding_id text primary key, sort_no int not null unique);
insert into ref.finding_labels (finding_id, sort_no)
select finding_id, row_number() over (order by
  case when check_code = 'usage_variance' and customer like 'Cedar%' then 1 when check_code = 'platform_variance' and customer like 'Meridian%' then 2
       when check_code = 'concession' and customer like 'Zephyr%' then 3 when check_code = 'void_credit_note' then 4 when check_code = 'unassigned_usage' then 5
       when check_code = 'concession' and customer like 'Willow%' then 6 when check_code = 'missing_usage_invoice' and customer like 'Willow%' then 7
       when check_code = '15th_anchor_timing' and customer like 'Crescent%' then 8 else 9 end,
  case class when 'error' then 1 when 'needs_info' then 2 else 3 end, check_code, customer)
from calc.v_findings
where not (check_code = 'amendment_not_loaded' or (check_code = 'missing_usage_invoice' and class = 'error'));
alter table ref.finding_labels enable row level security; revoke all on ref.finding_labels from anon, authenticated;
