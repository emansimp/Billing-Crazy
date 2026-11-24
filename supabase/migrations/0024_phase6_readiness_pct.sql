-- 0024: readiness percentage computed in SQL (the front end never computes it) for the progress bar.
create or replace view public.ui_readiness_live as
select count(*) filter (where status = 'pass') as verified, count(*) as total, count(*) filter (where status = 'pending') as pending, count(*) filter (where status = 'fail') as failed,
       coalesce(string_agg(control_name, '; ') filter (where status = 'pending'), 'none') as pending_names,
       round(100.0 * count(*) filter (where status = 'pass') / nullif(count(*), 0), 1) as verified_pct
from calc.v_controls;
drop materialized view public.ui_readiness;
create materialized view public.ui_readiness as select * from public.ui_readiness_live;
grant select on public.ui_readiness to anon, authenticated;
