# Contract term extraction rules (v1)

Source precedence (START_HERE p2): executed order forms and amendments set commercial terms; an amendment changes **only the terms it names**;
unchanged terms persist. `supersedes_document_id` in the register means partial precedence, not cancellation of the original.

## What is extracted, and from where
| Field | Where in the PDF | Rule |
|---|---|---|
| customer, contract ID, executed date | header ("Contract CT-... \| Executed ..."), §01 | Must equal the register `contract_id`, the Salesforce account name and `signed_at` (Denver date). |
| term start / end | §02 SERVICE START / SERVICE END | End is **inclusive** in the PDF; stored as `term_end_exclusive = end + 1 day`. Must equal register `effective_from` / `effective_to`. |
| billing frequency | §02 BILLING ("Annual in advance" / "Monthly in advance") | "Monthly, in arrears" on the same page is the usage line, not platform billing. |
| billing anchor day | §04 invoicing clause ("on the 1st / 15th ...", "in full on September 1") | Must equal the day of the term start. |
| platform fee | §03 "$X / year" or "$X / month" | `platform_fee_annual` = fee x 12 for monthly. Must equal "ANNUAL PLATFORM COMMITMENT". `platform_billing_amount` is the per-invoice amount. |
| allowance | §03 "N included runs per calendar month" | Whole runs per calendar month. |
| overage rate | §03 "$R / excess run" | USD per run, 4 decimals. |
| payment terms, currency | §02 PAYMENT / CURRENCY | Must be "Net 30 days / USD". |
| fees, credits, discounts | §03, §04, amendment §03/§04 | Order forms state none other than "no additional invoice discounts" (stored as `invoice_discounts = 0`). Amendment amounts go to `contract_term_fees`. |

## Versions
One row per customer per version in `ref.contract_term_versions`: v1 = order form; v2 = amendment (effective date from the amendment).
`effective_to_exclusive` of v1 = the amendment's effective date; of the latest version = term end. Intervals are start-inclusive, end-exclusive.
v2 copies unchanged terms from v1 and lists the changed ones in `changed_terms`. Meridian's invoice amount changes "from Nov 1", not Oct 16; the
October 16-31 increment is the separate catch-up charge.

## Never guess: status
Each version is checked against `contract_register.csv` and arithmetic (`ref.v_contract_term_checks`). All checks pass -> `status = extracted`,
`confidence = high`. Any failure -> `needs_info` with the failing check in `needs_info_reason`; the value is stored as read, never corrected.
Individual fees/credits carry their own status and verbatim quote. Ambiguous wording (e.g. "may be invoiced separately") -> `needs_info`.

## Approval
`approval_status` starts at `pending_review`. Phase 3 may use only rows the Controller/owner has set to `approved`.

## Sanity checks (recomputed, not copied)
`ref.v_contract_sanity_checks`: Meridian $48,000 -> $60,000 effective Oct 16; catch-up $12,000 x 16 / 365 = $526.03; incremental $12,000 x 320 / 365 = $10,520.55;
final-invoice credit $5.48 = $526.03 + 10 x $1,000 - $10,520.55; Cedar Harbor allowance 30,000 -> 45,000 effective Oct 16.
