-- Phase 3 golden tests. Every expected value is hand-calculated below (arithmetic in comments) and was also recomputed independently
-- in Python from the PDFs/CSVs (Decimal, half-up) before being written here. Amounts compared as 2-decimal text.
--
-- CEDAR HARBOR usage, October (31 days). Amendment effective Oct 16 (AM-OF-2026-157): allowance 30,000 -> 45,000.
--   weighted allowance = (30,000 x 15 days + 45,000 x 16 days) / 31 = (450,000 + 720,000) / 31 = 1,170,000 / 31 = 37,741.9355 -> 37,742 (rounded once, half up)
--   verified October runs (31 records) = 58,470        overage units = 58,470 - 37,742 = 20,728
--   expected usage = 20,728 x $0.40 = $8,291.20        billed (RC-261101-639373-U, 28,470 units x 40.00c) = $11,388.00  -> over-billed $3,096.80
-- MERIDIAN catch-up (required, owner decision 2026-11-23): (60,000 - 48,000) x 16 / 365 = 12,000 x 16 / 365 = 192,000 / 365 = 526.0274 -> $526.03
--   October platform revenue, base + increment (START_HERE: preserve original base schedule):
--   base = 48,000 x 31 / 365 = 4,076.7123 -> 4,076.71 ; increment = 526.0274 -> 526.03 ; total 4,602.74
--   cross-check, split by version: 48,000 x 15 / 365 = 1,972.6027 -> 1,972.60 ; 60,000 x 16 / 365 = 2,630.1370 -> 2,630.14 ; sum 4,602.74
-- ALDER annual $24,000 prepaid Sep 1 (period Sep 1 2026 - Sep 1 2027 = 365 days): no platform invoice in October -> expected to bill 0.
--   October revenue = 24,000 x 31 / 365 = 2,038.3562 -> 2,038.36 ; the annual invoice allocated by days to October = 24,000 x 31 / 365 = 2,038.36
--   Void credit cn_82a7ddd6e88e69 ($50.00) has NO effect: Oct usage billed gross 1,575.76, issued credits 0, net 1,575.76; the $50.00 is listed as ignored.
-- ZEPHYR: expected gross = 19,052 x $0.05 = $952.60 ; Controller-approved concession (MSG-2026-109) $100.00 -> net $852.60
--   billed gross $952.60 ; credit note cn_85bf669490fd97 ISSUED 2026-11-04 for $100.00 -> billed net $852.60 (concession applied once)
-- WILLOW: $250 concession request (MSG-2026-132) is unapproved -> applies nothing; no verified account -> usage unknown, not zero.
-- CRESCENT SHORE (15th anchor, $60,000/yr, $5,000/mo, term starts Sep 15): October revenue = 60,000 x 31 / 365 = 5,095.8904 -> 5,095.89
--   invoice Sep 15 covers Sep 15 - Oct 15 (30 days) -> Oct 1-14 = 14 days: 5,000 x 14 / 30 = 2,333.33
--   invoice Oct 15 covers Oct 15 - Nov 15 (31 days) -> Oct 15-31 = 17 days: 5,000 x 17 / 31 = 2,741.94 ; allocated total 5,075.27 (not equal to revenue 5,095.89)
--   issued in October (Oct 15): $5,000.00 expected = billed
-- TOTALS (independent): platform revenue base 93,764.36 + increment 526.03 = 94,290.39 ; platform to bill in Oct = 62,000 + 10,000 + 526.03 = 72,526.03 vs billed 72,000.00
--   usage gross 78,044.60 - 100.00 approved = 77,944.60 expected net ; billed gross 74,831.90 - 100.00 issued credit = 74,731.90 ; under 6,309.50 ; over 3,096.80
select test_name, expected, actual, (expected = actual) as pass from (
  select 'Cedar: weighted allowance (rounded once)' as test_name, '37742' as expected, (select allowance_runs::text from calc.v_expected_usage where account_name like 'Cedar%') as actual
  union all select 'Cedar: unrounded weighted allowance (4dp)', '37741.9355', (select round(allowance_unrounded, 4)::text from calc.v_expected_usage where account_name like 'Cedar%')
  union all select 'Cedar: weighted run-days', '1170000', (select weighted_run_days::text from calc.v_expected_usage where account_name like 'Cedar%')
  union all select 'Cedar: verified runs', '58470', (select verified_units::text from calc.v_expected_usage where account_name like 'Cedar%')
  union all select 'Cedar: overage units', '20728', (select overage_units::text from calc.v_expected_usage where account_name like 'Cedar%')
  union all select 'Cedar: expected usage', '8291.20', (select round(expected_usage_gross, 2)::text from calc.v_expected_usage where account_name like 'Cedar%')
  union all select 'Cedar: billed usage', '11388.00', (select round(billed_usage_gross, 2)::text from calc.v_billed_usage where account_name like 'Cedar%')
  union all select 'Cedar: over-billed', '3096.80', (select round(usage_over_billed, 2)::text from calc.v_expected_vs_billed where account_name like 'Cedar%')
  union all select 'Meridian: catch-up expected invoice amount', '526.03', (select round(expected_amount, 2)::text from calc.v_expected_platform_invoices i join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%' and charge_kind = 'upgrade_catch_up')
  union all select 'Meridian: catch-up period (Oct 16 - Nov 1)', '2026-10-16/2026-11-01', (select period_start || '/' || period_end_exclusive from calc.v_expected_platform_invoices i join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%' and charge_kind = 'upgrade_catch_up')
  union all select 'Meridian: base revenue', '4076.71', (select base_revenue::text from calc.v_expected_platform_revenue where account_name like 'Meridian%')
  union all select 'Meridian: increment revenue', '526.03', (select increment_revenue::text from calc.v_expected_platform_revenue where account_name like 'Meridian%')
  union all select 'Meridian: October platform revenue', '4602.74', (select expected_revenue::text from calc.v_expected_platform_revenue where account_name like 'Meridian%')
  union all select 'Meridian: split-by-version revenue agrees', '4602.74', (select version_split_revenue::text from calc.v_expected_platform_revenue where account_name like 'Meridian%')
  union all select 'Meridian: Oct 1 invoice expected at v1 amount', '4000.00', (select round(expected_amount, 2)::text from calc.v_expected_platform_invoices i join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%' and invoice_date = '2026-10-01')
  union all select 'Meridian: Nov 1 invoice expected at v2 amount (later service)', '5000.00', (select round(expected_amount, 2)::text from calc.v_expected_platform_invoices i join stg.customers c using (salesforce_account_id) where c.account_name like 'Meridian%' and invoice_date = '2026-11-01')
  union all select 'Alder: October platform to bill (annual prepaid Sep 1)', '0.00', (select round(expected_to_bill_for_period, 2)::text from calc.v_expected_platform where account_name like 'Alder%')
  union all select 'Alder: October platform revenue', '2038.36', (select expected_revenue::text from calc.v_expected_platform where account_name like 'Alder%')
  union all select 'Alder: annual invoice allocated to October', '2038.36', (select round(expected_invoices_allocated_to_period, 2)::text from calc.v_expected_platform where account_name like 'Alder%')
  union all select 'Alder: October usage billed gross', '1575.76', (select round(billed_usage_gross, 2)::text from calc.v_billed_usage where account_name like 'Alder%')
  union all select 'Alder: issued credits (void $50 has no effect)', '0.00', (select round(credits_issued, 2)::text from calc.v_billed_usage where account_name like 'Alder%')
  union all select 'Alder: void credit listed as ignored', '50.00', (select round(void_credits_ignored, 2)::text from calc.v_billed_usage where account_name like 'Alder%')
  union all select 'Alder: October usage billed net', '1575.76', (select round(billed_usage_net, 2)::text from calc.v_billed_usage where account_name like 'Alder%')
  union all select 'Alder: usage over/under', '0.00/0.00', (select round(usage_under_billed, 2) || '/' || round(usage_over_billed, 2) from calc.v_expected_vs_billed where account_name like 'Alder%')
  union all select 'Zephyr: expected gross', '952.60', (select expected_usage_gross::text from calc.v_expected_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: approved concession', '100.00', (select approved_concessions::text from calc.v_expected_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: expected net', '852.60', (select expected_usage_net::text from calc.v_expected_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: billed gross', '952.60', (select round(billed_usage_gross, 2)::text from calc.v_billed_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: issued credit', '100.00', (select round(credits_issued, 2)::text from calc.v_billed_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: credit note issue date', '2026-11-04', (select first_credit_date::text from calc.v_billed_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: billed net', '852.60', (select round(billed_usage_net, 2)::text from calc.v_billed_usage where account_name like 'Zephyr%')
  union all select 'Zephyr: no second concession (over/under)', '0.00/0.00', (select round(usage_under_billed, 2) || '/' || round(usage_over_billed, 2) from calc.v_expected_vs_billed where account_name like 'Zephyr%')
  union all select 'Willow: unapproved request authorizes nothing (expected net)', '0.00', (select expected_usage_net::text from calc.v_expected_usage where account_name like 'Willow%')
  union all select 'Willow: unapproved request recorded, not applied', '250.00', (select unapproved_requests_not_applied::text from calc.v_expected_usage where account_name like 'Willow%')
  union all select 'Willow: usage attribution', 'no_verified_product_account_usage', (select attribution_status from calc.v_expected_usage where account_name like 'Willow%')
  union all select '15th anchor Crescent: October revenue', '5095.89', (select expected_revenue::text from calc.v_expected_platform where account_name like 'Crescent%')
  union all select '15th anchor Crescent: Sep-15 invoice allocated to Oct (14/30)', '2333.33', (select allocated_to_period::text from calc.v_expected_platform_invoices i join stg.customers c using (salesforce_account_id) where c.account_name like 'Crescent%' and invoice_date = '2026-09-15')
  union all select '15th anchor Crescent: Oct-15 invoice allocated to Oct (17/31)', '2741.94', (select allocated_to_period::text from calc.v_expected_platform_invoices i join stg.customers c using (salesforce_account_id) where c.account_name like 'Crescent%' and invoice_date = '2026-10-15')
  union all select '15th anchor Crescent: issued in October expected', '5000.00', (select round(expected_to_bill_for_period, 2)::text from calc.v_expected_platform where account_name like 'Crescent%')
  union all select '15th anchor Crescent: issued in October billed', '5000.00', (select round(billed_invoiced_in_period, 2)::text from calc.v_billed_platform where account_name like 'Crescent%')
  union all select '15th anchor customers flagged', '2', (select count(*) from calc.v_expected_platform where is_15th_anchor)::text
  union all select 'customers in expected-vs-billed', '30', (select count(*) from calc.v_expected_vs_billed)::text
  union all select 'every invoice line maps to platform or usage', '0', (select count(*) from calc.v_invoice_line_stream_check where stream = 'other')::text
  union all select 'no rate change inside the month', '0', (select count(*) from calc.v_expected_usage where rate_changed_in_month)::text
  union all select 'TOTAL platform revenue expected (base + increment)', '94290.39', (select round(sum(expected_revenue), 2)::text from calc.v_expected_platform)
  union all select 'TOTAL platform expected to bill (invoice basis)', '72526.03', (select round(sum(platform_expected_to_bill), 2)::text from calc.v_expected_vs_billed)
  union all select 'TOTAL platform billed issued in October', '72000.00', (select round(sum(platform_billed_in_period), 2)::text from calc.v_expected_vs_billed)
  union all select 'TOTAL platform billed allocated to October', '92534.14', (select round(sum(platform_billed_allocated_to_period), 2)::text from calc.v_expected_vs_billed)
  union all select 'TOTAL usage expected gross', '78044.60', (select round(sum(expected_usage_gross), 2)::text from calc.v_expected_usage)
  union all select 'TOTAL usage expected net', '77944.60', (select round(sum(usage_expected_net), 2)::text from calc.v_expected_vs_billed)
  union all select 'TOTAL usage billed gross', '74831.90', (select round(sum(billed_usage_gross), 2)::text from calc.v_billed_usage)
  union all select 'TOTAL usage billed net', '74731.90', (select round(sum(usage_billed_net), 2)::text from calc.v_expected_vs_billed)
  union all select 'TOTAL usage under-billed', '6309.50', (select round(sum(usage_under_billed), 2)::text from calc.v_expected_vs_billed)
  union all select 'TOTAL usage over-billed', '3096.80', (select round(sum(usage_over_billed), 2)::text from calc.v_expected_vs_billed)
  union all select 'customers with a platform difference (Meridian only)', '1', (select count(*) from calc.v_expected_vs_billed where platform_under_billed <> 0 or platform_over_billed <> 0)::text
  union all select 'customers with a usage difference', '4', (select count(*) from calc.v_expected_vs_billed where usage_under_billed <> 0 or usage_over_billed <> 0)::text
) t;
