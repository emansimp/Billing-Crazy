# Playbook: error
**Trigger:** `class = error` in `calc.v_findings` (billed differs from contract x metered usage, or a control failed).
**Owner:** Billing (Alex Chen). **Approver:** Controller (Priya Shah).

1. Open the finding: confirm `evidence` IDs (invoice, line, usage records, contract document + page) and recompute the expected amount from the golden-tested views.
2. Decide the document by `direction`: `under` -> supplemental invoice; `over` -> linked credit note. Never edit a finalized invoice. Never net an under against an over.
3. Date the billing document in November. Keep the original service period (October) on the line.
4. Separately decide the October accounting adjustment: needed **only if** the October accrual/recognition differs from the contract-supported amount
   (`calc.usage_accrual_comparison`, `calc.platform_recognition_oct`). A billing correction is not an automatic revenue adjustment (e.g. Beacon Marsh: billing correction only).
5. For `amendment_not_loaded` diagnoses: load the executed amendment in billing before the next invoice run, then re-run the review.
6. For `later_service_followup` scope: fix the recurring invoice amount; do not reconcile November here.
7. Controller approves; record the decision on the finding; re-run `scripts/run_golden.py` and the review.
