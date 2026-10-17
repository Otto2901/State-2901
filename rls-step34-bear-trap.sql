-- rls-step34-bear-trap.sql
-- Bear Trap module: our alliance's Bear Hunt wave rosters for the two traps
-- BT1 and BT2, plus the settings used to build the copy-paste announcement.
--
--   bear_trap_config   one row per trap: time, delay between waves, wave
--                      count 1 to 5, join max and the heroes line.
--   bear_trap_players  one row per player. bt + wave place the player in a
--                      wave. Both null = Bench, in the alliance but not placed.
--                      A name can only exist once, so a player is never in
--                      two waves or both traps.
--
-- New assignable role bear_admin. Super admin and bear admins read and write
-- everything here, nobody else sees anything. No FK constraints, per this
-- repo's convention. Changes go to Admin Panel > Logs through the audit_row trigger.
--
-- Run once in the Supabase SQL editor after rls-step33, then run the VERIFY
-- query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Role + helper
-- ─────────────────────────────────────────────────────────────────────────────
alter table admin_roles drop constraint admin_roles_role_check;

alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array[
    'super_admin','svs_admin','cj_admin','moderator','prep_admin',
    'album_admin','library_admin','stronghold_admin','war_admin','rally_admin',
    'presidency_admin','minister_admin','troops_admin','bear_admin'
  ]));

create or replace function is_bear_admin(p text) returns boolean
language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'bear_admin');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Tables
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists bear_trap_config (
  bt smallint primary key check (bt in (1,2)),
  time_utc text not null default '20:00',
  delay_min int not null default 1 check (delay_min between 0 and 60),
  waves int not null default 5 check (waves between 1 and 5),
  join_max text not null default '',
  heroes text not null default '',
  updated_by text,
  updated_at timestamptz not null default now()
);

insert into bear_trap_config (bt, time_utc, delay_min, waves, join_max, heroes)
values
  (1, '20:00', 1, 5, '110k', 'Jessie, Jasser, Seo-yoon, Jeronimo, Reina or Gwen'),
  (2, '20:00', 1, 5, '110k', 'Jessie, Jasser, Seo-yoon, Jeronimo, Reina or Gwen')
on conflict (bt) do nothing;

create table if not exists bear_trap_players (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 40),
  bt smallint check (bt in (1,2)),
  wave smallint check (wave between 1 and 5),
  pos int not null default 0,
  created_at timestamptz not null default now(),
  check ((bt is null) = (wave is null))
);

create unique index if not exists bear_trap_players_name_uq
  on bear_trap_players (lower(trim(name)));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table bear_trap_config enable row level security;
alter table bear_trap_config force row level security;
alter table bear_trap_players enable row level security;
alter table bear_trap_players force row level security;

drop policy if exists "btc_select" on bear_trap_config;
create policy "btc_select" on bear_trap_config for select
  using (is_bear_admin(current_player()));
drop policy if exists "btc_update" on bear_trap_config;
create policy "btc_update" on bear_trap_config for update
  using (is_bear_admin(current_player()))
  with check (is_bear_admin(current_player()));

drop policy if exists "btp_select" on bear_trap_players;
create policy "btp_select" on bear_trap_players for select
  using (is_bear_admin(current_player()));
drop policy if exists "btp_write" on bear_trap_players;
create policy "btp_write" on bear_trap_players for all
  using (is_bear_admin(current_player()))
  with check (is_bear_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Audit log
-- ─────────────────────────────────────────────────────────────────────────────
drop trigger if exists audit_bear_trap_config on bear_trap_config;
create trigger audit_bear_trap_config after insert or update or delete on bear_trap_config
  for each row execute function audit_row();
drop trigger if exists audit_bear_trap_players on bear_trap_players;
create trigger audit_bear_trap_players after insert or update or delete on bear_trap_players
  for each row execute function audit_row();

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run this ONE query and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select 'policy' as kind, tablename || '.' || policyname as name, cmd as detail
  from pg_policies where tablename in ('bear_trap_config','bear_trap_players')
union all
select 'role_check', conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'admin_roles_role_check'
union all
select 'function', proname, '' from pg_proc where proname = 'is_bear_admin'
union all
select 'config_row', bt::text, time_utc || ' / ' || waves || ' waves' from bear_trap_config
union all
select 'trigger', tgname, '' from pg_trigger where tgname in ('audit_bear_trap_config','audit_bear_trap_players')
order by 1, 2;
-- expect 4 policy rows: bear_trap_config.btc_select SELECT, btc_update UPDATE,
-- bear_trap_players.btp_select SELECT, btp_write ALL. role_check lists
-- bear_admin. function row: is_bear_admin. config_row 1 and 2. 2 trigger rows.
