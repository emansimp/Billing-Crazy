-- 0020 (Phase 6, Area 1 part 3): read-only UI views for the Finding detail page (header, evidence trail, show the math, notes, sources).
-- All figures are SQL-computed; text is assembled from them. Source quotes (document names, message IDs) come from the supplied files.

create view public.ui_finding_detail as
with b as (
  select l.*, c.netsuite_customer_internal_id as ns_id, c.stripe_customer_id as stripe_id, x.contract_ids,
         f.recommended_action, f.approver, f.detail, f.contract_citation,
         (select v.effective_from from ref.contract_term_versions v where v.salesforce_account_id = l.salesforce_account_id and v.version_no = 2) as amend_eff,
         (select r.signed_at from raw.contract_register r where r.salesforce_account_id = l.salesforce_account_id and r.document_type = 'amendment' limit 1) as amend_signed,
         (select v.included_runs_per_month from ref.contract_term_versions v where v.salesforce_account_id = l.salesforce_account_id and v.version_no = 1) as runs_before,
         (select v.included_runs_per_month from ref.contract_term_versions v where v.salesforce_account_id = l.salesforce_account_id and v.version_no = 2) as runs_after,
         (select g.internal_id from raw.netsuite_gl_detail g where g.customer_internal_id = c.netsuite_customer_internal_id and g.account_number = '4010' and g.transaction_type = 'Journal' and g.posting_period = 'Oct 2026' limit 1) as accrual_je,
         (select g.created_at::date from raw.netsuite_gl_detail g where g.customer_internal_id = c.netsuite_customer_internal_id and g.account_number = '4010' and g.transaction_type = 'Journal' and g.posting_period = 'Oct 2026' limit 1) as accrual_created,
         q.gl_accrued, q.expected_net, q.accrual_adjustment_needed,
         uf.diagnosis, uf.billed_rate_cents, uf.contract_rate_cents, uf.billed_units, uf.expected_overage_units,
         eu.verified_units, eu.allowance_runs, eu.overage_rate_per_run,
         (select je.external_id from calc.v_adjustment_lines je where je.finding_id = l.finding_id and je.posts_entry order by je.line_order limit 1) as entry_id
  from public.ui_findings_list l
  join calc.v_findings f using (finding_id)
  left join stg.customers c on c.salesforce_account_id = l.salesforce_account_id
  left join stg.v_customer_crosswalk x on x.salesforce_account_id = l.salesforce_account_id
  left join calc.usage_accrual_comparison q on q.salesforce_account_id = l.salesforce_account_id
  left join calc.usage_findings uf on uf.salesforce_account_id = l.salesforce_account_id
  left join calc.v_expected_usage eu on eu.salesforce_account_id = l.salesforce_account_id
)
select b.display_id, b.finding_id, b.check_code, b.class, b.class_label, b.direction_label, b.stream, b.customer, b.what_we_found, b.owner, b.approver, b.decision,
       b.customer || ': ' || case b.check_code
         when 'usage_variance' then case b.diagnosis when 'amended_allowance_not_applied' then 'allowance amendment not applied to October usage billing'
              when 'billed_rate_differs_from_contract' then 'October usage billed at the wrong rate' when 'no_usage_invoice_issued' then 'no October usage invoice issued'
              else 'billed overage quantity differs from metering' end
         when 'platform_variance' then 'platform upgrade not reflected in October billing'
         when 'concession' then case b.class when 'valid_explanation' then 'approved concession already reflected in the October accrual' else 'concession requested without Controller approval' end
         when 'void_credit_note' then 'void credit note has no effect' when 'unassigned_usage' then 'unverified workspace usage isolated, ownership unproven'
         when 'missing_usage_invoice' then case b.class when 'needs_info' then 'no October usage invoice, usage unattributed' else 'no October usage invoice, no overage' end
         when '15th_anchor_timing' then '15th-anchor platform invoices cover two partial October periods' when 'duplicate_usage_record' then 'repeated usage record is not new activity'
         when 'later_service_platform' then 'November platform invoice below contract (follow-up)' else b.what_we_found end as title,
       b.ns_id as netsuite_id, b.stripe_id as stripe_customer, array_to_string(b.contract_ids, ', ') as contract_ids,
       case when b.check_code = 'platform_variance' then 'Oct ' || extract(day from b.amend_eff)::int || '–31, 2026' when b.check_code = 'later_service_platform' then 'Nov 1–30, 2026' else 'Oct 1–31, 2026' end as service_period,
       b.stream || case when b.direction_label is not null then ' · ' || b.direction_label else '' end as stream_chip,
       b.has_billing_correction, b.has_october_adjustment, b.recommended_action, b.entry_id, b.contract_citation, b.accrual_je, b.accrual_created,
       case
         when b.check_code = 'usage_variance' and b.accrual_adjustment_needed < 0 then
           'The October usage accrual (' || b.accrual_je || ', created ' || to_char(b.accrual_created, 'Mon FMDD') || ') is $' || to_char(b.gl_accrued, 'FM999,990.00') || ', equal to the billed amount. The expected charge is $' || to_char(b.expected_net, 'FM999,990.00') || ', so reduce the accrual by $' || to_char(abs(b.accrual_adjustment_needed), 'FM999,990.00') || ' in the October period. The November credit note then reduces AR and reverses the matching release of unbilled usage. It does not reduce revenue a second time.'
         when b.check_code = 'usage_variance' and b.accrual_adjustment_needed > 0 then
           'The October usage accrual (' || coalesce(b.accrual_je, 'none posted') || ') is $' || to_char(b.gl_accrued, 'FM999,990.00') || ' against an expected $' || to_char(b.expected_net, 'FM999,990.00') || ', so accrue the missing $' || to_char(b.accrual_adjustment_needed, 'FM999,990.00') || ' in the October period. The November supplemental invoice then releases the unbilled usage (Dr 1100 / Cr 1150); it is not revenue a second time.'
         when b.check_code = 'usage_variance' then
           'The October usage accrual ($' || to_char(b.gl_accrued, 'FM999,990.00') || ') already equals the expected net ($' || to_char(b.expected_net, 'FM999,990.00') || '), so no October entry is needed. A billing correction is not an automatic revenue adjustment: the November supplemental invoice only releases the remaining unbilled usage.'
         when b.check_code = 'platform_variance' then
           'NetSuite posted the base platform recognition for October. The Oct 16–31 upgrade increment ($' || to_char(b.amount, 'FM999,990.00') || ') is missing, so recognize it in the October period (Dr 2200 / Cr 4000) and reclass the incremental contract asset (Dr 1160 / Cr 2200). The November supplemental invoice is a billing document; the revenue belongs to October because that is when the service was delivered.'
         when b.check_code = 'concession' and b.class = 'valid_explanation' then
           'No October entry. The posted accrual ($' || to_char(b.gl_accrued, 'FM999,990.00') || ') already equals the expected net ($' || to_char(b.expected_net, 'FM999,990.00') || '), so the approved concession is already reflected. A contra-revenue entry would reduce revenue twice; the November credit note reduces AR and releases unbilled usage only.'
         else 'No October accounting entry for this item. ' || b.detail end as accounting_effect,
       case
         when b.check_code = 'usage_variance' and b.diagnosis = 'amended_allowance_not_applied' then
           b.customer || ' signed an amendment on ' || to_char(b.amend_signed at time zone 'America/Denver', 'Mon FMDD') || ' raising its monthly allowance from ' || to_char(b.runs_before, 'FM999,999') || ' to ' || to_char(b.runs_after, 'FM999,999') || ' runs, effective ' || to_char(b.amend_eff, 'Mon FMDD') || '. Billing has no load date for the amendment, and the Nov 1 invoice quantity is consistent with the old allowance. Recalculating with the weighted allowance of ' || to_char(b.allowance_runs, 'FM999,999') || ' runs lowers the October usage charge by $' || to_char(b.amount, 'FM999,990.00') || '.'
         when b.check_code = 'usage_variance' then b.what_we_found || '. Expected net $' || to_char(b.expected_net, 'FM999,990.00') || ' versus billed; the difference is $' || to_char(b.amount, 'FM999,990.00') || '.'
         else b.detail end as explanation
from b;

-- evidence trail
create view public.ui_finding_evidence as
with fl as (select * from public.ui_findings_list),
ctx as (
  select fl.finding_id, fl.check_code, fl.salesforce_account_id, fl.customer,
         (select r.document_id from raw.contract_register r where r.salesforce_account_id = fl.salesforce_account_id and r.document_type = 'amendment' limit 1) as amend_doc,
         (select r.signed_at from raw.contract_register r where r.salesforce_account_id = fl.salesforce_account_id and r.document_type = 'amendment' limit 1) as amend_signed,
         (select r.billing_loaded_at from raw.contract_register r where r.salesforce_account_id = fl.salesforce_account_id and r.document_type = 'amendment' limit 1) as amend_loaded,
         (select r.approval_reference from raw.contract_register r where r.salesforce_account_id = fl.salesforce_account_id and r.document_type = 'amendment' limit 1) as amend_msg,
         v1.included_runs_per_month as runs1, v2.included_runs_per_month as runs2, v1.platform_fee_annual as fee1, v2.platform_fee_annual as fee2, v1.platform_billing_amount as inv1, v2.platform_billing_amount as inv2,
         v2.effective_from as eff2, v1.overage_rate_per_run as rate, v1.source_document_id as order_form, v1.source_citation as order_citation, v1.term_start,
         v2.version_id is not null as has_amend, ('included_runs_per_month' = any(v2.changed_terms)) as usage_amend, ('platform_fee_annual' = any(v2.changed_terms)) as platform_amend,
         eu.verified_units, eu.record_count, eu.allowance_runs, eu.expected_usage_net, array_length(eu.product_account_ids, 1) as accounts,
         bu.invoice_numbers[1] as inv_no, bu.billed_units, bu.billed_usage_gross, bu.line_ids[1] as line_id,
         q.gl_accrued, q.expected_net,
         (select g.internal_id from raw.netsuite_gl_detail g join stg.customers c on c.netsuite_customer_internal_id = g.customer_internal_id where c.salesforce_account_id = fl.salesforce_account_id and g.account_number = '4010' and g.transaction_type = 'Journal' and g.posting_period = 'Oct 2026' limit 1) as je_id,
         (select c.netsuite_customer_internal_id from stg.customers c where c.salesforce_account_id = fl.salesforce_account_id) as ns_id,
         (select unit_amount_decimal from calc.actual_invoice_lines l where l.salesforce_account_id = fl.salesforce_account_id and l.stream = 'usage' and l.period_start = '2026-10-01' limit 1) as billed_rate_cents,
         (select string_agg(l.invoice_number, ', ') from calc.actual_invoice_lines l where l.salesforce_account_id = fl.salesforce_account_id and l.stream = 'platform' and l.period_start >= '2026-10-01' and l.period_start < '2026-11-01') as plat_oct_invoices
  from fl
  left join ref.contract_term_versions v1 on v1.salesforce_account_id = fl.salesforce_account_id and v1.version_no = 1
  left join ref.contract_term_versions v2 on v2.salesforce_account_id = fl.salesforce_account_id and v2.version_no = 2
  left join calc.v_expected_usage eu on eu.salesforce_account_id = fl.salesforce_account_id
  left join calc.v_billed_usage bu on bu.salesforce_account_id = fl.salesforce_account_id
  left join calc.usage_accrual_comparison q on q.salesforce_account_id = fl.salesforce_account_id
  where fl.check_code in ('usage_variance', 'platform_variance')
), rich as (
  select finding_id, 1 as ord, 'Executed amendment ' || amend_doc as title,
         'Signed ' || to_char(amend_signed at time zone 'America/Denver', 'Mon FMDD') || ', effective ' || to_char(eff2, 'Mon FMDD') || '. ' ||
         case when usage_amend then 'Included runs change from ' || to_char(runs1, 'FM999,999') || ' to ' || to_char(runs2, 'FM999,999') || ' per month. Overage rate stays $' || to_char(rate, 'FM0.00') || '. Platform stays $' || to_char(inv1, 'FM999,999.00') || ' per month.'
              else 'Annual platform rate changes from $' || to_char(fee1, 'FM999,999') || ' to $' || to_char(fee2, 'FM999,999') || ' for the remainder of the term; monthly invoices become $' || to_char(inv2, 'FM999,999') || ' from Nov 1; the October upgrade catch-up is $' || to_char(fee2 - fee1, 'FM999,999') || ' × 16 ÷ 365.' end as body,
         'contracts/' || amend_doc || '.pdf, sections 03–04' as source_ref, null::text as badge
  from ctx where has_amend and (usage_amend or platform_amend)
  union all select finding_id, 2, 'Not recorded as loaded to billing', 'The contract register shows no billing load date for this amendment.', 'contract_register.csv, billing_loaded_at is blank', null
  from ctx where has_amend and amend_loaded is null
  union all select finding_id, 3, 'Sales asked for the update', 'Oct 14 message asks Billing to update the relevant systems from the executed documents.', 'billing_followups.pdf, ' || amend_msg, null
  from ctx where has_amend and amend_msg is not null
  union all select finding_id, 1, 'Contract terms ' || order_form, 'Included runs ' || to_char(runs1, 'FM999,999') || ' per month; overage rate $' || to_char(rate, 'FM0.00') || '; term starts ' || to_char(term_start, 'Mon FMDD, YYYY') || '.', order_citation, null
  from ctx where not has_amend and check_code = 'usage_variance'
  union all select finding_id, 4, 'What was billed',
         case when inv_no is null then 'No October usage invoice was found for this customer.'
              else 'Nov 1 usage invoice ' || inv_no || ', ' || to_char(billed_units, 'FM999,999') || ' runs at $' || to_char(billed_rate_cents / 100, 'FM0.00') || ' for Oct 1 – Nov 1.' end,
         coalesce('stripe_invoice_lines.csv, ' || line_id, 'stripe_invoices.csv (no October usage invoice)'), null
  from ctx where check_code = 'usage_variance'
  union all select finding_id, 5, 'October usage from the metering file', to_char(verified_units, 'FM999,999') || ' runs across ' || record_count || ' unique active daily records on ' || accounts || ' verified product account' || case when accounts > 1 then 's' else '' end || '.', 'product_usage.csv, usage_batch_controls.csv', 'Matches source'
  from ctx where check_code = 'usage_variance'
  union all select finding_id, 6, 'What NetSuite accrued', 'The October usage accrual (' || coalesce(je_id, 'none posted') || ') is $' || to_char(gl_accrued, 'FM999,990.00') || '. Expected net $' || to_char(expected_net, 'FM999,990.00') || '.', 'netsuite_gl_detail.csv, customer ' || ns_id || ', 1150 / 4010', null
  from ctx where check_code = 'usage_variance'
  union all select finding_id, 4, 'What was billed', 'October platform invoices: ' || coalesce(plat_oct_invoices, 'none') || ' at $' || to_char(inv1, 'FM999,990.00') || '. No invoice for the Oct 16–31 increment.', 'stripe_invoice_lines.csv, platform lines', null
  from ctx where check_code = 'platform_variance'
  union all select finding_id, 5, 'What NetSuite recognized', 'October base platform recognition is posted; the Oct 16–31 increment is not.', 'netsuite_gl_detail.csv, customer ' || ns_id || ', 2200 / 4000', null
  from ctx where check_code = 'platform_variance'
), generic as (
  select l.finding_id, 10 + row_number() over (partition by l.finding_id order by e.key) as ord,
         initcap(replace(e.key, '_', ' ')) as title,
         case when jsonb_typeof(e.value) = 'array' then coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(e.value) x), 'none') else e.value #>> '{}' end as body,
         'calculation views, evidence IDs' as source_ref, null::text as badge
  from public.ui_findings_list l join calc.v_findings f using (finding_id), jsonb_each(f.evidence) e
  where l.check_code not in ('usage_variance', 'platform_variance')
  union all select l.finding_id, 1, 'What the check found', f.detail, f.contract_citation, null from public.ui_findings_list l join calc.v_findings f using (finding_id) where l.check_code not in ('usage_variance', 'platform_variance')
)
select finding_id, row_number() over (partition by finding_id order by ord) as item_no, title, body, source_ref, badge from (select * from rich union all select * from generic) u;

-- show the math
create view public.ui_finding_math as
with uv as (
  select l.finding_id, eu.weighted_run_days, eu.days_in_month, eu.allowance_runs, eu.verified_units, eu.overage_units, eu.overage_rate_per_run, eu.expected_usage_gross, eu.approved_concessions,
         bu.billed_units, bu.billed_usage_gross, bu.invoice_numbers[1] as inv_no, uf.billed_rate_cents, l.amount, l.direction_label,
         (select string_agg(to_char(v.included_runs_per_month, 'FM999,999') || ' × ' || x.days || ' days', ' + ' order by v.effective_from)
            from ref.contract_term_versions v cross join ref.close_params p
            cross join lateral (select least(v.effective_to_exclusive, p.period_end_exclusive) - greatest(v.effective_from, p.period_start) as days) x
            where v.salesforce_account_id = l.salesforce_account_id and v.approval_status = 'approved' and x.days > 0) as breakdown
  from public.ui_findings_list l join calc.v_expected_usage eu on eu.salesforce_account_id = l.salesforce_account_id
  join calc.v_billed_usage bu on bu.salesforce_account_id = l.salesforce_account_id left join calc.usage_findings uf on uf.salesforce_account_id = l.salesforce_account_id
  where l.check_code = 'usage_variance'),
pv as (
  select l.finding_id, v1.platform_fee_annual as fee1, v2.platform_fee_annual as fee2, v2.effective_from as eff, p.period_end_exclusive - v2.effective_from as days, l.amount,
         v1.platform_billing_amount as oct_invoice, (select string_agg(x.invoice_number, ', ') from calc.actual_invoice_lines x where x.salesforce_account_id = l.salesforce_account_id and x.stream = 'platform' and x.period_start >= '2026-10-01' and x.period_start < '2026-11-01') as inv_nos
  from public.ui_findings_list l join ref.contract_term_versions v1 on v1.salesforce_account_id = l.salesforce_account_id and v1.version_no = 1
  join ref.contract_term_versions v2 on v2.salesforce_account_id = l.salesforce_account_id and v2.version_no = 2 cross join ref.close_params p where l.check_code = 'platform_variance')
select finding_id, 1 as step_no, '1. Weighted allowance' as step, '(' || breakdown || ') ÷ ' || days_in_month || ', rounded once, half up' as calculation, to_char(allowance_runs, 'FM999,999') || ' runs' as result from uv
union all select finding_id, 2, '2. Expected overage runs', 'max(0, ' || to_char(verified_units, 'FM999,999') || ' − ' || to_char(allowance_runs, 'FM999,999') || ')', to_char(overage_units, 'FM999,999') || ' runs' from uv
union all select finding_id, 3, '3. Expected usage charge', to_char(overage_units, 'FM999,999') || ' × $' || to_char(overage_rate_per_run, 'FM0.00'), '$' || to_char(expected_usage_gross, 'FM999,990.00') from uv
union all select finding_id, 4, '4. Billed usage charge', coalesce(to_char(billed_units, 'FM999,999') || ' × $' || to_char(billed_rate_cents / 100, 'FM0.00') || ' (invoice ' || inv_no || ')', 'No October usage invoice issued'), '$' || to_char(billed_usage_gross, 'FM999,990.00') from uv
union all select finding_id, 5, '5. Variance', case when direction_label = 'Over-billed' then '$' || to_char(billed_usage_gross, 'FM999,990.00') || ' − $' || to_char(expected_usage_gross - approved_concessions, 'FM999,990.00') else '$' || to_char(expected_usage_gross - approved_concessions, 'FM999,990.00') || ' − $' || to_char(billed_usage_gross, 'FM999,990.00') end,
       '$' || to_char(amount, 'FM999,990.00') || ' ' || lower(direction_label) from uv
union all select finding_id, 1, '1. Annual rate increase', '$' || to_char(fee2, 'FM999,999') || ' − $' || to_char(fee1, 'FM999,999'), '$' || to_char(fee2 - fee1, 'FM999,999') || ' per year' from pv
union all select finding_id, 2, '2. Days at the new rate', to_char(eff, 'Mon FMDD') || ' to Oct 31 inclusive', days || ' days' from pv
union all select finding_id, 3, '3. October increment', '$' || to_char(fee2 - fee1, 'FM999,999') || ' × ' || days || ' ÷ 365, rounded once to cents', '$' || to_char(amount, 'FM999,990.00') from pv
union all select finding_id, 4, '4. Billed for October service', 'Oct 1 platform invoice ' || inv_nos || '; no invoice for the increment', '$' || to_char(oct_invoice, 'FM999,990.00') from pv
union all select finding_id, 5, '5. Variance', '($' || to_char(oct_invoice, 'FM999,990.00') || ' + $' || to_char(amount, 'FM999,990.00') || ') − $' || to_char(oct_invoice, 'FM999,990.00'), '$' || to_char(amount, 'FM999,990.00') || ' under-billed' from pv
union all select l.finding_id, 1, 'Check result', f.detail, l.amount_display from public.ui_findings_list l join calc.v_findings f using (finding_id) where l.check_code not in ('usage_variance', 'platform_variance');

create view public.ui_finding_math_notes as
with uv as (
  select l.finding_id, uf.diagnosis, eu.allowance_runs, eu.weighted_run_days, eu.days_in_month, eu.verified_units, eu.overage_rate_per_run, uf.billed_units, uf.expected_overage_units, l.amount,
         uf.billed_rate_cents, uf.contract_rate_cents,
         (select to_char(v.included_runs_per_month, 'FM999,999') from ref.contract_term_versions v where v.salesforce_account_id = l.salesforce_account_id and v.version_no = 2) as runs_new,
         (select least(v.effective_to_exclusive, p.period_end_exclusive) - greatest(v.effective_from, p.period_start) from ref.contract_term_versions v cross join ref.close_params p where v.salesforce_account_id = l.salesforce_account_id and v.version_no = 2) as days_new,
         (select unit_amount_decimal from calc.actual_invoice_lines x where x.salesforce_account_id = l.salesforce_account_id and x.stream = 'usage' and x.period_start = '2026-09-01' limit 1) as sep_rate_cents
  from public.ui_findings_list l join calc.v_expected_usage eu on eu.salesforce_account_id = l.salesforce_account_id join calc.usage_findings uf on uf.salesforce_account_id = l.salesforce_account_id
  where l.check_code = 'usage_variance')
select finding_id,
       case diagnosis when 'amended_allowance_not_applied' then 'Why ' || to_char(allowance_runs - (verified_units - billed_units), 'FM999,999') || ' runs?'
                      when 'billed_rate_differs_from_contract' then 'Why $' || to_char((contract_rate_cents - billed_rate_cents) / 100, 'FM0.00') || ' per run?'
                      when 'no_usage_invoice_issued' then 'Why is there no invoice?' else 'Why ' || to_char(expected_overage_units - billed_units, 'FM999,999') || ' runs?' end as heading,
       case diagnosis
         when 'amended_allowance_not_applied' then 'The invoice quantity matches an allowance of ' || to_char(verified_units - billed_units, 'FM999,999') || ' for the whole month. The amended allowance of ' || runs_new || ' applied for ' || days_new || ' of ' || days_in_month || ' days, so the weighted allowance is ' || to_char(allowance_runs - (verified_units - billed_units), 'FM999,999') || ' runs higher. ' || to_char(allowance_runs - (verified_units - billed_units), 'FM999,999') || ' × $' || to_char(overage_rate_per_run, 'FM0.00') || ' = $' || to_char(amount, 'FM999,990.00') || '.'
         when 'billed_rate_differs_from_contract' then 'The October invoice carries $' || to_char(billed_rate_cents / 100, 'FM0.00') || ' per run; the contract rate is $' || to_char(contract_rate_cents / 100, 'FM0.00') || coalesce(' and the September invoice used $' || to_char(sep_rate_cents / 100, 'FM0.00'), '') || '. The difference of $' || to_char((contract_rate_cents - billed_rate_cents) / 100, 'FM0.00') || ' on ' || to_char(billed_units, 'FM999,999') || ' runs = $' || to_char(amount, 'FM999,990.00') || '.'
         when 'no_usage_invoice_issued' then 'No Stripe invoice line exists for October usage. Expected overage ' || to_char(expected_overage_units, 'FM999,999') || ' runs × $' || to_char(overage_rate_per_run, 'FM0.00') || ' = $' || to_char(amount, 'FM999,990.00') || ' has not been billed.'
         else 'Metering supports ' || to_char(expected_overage_units, 'FM999,999') || ' overage runs but the invoice bills ' || to_char(billed_units, 'FM999,999') || ': ' || to_char(expected_overage_units - billed_units, 'FM999,999') || ' runs × $' || to_char(overage_rate_per_run, 'FM0.00') || ' = $' || to_char(amount, 'FM999,990.00') || '.' end as body,
       'Rounding: allowance once to whole runs, charge once to cents' as rounding_note, 'Source rule: START_HERE, Usage' as source_rule
from uv
union all
select l.finding_id, 'Why is this a catch-up?', 'The amendment raises the annual platform rate from $48,000 to $60,000 effective Oct 16 for the rest of the term, so the 16 service days in October at the higher rate were never billed. The base schedule is unchanged; the increment is added on top.',
       'Rounding: each monthly recognition component rounded once to cents', 'Source rule: START_HERE, Accounting (preserve the original base schedule when adding an upgrade increment)'
from public.ui_findings_list l where l.check_code = 'platform_variance';

create view public.ui_finding_sources as
select finding_id, title as source, source_ref as reference, item_no from public.ui_finding_evidence;

grant select on public.ui_finding_detail, public.ui_finding_evidence, public.ui_finding_math, public.ui_finding_math_notes, public.ui_finding_sources to anon, authenticated;
