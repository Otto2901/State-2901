-- rls-step29-logout-revoke.sql
-- Sign Out used to only forget the token on the device. The row in sessions stayed
-- valid for up to 30 days, so a copied token kept working after logout.
-- end_session deletes the session row that matches the caller's own x-session-token
-- header. A caller can only end the session whose token they already hold.
-- Run once in the Supabase SQL editor after rls-step28, then run the VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────
-- 1. end_session RPC
-- ─────────────────────────────────────────────────────────────
create or replace function end_session()
returns void
language sql
security definer
set search_path = public
as $$
  delete from sessions
  where token = coalesce(current_setting('request.headers', true)::json->>'x-session-token', '')
    and token <> '';
$$;

revoke all on function end_session() from public;
grant execute on function end_session() to anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- VERIFY: run these and paste the ROWS back
-- ─────────────────────────────────────────────────────────────
-- expect 1 row: end_session, prosecdef true
select proname, prosecdef from pg_proc where proname = 'end_session';
-- expect 1 row: sessions, rls on, still zero policies so anon cannot read or write it directly
select c.relname, c.relrowsecurity, count(p.policyname) as policies
from pg_class c left join pg_policies p on p.tablename = c.relname
where c.relname = 'sessions'
group by c.relname, c.relrowsecurity;
