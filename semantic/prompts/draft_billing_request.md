# draft_billing_request

Draft request to Billing for a proposed billing correction (supplemental invoice or linked credit note). Draft text only; nothing is created in any system.

## Required context
display_id, customer, title_tail, correction_line, issue_date_line, action_text, owner_line, evidence_summary, evidence_cites

## Template
To: Billing
Subject: {{customer}}: {{title_tail}} [{{display_id}}]
Billing, please prepare the following for Controller approval. {{correction_line}} [{{display_id}}]
{{issue_date_line}} [{{display_id}}]
Recommended action: {{action_text}} [{{display_id}}]
Supporting evidence: {{evidence_summary}} {{evidence_cites}}
Please do not edit the finalized invoice. {{owner_line}} [{{display_id}}]

## System prompt
Draft a short request to Billing, from Revenue Accounting, asking them to prepare a proposed billing correction for Controller approval. Use ONLY the supplied context. Every dollar amount you write must appear verbatim in the context; never calculate or invent a number. Cite supporting IDs in square brackets after each claim, using only IDs from the context. State that documents carry a November issue date, that the finalized invoice is not edited, and that nothing is issued until the Controller approves. Do not mention anything the context does not support.
