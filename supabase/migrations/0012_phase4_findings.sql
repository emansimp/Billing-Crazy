-- 0012 (Phase 4): findings. One check matrix: every customer gets a recorded result for every check (class 'pass' = checked, nothing found).
-- v_findings = the non-pass results. Amounts come from the Phase 3 views / source rows; text is only a label.
-- in_variance_total = true only for the rows that make up the Phase 3 expected-vs-billed variance (so totals tie); diagnoses, valid
-- explanations and later-service follow-ups carry amounts for context but are excluded from that total.
create view calc.v_check_results as
with docs as (select salesforce_account_id, array_agg(document_id order by document_id) as docs from raw.contract_register group by 1),
cit as (select salesforce_account_id, string_agg(source_citation, ' | ' order by version_no) as citation from ref.contract_term_versions group by 1),
cust as (select c.salesforce_account_id, c.account_name, d.docs, ci.citation from stg.customers c left join docs d using (salesforce_account_id) left join cit ci using (salesforce_account_id)),
-- C1 platform variance (Phase 3, invoice basis)
c1 as (
  select 'platform_variance' as check_code, 'Platform: expected vs billed (invoice basis)' as check_name, c.salesforce_account_id, c.account_name as customer, 'platform' as stream,
         case when e.platform_under_billed <> 0 or e.platform_over_billed <> 0 then 'error' else 'pass' end as class,
         case when e.platform_under_billed <> 0 or e.platform_over_billed <> 0 then round(greatest(e.platform_under_billed, e.platform_over_billed), 2) end as amount,
         case when e.platform_under_billed <> 0 then 'under' when e.platform_over_billed <> 0 then 'over' end as direction,
         true as in_variance_total, 'october_service' as period_scope,
         jsonb_build_object('invoice_numbers', coalesce(to_jsonb(pb.invoice_numbers_covering_period), '[]'::jsonb), 'line_ids', coalesce(to_jsonb(pb.line_ids_covering_period), '[]'::jsonb), 'contract_documents', to_jsonb(c.docs)) as evidence,
         c.citation as contract_citation,
         case when e.platform_under_billed <> 0 then 'Controller approves; Billing issues a supplemental platform invoice (November issue date) for the under-billed amount; update the billing record with the executed amendment.'
              when e.platform_over_billed <> 0 then 'Controller approves; Billing issues a linked credit note (November issue date).' else 'None' end as recommended_action,
         'Billing (Alex Chen)' as owner, 'Controller (Priya Shah)' as approver,
         'expected to bill ' || round(e.platform_expected_to_bill, 2) || ' vs billed ' || round(e.platform_billed_in_period, 2) as detail
  from cust c join calc.v_expected_vs_billed e using (salesforce_account_id) join calc.v_billed_platform pb using (salesforce_account_id)
),
-- C2 usage variance (Phase 3, net of approved concessions)
c2 as (
  select 'usage_variance', 'Usage: expected vs billed (net of approved concessions)', c.salesforce_account_id, c.account_name, 'usage',
         case when e.usage_under_billed <> 0 or e.usage_over_billed <> 0 then 'error' else 'pass' end,
         case when e.usage_under_billed <> 0 or e.usage_over_billed <> 0 then round(greatest(e.usage_under_billed, e.usage_over_billed), 2) end,
         case when e.usage_under_billed <> 0 then 'under' when e.usage_over_billed <> 0 then 'over' end,
         true, 'october_service',
         jsonb_build_object('invoice_numbers', coalesce(to_jsonb(ub.invoice_numbers), '[]'::jsonb), 'line_ids', coalesce(to_jsonb(ub.line_ids), '[]'::jsonb),
                            'usage_records_verified', ev.record_count, 'contract_documents', to_jsonb(c.docs)),
         c.citation,
         case when e.usage_under_billed <> 0 then 'Controller approves; Billing issues a supplemental usage invoice (November issue date) for ' || round(e.usage_under_billed, 2) || '; '
                || case when q.accrual_adjustment_needed = 0 then 'no October accrual change (the October accrual already matches the contract).'
                        else 'post an October accrual correction of ' || round(abs(q.accrual_adjustment_needed), 2) || ' (October posting period).' end
              when e.usage_over_billed <> 0 then 'Controller approves; Billing issues a linked credit note (November issue date) for ' || round(e.usage_over_billed, 2) || '; '
                || case when q.accrual_adjustment_needed = 0 then 'no October accrual change.' else 'reverse ' || round(abs(q.accrual_adjustment_needed), 2) || ' of October usage accrual (October posting period).' end
              else 'None' end,
         'Billing (Alex Chen)', 'Controller (Priya Shah)',
         case when e.usage_under_billed <> 0 or e.usage_over_billed <> 0 then
              'expected net ' || round(e.usage_expected_net, 2) || ' vs billed net ' || round(e.usage_billed_net, 2) || '; diagnosis: ' || coalesce(f.diagnosis, 'n/a')
              || '; expected overage units ' || ev.overage_units || ' vs billed ' || coalesce(ub.billed_units::text, 'none') || '; contract rate ' || ev.overage_rate_per_run
              || coalesce(' vs billed rate ' || round(f.billed_rate_cents / 100, 4), '')
              else 'expected net ' || round(e.usage_expected_net, 2) || ' = billed net ' || round(e.usage_billed_net, 2) end
  from cust c join calc.v_expected_vs_billed e using (salesforce_account_id) join calc.v_expected_usage ev using (salesforce_account_id)
  join calc.v_billed_usage ub using (salesforce_account_id) join calc.usage_accrual_comparison q using (salesforce_account_id)
  left join calc.usage_findings f on f.salesforce_account_id = c.salesforce_account_id
),
-- C3 amendment not loaded in billing (register billing_loaded_at blank)
am as (
  select r.salesforce_account_id, array_agg(r.document_id order by r.document_id) as docs, bool_or(r.billing_loaded_at is null) as unloaded,
         min(r.signed_at) as signed_at, min(r.effective_from) as eff, bool_or('included_runs_per_month' = any(v.changed_terms)) as usage_term,
         string_agg(v.source_citation, ' | ') as citation, array_agg(distinct r.approval_reference) as msgs
  from raw.contract_register r left join ref.contract_term_versions v on v.source_document_id = r.document_id
  where r.document_type = 'amendment' group by 1
),
c3 as (
  select 'amendment_not_loaded', 'Signed amendment not loaded in billing (billing_loaded_at blank)', c.salesforce_account_id, c.account_name,
         case when a.usage_term then 'usage' else 'platform' end,
         case when a.unloaded then 'error' else 'pass' end,
         case when a.unloaded then case when a.usage_term then (select round(greatest(usage_under_billed, usage_over_billed), 2) from calc.v_expected_vs_billed x where x.salesforce_account_id = c.salesforce_account_id)
                                        else (select round(greatest(platform_under_billed, platform_over_billed), 2) from calc.v_expected_vs_billed x where x.salesforce_account_id = c.salesforce_account_id) end end,
         case when a.unloaded then case when a.usage_term then (select case when usage_under_billed <> 0 then 'under' when usage_over_billed <> 0 then 'over' end from calc.v_expected_vs_billed x where x.salesforce_account_id = c.salesforce_account_id)
                                        else (select case when platform_under_billed <> 0 then 'under' when platform_over_billed <> 0 then 'over' end from calc.v_expected_vs_billed x where x.salesforce_account_id = c.salesforce_account_id) end end,
         false, 'october_service',
         case when a.unloaded then jsonb_build_object('amendment_documents', to_jsonb(a.docs), 'register_billing_loaded_at', null, 'messages', to_jsonb(a.msgs)) else '{}'::jsonb end,
         a.citation,
         case when a.unloaded then 'Billing loads the executed amendment (effective ' || a.eff || ') into the billing system before the next invoice run; Sales confirms no other signed amendments are outstanding.' else 'None' end,
         'Billing (Alex Chen) with Sales (Morgan Lee)', 'Controller (Priya Shah)',
         case when a.unloaded then 'amendment ' || array_to_string(a.docs, ',') || ' signed ' || (a.signed_at at time zone 'America/Denver')::date || ' effective ' || a.eff || ' but billing_loaded_at is blank; October invoices were generated without it'
              else 'no signed amendment awaiting billing load' end
  from cust c left join am a using (salesforce_account_id)
),
-- C4 void credit notes: no current credit effect; nothing may be posted for them
vd as (
  select a.account_id as salesforce_account_id, array_agg(n.id) as note_ids, array_agg(distinct n.invoice_id) as invoice_ids, sum(n.amount)::numeric / 100 as amount,
         bool_or(exists (select 1 from raw.netsuite_gl_detail g where g.customer_internal_id = a.netsuite_customer_internal_id and g.transaction_type = 'Credit Memo'
                         and g.account_number = '1100' and g.credit = n.amount::numeric / 100)) as posted_in_gl, min(n.voided_at) as voided_at
  from raw.stripe_credit_notes n join raw.salesforce_accounts a on a.stripe_customer_id = n.customer_id where n.status = 'void' group by 1
),
c4 as (
  select 'void_credit_note', 'Void credit notes have no effect', c.salesforce_account_id, c.account_name, 'usage',
         case when v.note_ids is null then 'pass' when v.posted_in_gl then 'error' else 'valid_explanation' end,
         round(v.amount, 2), null::text, false, 'october_service',
         case when v.note_ids is null then '{}'::jsonb else jsonb_build_object('credit_note_ids', to_jsonb(v.note_ids), 'invoice_ids', to_jsonb(v.invoice_ids), 'messages', '["MSG-2026-116"]'::jsonb, 'voided_at', v.voided_at) end,
         'START_HERE p3 CREDITS: use issued notes only; void notes have no current credit effect | billing_followups.pdf MSG-2026-116',
         case when v.note_ids is null then 'None' when v.posted_in_gl then 'A credit was posted in NetSuite for a void note: reverse it (Controller approval).' else 'No action. Void note ignored; confirmed no matching credit memo in NetSuite.' end,
         'Billing (Alex Chen)', 'n/a (no action)',
         case when v.note_ids is null then 'no void credit notes' else 'void credit ' || round(v.amount, 2) || ' ignored; matching NetSuite credit memo posted: ' || v.posted_in_gl end
  from cust c left join vd v using (salesforce_account_id)
),
-- C5 concessions: approved ones must be issued once and already in the accrual; unapproved requests authorize nothing
cn as (
  select c.salesforce_account_id, e.approved_concessions as approved, e.unapproved_requests_not_applied as requested, ub.credits_issued, ub.issued_credit_note_ids as note_ids,
         q.gl_accrued, q.expected_net,
         (select array_agg(msg_id order by msg_id) from ref.approvals ap where ap.salesforce_account_id = c.salesforce_account_id and ap.item like 'usage_concession%') as msgs
  from cust c join calc.v_expected_usage e using (salesforce_account_id) join calc.v_billed_usage ub using (salesforce_account_id) join calc.usage_accrual_comparison q using (salesforce_account_id)
),
c5 as (
  select 'concession', 'Concessions: approval, single issue, accrual net', c.salesforce_account_id, c.account_name, 'usage',
         case when n.requested > 0 then 'needs_info'
              when n.approved > 0 and n.credits_issued = n.approved and n.gl_accrued = n.expected_net then 'valid_explanation'
              when n.approved > 0 or n.credits_issued > 0 then 'error' else 'pass' end,
         case when n.requested > 0 then round(n.requested, 2) when n.approved > 0 or n.credits_issued > 0 then round(greatest(n.approved, n.credits_issued), 2) end,
         null::text, false, 'october_service',
         case when n.msgs is null and n.credits_issued = 0 then '{}'::jsonb else jsonb_build_object('messages', to_jsonb(n.msgs), 'issued_credit_note_ids', coalesce(to_jsonb(n.note_ids), '[]'::jsonb)) end,
         'billing_followups.pdf MSG-2026-108/109 (Zephyr), MSG-2026-132 (Willow) | START_HERE p2 UNVERIFIED USAGE, p3 CREDITS',
         case when n.requested > 0 then 'Do not issue a credit or reduce revenue. Sales requests Controller decision; ownership of any unverified workspace is separate and unproven.'
              when n.approved > 0 and n.credits_issued = n.approved and n.gl_accrued = n.expected_net then 'No action. Approved concession credited once and the October accrual is already net. Do not apply a second concession.'
              when n.approved > 0 or n.credits_issued > 0 then 'Reconcile credit vs approval vs accrual (Controller).' else 'None' end,
         'Controller (Priya Shah)', 'Controller (Priya Shah)',
         case when n.requested > 0 then 'requested ' || round(n.requested, 2) || ', approved ' || round(n.approved, 2) || ': no Controller approval on file'
              when n.approved > 0 or n.credits_issued > 0 then 'approved ' || round(n.approved, 2) || ', issued credit ' || round(n.credits_issued, 2) || ', accrual ' || round(n.gl_accrued, 2) || ' vs expected net ' || round(n.expected_net, 2)
              else 'no concession activity' end
  from cust c join cn n using (salesforce_account_id)
),
-- C6 missing usage invoice
c6 as (
  select 'missing_usage_invoice', 'Usage invoice present when usage is billable', c.salesforce_account_id, c.account_name, 'usage',
         case when ub.billed_usage_gross > 0 then 'pass'
              when ev.attribution_status <> 'verified' then 'needs_info'
              when ev.expected_usage_gross > 0 then 'error' else 'valid_explanation' end,
         case when ub.billed_usage_gross = 0 and ev.attribution_status = 'verified' and ev.expected_usage_gross > 0 then round(ev.expected_usage_net, 2) end,
         case when ub.billed_usage_gross = 0 and ev.attribution_status = 'verified' and ev.expected_usage_gross > 0 then 'under' end,
         false, 'october_service',
         case when ub.billed_usage_gross > 0 then '{}'::jsonb else jsonb_build_object('expected_invoice_date', ev.usage_invoice_due_date, 'verified_units', ev.verified_units, 'allowance_runs', ev.allowance_runs, 'attribution_status', ev.attribution_status) end,
         c.citation || ' | START_HERE p3 BILLING: usage invoiced on the first day of the next month; an absent usage invoice can be valid when no overage exists',
         case when ub.billed_usage_gross > 0 then 'None'
              when ev.attribution_status <> 'verified' then 'Product Operations verifies workspace ownership before Billing assigns any usage; no usage invoice until then.'
              when ev.expected_usage_gross > 0 then 'Issue the missing October usage invoice (November issue date) after Controller approval; see the usage variance finding.'
              else 'No action: verified usage (' || ev.verified_units || ') is within the allowance (' || ev.allowance_runs || '), so no overage invoice is due.' end,
         case when ev.attribution_status <> 'verified' then 'Product Operations' else 'Billing (Alex Chen)' end, 'Controller (Priya Shah)',
         case when ub.billed_usage_gross > 0 then 'usage invoice present'
              else 'no usage invoice; verified units ' || ev.verified_units || ' vs allowance ' || ev.allowance_runs || '; attribution ' || ev.attribution_status end
  from cust c join calc.v_expected_usage ev using (salesforce_account_id) join calc.v_billed_usage ub using (salesforce_account_id)
),
-- C8 15th-anchor timing: invoice periods cross the calendar month; must match the contract schedule
a15 as (
  select e.salesforce_account_id,
         count(*) filter (where e.charge_kind = 'platform_advance' and e.covers_period) as expected_rows,
         count(*) filter (where e.charge_kind = 'platform_advance' and e.covers_period and exists
              (select 1 from calc.v_billed_platform_lines b where b.salesforce_account_id = e.salesforce_account_id and b.period_start = e.period_start and b.billed_amount = e.expected_amount)) as matched_rows,
         string_agg(e.invoice_date || ' (' || e.days_in_report_period || '/' || e.period_days || ' days in October = ' || e.allocated_to_period || ')', '; ' order by e.invoice_date) filter (where e.charge_kind = 'platform_advance' and e.covers_period) as arithmetic
  from calc.v_expected_platform_invoices e where e.billing_anchor_day = 15 group by 1
),
c8 as (
  select '15th_anchor_timing', '15th-anchor invoice periods cross the month end', c.salesforce_account_id, c.account_name, 'platform',
         case when a.salesforce_account_id is null then 'pass' when a.expected_rows = a.matched_rows then 'valid_explanation' else 'error' end,
         case when a.salesforce_account_id is not null then round(abs(pe.expected_revenue - pe.expected_invoices_allocated_to_period), 2) end,
         null::text, false, 'october_service',
         case when a.salesforce_account_id is null then '{}'::jsonb else jsonb_build_object('invoice_numbers', coalesce(to_jsonb(pb.invoice_numbers_covering_period), '[]'::jsonb), 'line_ids', coalesce(to_jsonb(pb.line_ids_covering_period), '[]'::jsonb)) end,
         c.citation || ' | START_HERE p1: neither a crossing-period invoice nor its allocation automatically equals October revenue',
         case when a.salesforce_account_id is null then 'None' when a.expected_rows = a.matched_rows then 'No billing correction. Invoices match the contract schedule; the amount shown is the timing difference between day-based revenue and invoice allocation, not a billing variance.'
              else 'Invoice periods or amounts differ from the 15th-anchor schedule: investigate.' end,
         'Revenue Accounting (Alex Chen)', 'Controller (Priya Shah)',
         case when a.salesforce_account_id is null then 'anchor day 1' else 'invoice periods: ' || a.arithmetic || '; allocated ' || round(pe.expected_invoices_allocated_to_period, 2) || ' vs day-based revenue ' || round(pe.expected_revenue, 2) end
  from cust c left join a15 a using (salesforce_account_id) left join calc.v_expected_platform pe using (salesforce_account_id) left join calc.v_billed_platform pb using (salesforce_account_id)
),
-- C9 duplicate usage records (exact repeated record_id)
dup as (
  select m.salesforce_account_id, array_agg(distinct u.record_id) as ids, sum(u.units) filter (where u.rn > 1) as dup_units
  from (select u.*, row_number() over (partition by record_id order by src_row) rn, count(*) over (partition by record_id) n from raw.product_usage u) u
  join raw.product_account_mapping m using (product_account_id) where u.n > 1 group by 1
),
c9 as (
  select 'duplicate_usage_record', 'Duplicate usage records are not new activity', c.salesforce_account_id, c.account_name, 'usage',
         case when d.ids is null then 'pass' when ev.expected_usage_net = ub.billed_usage_net then 'valid_explanation' else 'error' end,
         null::numeric, null::text, false, 'october_service',
         case when d.ids is null then '{}'::jsonb else jsonb_build_object('usage_record_ids', to_jsonb(d.ids)) end,
         'START_HERE p2 USAGE: versions/duplicates must not be double counted; exact repeated source IDs are not new activity',
         case when d.ids is null then 'None' else 'No action. The repeated row is excluded in v_usage_clean and the invoice matches the de-duplicated usage. Ask Product Operations to fix the export duplication.' end,
         'Product Operations', 'n/a (no action)',
         case when d.ids is null then 'no repeated record_id' else 'repeated ' || array_to_string(d.ids, ',') || ' (' || d.dup_units || ' runs); counting it would have added ' || round(d.dup_units * ev.overage_rate_per_run, 2) || ' of overage (all runs are above the allowance); billing matches the de-duplicated total' end
  from cust c left join dup d using (salesforce_account_id) join calc.v_expected_usage ev using (salesforce_account_id) join calc.v_billed_usage ub using (salesforce_account_id)
),
-- C10 later-service platform invoices (follow-ups, not October)
c10 as (
  select 'later_service_platform', 'Later-service platform invoices (follow-up, not October)', c.salesforce_account_id, c.account_name, 'platform',
         case when pe.later_service_expected_issued_by_cutoff = pb.later_service_billed_by_cutoff then 'pass' else 'error' end,
         case when pe.later_service_expected_issued_by_cutoff <> pb.later_service_billed_by_cutoff then round(abs(pe.later_service_expected_issued_by_cutoff - pb.later_service_billed_by_cutoff), 2) end,
         case when pe.later_service_expected_issued_by_cutoff > pb.later_service_billed_by_cutoff then 'under' when pe.later_service_expected_issued_by_cutoff < pb.later_service_billed_by_cutoff then 'over' end,
         false, 'later_service_followup',
         jsonb_build_object('invoice_numbers', coalesce((select to_jsonb(array_agg(b.invoice_number)) from calc.v_billed_platform_lines b where b.salesforce_account_id = c.salesforce_account_id and b.period_start >= (select period_end_exclusive from ref.close_params)), '[]'::jsonb)),
         c.citation,
         case when pe.later_service_expected_issued_by_cutoff = pb.later_service_billed_by_cutoff then 'None' else 'Follow-up (not October): correct the recurring platform invoice amount in billing; Controller approves any supplemental invoice.' end,
         'Billing (Alex Chen)', 'Controller (Priya Shah)',
         'November-service platform invoices issued by cutoff: expected ' || round(pe.later_service_expected_issued_by_cutoff, 2) || ' vs billed ' || round(pb.later_service_billed_by_cutoff, 2)
  from cust c join calc.v_expected_platform pe using (salesforce_account_id) join calc.v_billed_platform pb using (salesforce_account_id)
),
-- C7 unassigned usage exposure (workspace-level, no customer)
c7 as (
  select 'unassigned_usage', 'Unverified usage isolated (conditional exposure)', null::text, 'UNASSIGNED WORKSPACE ' || u.product_account_id, 'usage', 'needs_info',
         null::numeric, null::text, false, 'october_service',
         jsonb_build_object('product_account_id', u.product_account_id, 'record_ids', to_jsonb(u.record_ids), 'messages', '["MSG-2026-131"]'::jsonb),
         'START_HERE p2 UNVERIFIED USAGE | billing_followups.pdf MSG-2026-131',
         'Product Operations verifies ownership (evidence required). No assignment by elimination, no accrual, no invoice until verified. Conditional October exposure if owned by a single existing customer: '
           || (select round(min(incremental_charge_if_owned), 2) from calc.unverified_conditional_exposure where month_start = '2026-10-01') || ' to '
           || (select round(max(incremental_charge_if_owned), 2) from calc.unverified_conditional_exposure where month_start = '2026-10-01') || '.',
         'Product Operations', 'Controller (Priya Shah)',
         u.unverified_units || ' October runs in ' || u.record_count || ' records; no verified owner'
  from calc.unverified_usage_month u where u.month_start = '2026-10-01'
)
select * from c1 union all select * from c2 union all select * from c3 union all select * from c4 union all select * from c5
union all select * from c6 union all select * from c8 union all select * from c9 union all select * from c10 union all select * from c7;

create view calc.v_findings as
select check_code || ':' || coalesce(salesforce_account_id, 'workspace') as finding_id, *
from calc.v_check_results where class <> 'pass';

-- All 30 customers classified. Severity: error > needs_info > valid_explanation > clean.
create view calc.v_customer_classification as
select c.salesforce_account_id, c.account_name,
       count(r.*) as checks_recorded,
       count(*) filter (where r.class = 'pass') as checks_passed,
       count(*) filter (where r.class = 'error') as errors,
       count(*) filter (where r.class = 'needs_info') as needs_info,
       count(*) filter (where r.class = 'valid_explanation') as valid_explanations,
       case when count(*) filter (where r.class = 'error') > 0 then 'error'
            when count(*) filter (where r.class = 'needs_info') > 0 then 'needs_info'
            when count(*) filter (where r.class = 'valid_explanation') > 0 then 'valid_explanation' else 'clean' end as overall_class,
       array_agg(r.check_code order by r.check_code) filter (where r.class <> 'pass') as finding_checks
from stg.customers c left join calc.v_check_results r using (salesforce_account_id)
group by c.salesforce_account_id, c.account_name;

-- Tie-out: findings counted in the variance total vs the Phase 3 expected-vs-billed totals.
create view calc.v_findings_tieout as
select 'platform under-billed' as measure,
       (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'platform' and direction = 'under') as findings_total,
       (select round(sum(platform_under_billed), 2) from calc.v_expected_vs_billed) as phase3_total
union all select 'platform over-billed', (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'platform' and direction = 'over'), (select round(sum(platform_over_billed), 2) from calc.v_expected_vs_billed)
union all select 'usage under-billed', (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'usage' and direction = 'under'), (select round(sum(usage_under_billed), 2) from calc.v_expected_vs_billed)
union all select 'usage over-billed', (select coalesce(sum(amount), 0) from calc.v_findings where in_variance_total and stream = 'usage' and direction = 'over'), (select round(sum(usage_over_billed), 2) from calc.v_expected_vs_billed);

-- The owner's expectation list vs what the data says (a disagreement is reported, never forced).
create view calc.v_findings_owner_expectations as
with ex(n, customer_like, check_code, expected_class, expected_amount, expected_direction, description) as (values
 (1, 'Cedar%',   'usage_variance',          'error',             3096.80::numeric, 'over',  'Cedar Harbor usage over-billed $3,096.80'),
 (2, 'Meridian%','platform_variance',       'error',             526.03,           'under', 'Meridian platform under-billed $526.03'),
 (3, 'Zephyr%',  'concession',              'valid_explanation', 100.00,           null,    'Zephyr $100 concession valid'),
 (4, 'Alder%',   'void_credit_note',        'valid_explanation', 50.00,            null,    'Alder void $50 credit valid'),
 (5, 'UNASSIGNED%','unassigned_usage',      'needs_info',        null,             null,    'Unassigned workspace needs info'),
 (6, 'Willow%',  'concession',              'needs_info',        250.00,           null,    'Willow $250 concession request, no approval: needs info'),
 (7, 'Willow%',  'missing_usage_invoice',   'needs_info',        null,             null,    'Willow no October usage invoice: needs info'),
 (8, 'Crescent%','15th_anchor_timing',      'valid_explanation', null,             null,    'Crescent Shore 15th-anchor valid'))
select ex.n, ex.description, ex.expected_class, f.class as actual_class, ex.expected_amount, f.amount as actual_amount, f.direction as actual_direction,
       case when f.class is not distinct from ex.expected_class and (ex.expected_amount is null or f.amount = ex.expected_amount)
                 and (ex.expected_direction is null or f.direction = ex.expected_direction) then 'MATCH' else 'DISAGREES' end as result
from ex left join calc.v_check_results r on r.check_code = ex.check_code and r.customer like ex.customer_like
left join calc.v_findings f on f.finding_id = r.check_code || ':' || coalesce(r.salesforce_account_id, 'workspace');

alter view calc.v_findings set (security_invoker = false);
do $$ declare s text; begin foreach s in array array['calc'] loop execute format('revoke all on all tables in schema %I from anon, authenticated', s); end loop; end $$;
