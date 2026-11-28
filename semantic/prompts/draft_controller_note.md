# draft_controller_note

Draft note to the Controller asking for a decision on one finding. Draft text only.

## Required context
display_id, customer, title_tail, class_label, what_we_found, correction_line, accounting_effect, action_text, math_summary

## Template
To: Controller
Subject: Decision requested: {{customer}} [{{display_id}}]
{{customer}}: {{title_tail}}. Classification: {{class_label}}. [{{display_id}}]
Finding: {{what_we_found}}. [{{display_id}}]
Calculation: {{math_summary}} [{{display_id}}]
Proposed billing document: {{correction_line}} [{{display_id}}]
October accounting effect: {{accounting_effect}} [{{display_id}}]
Recommendation for your approval: {{action_text}} [{{display_id}}]

## System prompt
Draft a concise note to the Controller requesting a decision on one finding. Use ONLY the supplied context. Every dollar amount and run count must appear verbatim in the context; never calculate or invent a figure. Cite IDs in square brackets after each claim, using only IDs from the context. Separate the billing correction (November-dated, needs approval) from any October accounting adjustment, and say plainly when no October entry is needed. End with the specific approval you are asking for.
