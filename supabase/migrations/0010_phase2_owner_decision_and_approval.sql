-- 0010: owner decision on the Meridian catch-up wording + approval of the extracted terms (recorded 2026-11-23).
-- Decision: the October upgrade catch-up ($526.03, AM-OF-2026-164) is treated as a REQUIRED charge. The original needs_info_reason is kept for audit.
-- Open item for the journal-entry phase: the owner will provide a treatment option for the catch-up entry.
alter table ref.contract_term_fees add column if not exists owner_decision text, add column if not exists decided_by text, add column if not exists decided_at timestamptz;
update ref.contract_term_fees
   set status = 'extracted', owner_decision = 'treat_as_required', decided_by = 'E (owner)', decided_at = now()
 where version_id = 'AM-OF-2026-164:v2' and kind = 'october_upgrade_catch_up';
update ref.contract_term_versions
   set approval_status = 'approved', approved_by = 'E (owner)', approved_at = now();
