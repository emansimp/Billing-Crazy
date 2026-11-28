-- 0029: Supabase's API layer (safeupdate) rejects DELETE without a WHERE clause, so ui_reset_demo and ui_revoke_approvals failed from the app
-- with "DELETE requires a WHERE clause". Same behaviour, explicit "where true".
create or replace function public.ui_revoke_approvals() returns void language sql security definer set search_path = ops, public, calc, ref
as 'delete from ref.journal_approvals where true';
create or replace function public.ui_reset_demo() returns void language plpgsql security definer set search_path = ops, public, calc, ref as $$
begin
  delete from ops.finding_decisions where true;
  delete from ops.finding_decision_log where true;
  delete from ref.adjustment_treatments where true;
  delete from ref.journal_approvals where true;
end $$;
