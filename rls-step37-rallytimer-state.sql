-- rls-step37-rallytimer-state.sql
-- Rally Timer working list moves off the phone and onto the site.
--
--   rally_timer_state   one row per rally admin: their current list of
--                       leaders, march times, ticks and the rally duration.
--                       leaders = [{"name":"Otto","march":"1:12","active":true}]
--
-- Each rally admin reads and writes only their own row, so phone and PC show
-- the same list. The super admin may also touch any row, which the account
-- delete and rename cleanup needs. Shared presets stay in rally_timer_presets.
-- No audit trigger on purpose: the list saves while typing and would flood Logs.
--
-- Run once in the Supabase SQL editor after rls-step36, then run the VERIFY
-- query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Table
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists rally_timer_state (
  player_name text primary key,
  dur int not null default 180 check (dur in (60,180,300)),
  leaders jsonb not null default '[]'::jsonb check (jsonb_typeof(leaders) = 'array'),
  updated_at timestamptz not null default now()
);

alter table rally_timer_state enable row level security;
alter table rally_timer_state force row level security;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Policy: own row for rally admins, any row for the super admin
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "rts_own" on rally_timer_state;
create policy "rts_own" on rally_timer_state for all
  using (
    (player_name = current_player() and is_rally_admin(current_player()))
    or is_super_admin(current_player())
  )
  with check (
    (player_name = current_player() and is_rally_admin(current_player()))
    or is_super_admin(current_player())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run these and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
-- expect 1 row: rts_own, ALL
select policyname, cmd from pg_policies where tablename = 'rally_timer_state';

-- expect 4 rows: player_name, dur, leaders, updated_at
select column_name, data_type from information_schema.columns
  where table_name = 'rally_timer_state' order by ordinal_position;
