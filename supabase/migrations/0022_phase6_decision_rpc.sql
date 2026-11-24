-- 0022: server-only write for finding decisions. Not executable by the browser roles (anon/authenticated); only the service role (server routes) can call it.
create function public.ui_record_finding_decision(p_display_id text, p_decision text) returns void
language plpgsql security definer set search_path = ops, public, calc, ref as $$
declare fid text;
begin
  select finding_id into fid from public.ui_findings_list where display_id = p_display_id;
  if fid is null then raise exception 'unknown finding %', p_display_id; end if;
  insert into ops.finding_decisions (finding_id, decision) values (fid, p_decision)
  on conflict (finding_id) do update set decision = excluded.decision, decided_at = now();
end $$;
revoke all on function public.ui_record_finding_decision(text, text) from public, anon, authenticated;
grant execute on function public.ui_record_finding_decision(text, text) to service_role;
