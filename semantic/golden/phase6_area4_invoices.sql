-- Phase 6 Area 4 golden tests: Invoices (register, detail, coverage timeline).
-- Hand values: 124 invoices = 30 September (paid) + 94 issued Oct 1-Nov 1 (open); 2 credit notes (1 issued Zephyr, 1 void Alder).
--   Covering October: platform 10 annual + 2 (Sep 15 anchor) + 18 monthly Oct 1 + 2 (Oct 15 anchor) = 32 ; usage Nov 1 invoices for October service = 27 ; total 59.
--   Alder annual: 24,000 x 31 / 365 = 2,038.36 allocated to October. Willow/Crescent Sep 15 invoice covers Oct 1-14, Oct 15 invoice covers Oct 15-31.
--   Timeline range Sep 1 - Nov 30 = 91 days: October starts day 30 -> 30/91 = 32.967 %, width 31/91 = 34.066 %, cutoff Nov 11 = day 71 -> 78.022 %, Nov 1 = day 61 -> 67.033 %,
--   Zephyr credit note Nov 4 = day 64 -> 70.330 %.
with inv as materialized (select * from public.ui_invoices), det as materialized (select * from public.ui_invoice_detail), cov as materialized (select * from public.ui_coverage),
     meta as materialized (select * from public.ui_coverage_meta), sm as materialized (select * from public.ui_invoices_summary)
select test_name, expected, actual, (expected = actual) as pass from (
  select 'register: invoices / paid / open' as test_name, '124/30/94' as expected, (select invoices || '/' || paid || '/' || open from sm) as actual
  union all select 'register: credit notes total / issued / void', '2/1/1', (select credit_notes || '/' || credit_notes_issued || '/' || credit_notes_void from sm)
  union all select 'register: invoices covering October', '59', (select covering_october from sm)::text
  union all select 'covering October by stream (platform/usage)', '32/27', (select count(*) filter (where stream = 'platform') || '/' || count(*) filter (where stream = 'usage') from inv where covers_october)
  union all select 'every invoice is in the register exactly once (rows = distinct ids)', '124/124', (select count(*) || '/' || count(distinct invoice_id) from inv)
  union all select 'register amounts equal Stripe invoice totals (rows differing)', '0', (select count(*) from inv i join raw.stripe_invoices s on s.id = i.invoice_id where i.amount <> s.total::numeric / 100)::text
  union all select 'Alder annual role', 'Prepaid, $2,038.36 allocated to October', (select role_in_review from inv where customer = 'Alder Fieldworks' and type = 'Platform, annual')
  union all select 'Alder Nov 1 usage invoice carries the void credit note, no effect', 'CN-186097-20261102, $50.00, void, no effect', (select credit_note_text from inv where invoice_number = 'RC-261101-186097-U')
  union all select 'Zephyr Nov 1 usage invoice carries the issued credit note', 'CN-148565-20261104, $100.00, issued Nov 4', (select credit_note_text from inv where invoice_number = 'RC-261101-148565-U')
  union all select '15th anchor roles (Willow Sep 15 / Oct 15)', 'Covers Oct 1–14, day-based allocation|Covers Oct 15–31, day-based allocation', (select string_agg(role_in_review, '|' order by issued) from inv where customer = 'Willow Passage' and stream = 'platform')
  union all select 'Cedar Oct usage invoice role and finding', 'October usage billing/F-01', (select role_in_review || '/' || finding_ids from inv where invoice_number = 'RC-261101-639373-U')
  union all select 'Meridian: F-02 on the Oct invoice, F-09 on the Nov invoice (not mixed)', 'F-02|F-09', (select string_agg(finding_ids, '|' order by issued) from inv where customer = 'Meridian Process Systems' and stream = 'platform' and finding_ids is not null)
  union all select 'September usage invoices are release-only (29: every customer with a September overage; Willow had none)', '29', (select count(*) from inv where stream = 'usage' and issued = '2026-10-01' and role_in_review like 'Releases Sep 30 accrual of $%')::text
  union all select 'Cedar usage invoice detail: qty / unit / total', '28470/0.40/11388.00', (select quantity || '/' || round(unit_price, 2) || '/' || round(invoice_total, 2) from det where invoice_number = 'RC-261101-639373-U')
  union all select 'Cedar detail: expected / over-billed', '8291.20/3096.80', (select round(expected_amount, 2) || '/' || round(over_billed, 2) from det where invoice_number = 'RC-261101-639373-U')
  union all select 'Cedar detail: NetSuite posting', 'JE-2f793a7d4c77e5/Dr 1100 11,388.00/Cr 1150 11,388.00', (select journal || '/' || dr_text || '/' || cr_text from det where invoice_number = 'RC-261101-639373-U')
  union all select 'Cedar detail: proposed correction', 'CORR-01/Credit note/3096.80', (select correction_ref || '/' || correction_document || '/' || round(correction_amount, 2) from det where invoice_number = 'RC-261101-639373-U')
  union all select 'Cedar detail: Stripe id and issue time', 'in_c0e6eb901e48cd/Issued Nov 1, 2026, 9:00 AM MT', (select invoice_id || '/' || issued_label from det where invoice_number = 'RC-261101-639373-U')
  union all select 'every in-period invoice has a NetSuite posting; September ones are outside the extract', '94/30', (select count(*) filter (where not outside_gl_extract) || '/' || count(*) filter (where outside_gl_extract) from det)
  union all select 'Meridian Oct platform invoice carries the proposed catch-up', 'CORR-02/Supplemental invoice/526.03', (select correction_ref || '/' || correction_document || '/' || round(correction_amount, 2) from det where invoice_number = 'RC-261001-335780-P')
  union all select 'timeline meta: October position', '32.967/34.066', (select october_left_pct || '/' || october_width_pct from meta)
  union all select 'timeline meta: cutoff Nov 11 and November start', '78.022/67.033/Nov 11', (select cutoff_pct || '/' || november_left_pct || '/' || cutoff_label from meta)
  union all select 'Alder annual bar spans the whole view and continues past it', '0.000/100.000/true', (select left_pct || '/' || width_pct || '/' || continues_past from cov where customer = 'Alder Fieldworks' and bar_kind = 'platform')
  union all select 'Alder annual label shows the allocation arithmetic', 'Sep 1, 2026 to Sep 1, 2027 · $24,000.00 prepaid · October allocation $2,038.36 (24,000 × 31 ÷ 365) · continues past this view', (select label from cov where customer = 'Alder Fieldworks' and bar_kind = 'platform')
  union all select 'Cedar October platform bar position', '32.967/34.066', (select left_pct || '/' || width_pct from cov where customer = 'Cedar Harbor Labs' and bar_kind = 'platform' and label like 'Oct ·%')
  union all select 'Meridian November bar says the amendment sets 5,000', 'Nov · $4,000.00 · later service, amendment says $5,000.00', (select label from cov where customer = 'Meridian Process Systems' and bar_kind = 'platform' and label like 'Nov ·%')
  union all select 'Meridian October bar marks the upgrade', 'Oct · $4,000.00 · upgrade Oct 16', (select label from cov where customer = 'Meridian Process Systems' and bar_kind = 'platform' and label like 'Oct ·%')
  union all select 'Zephyr credit note marker', 'Credit note Nov 4, $100.00/70.330', (select label || '/' || left_pct from cov where customer = 'Zephyr Grove' and bar_kind = 'credit_note')
  union all select 'Alder void credit note marker', 'Credit note Nov 2, $50.00, void, no effect', (select label from cov where customer = 'Alder Fieldworks' and bar_kind = 'credit_note')
  union all select 'September usage bar (Cedar) invoiced Oct 1', 'Sep usage · invoiced Oct 1 · $12,243.20', (select label from cov where customer = 'Cedar Harbor Labs' and bar_kind = 'usage' and label like 'Sep usage%')
  union all select '15th anchor platform bars (Willow: Sep 15 - Oct 15 paid, Oct 15 - Nov 15)', 'Sep 15 – Oct 15 · $5,000.00 · paid|Oct 15 – Nov 15 · $5,000.00', (select string_agg(label, '|' order by left_pct) from cov where customer = 'Willow Passage' and bar_kind = 'platform')
  union all select 'bar positions stay inside the view (left + width <= 100)', '0', (select count(*) from cov where bar_kind <> 'credit_note' and left_pct + width_pct > 100.001)::text
  union all select 'coverage covers all 30 customers', '30', (select count(distinct customer) from cov where bar_kind <> 'credit_note')::text
  union all select 'snapshots fresh: register and coverage (rows differing from the live views)', '0',
        (select (select count(*) from ((select * from public.ui_invoices except select * from public.ui_invoices_live) union all (select * from public.ui_invoices_live except select * from public.ui_invoices)) a)
              + (select count(*) from ((select * from public.ui_coverage except select * from public.ui_coverage_live) union all (select * from public.ui_coverage_live except select * from public.ui_coverage)) b))::text
) t;
