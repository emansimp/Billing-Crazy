# October accounting entries: policy and rules (v1)

Source: START_HERE.pdf p2-3 (ACCOUNTING, CREDITS, APPROVAL AND DATES) and the Journal entries mockups. Proposals only; nothing is posted or sent to NetSuite.

## When an entry exists
A billing correction is **not** an automatic revenue adjustment. An October entry is proposed only where the October **accrual or recognition itself**
differs from the contract-supported amount (`calc.usage_accrual_comparison`, `calc.platform_recognition_oct`):
| Situation | October entry | November billing document |
|---|---|---|
| Usage over-billed **and** accrued (Cedar Harbor) | reduce the accrual: Dr 4010 / Cr 1150 | linked credit note |
| Usage under-billed and under-accrued (Juniper Signal, Yarrow) | accrue missed revenue: Dr 1150 / Cr 4010 | supplemental invoice |
| Usage under-billed but accrual already right (Beacon Marsh) | **none** | supplemental invoice |
| Platform under-billed from an amendment (Meridian) | recognize the October true-up: Dr 2200 / Cr 4000, plus **incremental** reclass Dr 1160 / Cr 2200 | supplemental invoice |
| Approved concession already in the accrual (Zephyr Grove) | **none** (an entry would reduce revenue twice) | credit note already issued |
| Unapproved concession request (Willow Passage) | **none** (authorizes nothing) | none |
Under-billing and over-billing are always separate lines; they are never netted.

## Treatments (per adjustment line)
Each line starts on its policy default; changing it changes the account pair and **requires a non-blank reason** (`calc.set_treatment`; table constraint).
| Kind | accrual | contra | write-off |
|---|---|---|---|
| usage_reduce (default accrual) | Dr 4010 / Cr 1150 | Dr 4090 / Cr 1150 | Dr 6900 / Cr 1150 |
| usage_increase (accrual only) | Dr 1150 / Cr 4010 | not allowed | not allowed |
| platform_increase (accrual only) | Dr 2200 / Cr 4000 | not allowed | not allowed |
| concession_credit (default contra) | Dr 4010 / Cr 1150 | Dr 4090 / Cr 1150 | Dr 6900 / Cr 1150 |
Missed revenue can only be accrued. Contra applies to credited or waived amounts. Write-off is outside the exercise policy and blocks export.
**4090 and 6900 are PLACEHOLDER accounts** (not in the supplied chart of accounts): every output that uses them carries the warning
"map to a real NetSuite account before import".

## Contract-asset reclass
A customer platform net debit in 2200 moves to 1160. The supplied October GL already contains its baseline reclass; the engine reverses and recalculates
(required 1160 = net debit in 2200 after corrected recognition) and proposes **only the incremental change** (Meridian +$526.03).

## Dates
Billing documents (supplemental invoices, credit notes) are dated in November (`ref.close_params.proposed_billing_issue_date`, a proposal for the Controller to confirm).
October-service accounting adjustments stay in the October posting period (journal date 2026-10-31). October is open per MSG-2026-125; September is finalized.

## NetSuite journal CSV
`scripts/export_journal_csv.py`: External ID repeated on every row; Date, Posting Period, Account ("number name"), Debit, Credit (one per line, the other blank), Memo, Name (NetSuite customer ID);
no total row; each entry balances. A closed posting period, an unbalanced entry, a write-off or an override without reason blocks the file; placeholder accounts warn; Controller approval is
required unless `--allow-draft` is used (the file is then a DRAFT).

## Mockup vs data
The mockup's sample JE-03 (Zephyr, Dr 4090 / Cr 1150 $100) is **not generated**: Zephyr's October accrual is already net ($852.60 = expected net), so the entry would double-count.
