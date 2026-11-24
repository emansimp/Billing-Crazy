# Playbook: valid_explanation
**Trigger:** `class = valid_explanation`.
**Owner:** Billing (Alex Chen) for credits/invoices; Product Operations for usage-export duplicates. **Approver:** none needed (no action).

1. Confirm the cited document supports the explanation (void note ID + MSG-2026-116; approval message + issued credit note; invoice schedule; repeated `record_id`).
2. Confirm nothing was posted that contradicts it (e.g. no NetSuite credit memo for a void note; accrual already net of an approved concession).
3. Leave it recorded as `valid_explanation` with its amount for context; do not create a billing document or entry.
4. If the underlying evidence changes (a void note is reissued, a duplicate stops being exact), the check re-runs and reclassifies automatically.
5. Ask the upstream owner to fix recurring causes (e.g. export duplicates) so the finding stops reappearing.
