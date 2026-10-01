-- rls-step25-alliance-on-apps.sql
-- SvS minister applications now ask for the player's alliance, picked from
-- the state alliance list. It is stored on the application and on the
-- permanent troop report, so the Troops tab can filter by alliance.
-- Older troop reports keep alliance empty: shown as No alliance, and the
-- super admin can set it by hand. ptr_update is already super admin only.
--
-- state_alliances: public function so the no-login form can list alliances.
-- It returns only alliance tags and colours, nothing about players.
--
-- Run once in the Supabase SQL editor after rls-step24, then run the
-- VERIFY query at the bottom and paste the ROWS back.

alter table minister_applications add column if not exists alliance text;
alter table player_troop_reports add column if not exists alliance text;

create or replace function state_alliances()
returns table (alliance text, color text)
language sql security definer stable
set search_path = public
as $$
  select c.alliance, c.color from alliance_colors c order by c.alliance;
$$;

revoke all on function state_alliances() from public;
grant execute on function state_alliances() to anon, authenticated;

-- VERIFY: run this ONE query and paste the ROWS back
select 'column' as kind, table_name || '.' || column_name as name, data_type as detail
  from information_schema.columns
  where column_name = 'alliance' and table_name in ('minister_applications','player_troop_reports')
union all
select 'function', proname, '' from pg_proc where proname = 'state_alliances'
union all
select 'policy', policyname, cmd || ' / ' || coalesce(qual, '') || ' / ' || coalesce(with_check, '')
  from pg_policies where tablename = 'player_troop_reports'
order by 1, 2;
-- expect 2 column rows with type text, 1 function row state_alliances,
-- 4 policy rows unchanged: ptr_select is_troops_admin, others is_super_admin
