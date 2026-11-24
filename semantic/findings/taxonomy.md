# Finding taxonomy (v1)

Every check (see the catalog below) records a result for **every customer**: `pass` (checked, nothing found) or one of three finding classes.
`calc.v_check_results` holds all results; `calc.v_findings` is the non-pass subset; `calc.v_customer_classification` classifies all 30 customers
(severity: error > needs_info > valid_explanation > clean).

| Class | Meaning | Money effect |
|---|---|---|
| `error` | The billed amount or record differs from what the contract and metered usage support. | A billing correction (Nov-dated supplemental invoice or linked credit note) is recommended for Controller approval; an October accounting adjustment only where the October accrual/recognition also differs. |
| `valid_explanation` | A difference or oddity that looks like an error but the source documents explain it. | None. Recorded so nobody re-investigates it. |
| `needs_info` | The evidence cannot settle it (missing owner, no approval). | None until the stated owner supplies the evidence. Nothing is assigned or credited by assumption. |

## Required fields (enforced by `semantic/golden/phase4_findings.sql`)
| Field | Rule |
|---|---|
| `customer` | Customer name; the unassigned-workspace finding uses `UNASSIGNED WORKSPACE <product account>` (it has no customer by design). |
| `stream` | `platform` or `usage`. Never combined. |
| `amount` + `direction` | Required for `error` (`under` = we billed less than supported; `over` = more). Optional context amount for the other classes. Under- and over-billing are never netted. |
| `evidence` | JSON of row/document IDs: invoice numbers, Stripe line IDs, credit note IDs, usage record IDs, contract document IDs, message IDs. |
| `contract_citation` | Contract file + page + section (and START_HERE / message citations for policy). |
| `recommended_action`, `owner`, `approver` | Plain-language next step; who does it; who approves. |
| `in_variance_total` | `true` only for the rows that make up the Phase 3 variance (so totals tie). Diagnoses, valid explanations and follow-ups show amounts for context but are excluded. |
| `period_scope` | `october_service`, or `later_service_followup` (flagged, not reconciled). |

## Check catalog
| check_code | Question | Possible results |
|---|---|---|
| `platform_variance` | Platform expected vs billed (invoice basis) | error / pass |
| `usage_variance` | Usage expected vs billed, net of approved concessions | error / pass |
| `amendment_not_loaded` | Signed amendment with blank `billing_loaded_at` | error / pass (diagnosis; not in variance total) |
| `void_credit_note` | Void credit notes have no effect and nothing was posted | valid_explanation / error / pass |
| `concession` | Approved once, credited once, accrual net; unapproved requests authorize nothing | valid_explanation / needs_info / error / pass |
| `missing_usage_invoice` | Usage invoice exists when billable | error / valid_explanation (no overage) / needs_info (no verified account) / pass |
| `15th_anchor_timing` | 15th-anchor invoices match the schedule and cross the month end | valid_explanation / error / pass |
| `duplicate_usage_record` | Exact repeated `record_id` is not new activity | valid_explanation / error / pass |
| `later_service_platform` | November-service platform invoices issued by cutoff | error (follow-up) / pass |
| `unassigned_usage` | Unverified workspace usage isolated, conditional exposure only | needs_info |
