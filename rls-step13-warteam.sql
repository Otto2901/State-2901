-- Run this once in the Supabase SQL Editor.
-- Step 13: War Team Builder. Rally-leader teams with independent attack
-- and defense hero+troop formations for the leader, plus a squad of
-- other members who each carry a single formation. Heroes come from an
-- admin-managed master list (war_heroes).
--
-- No FK constraints are declared anywhere in this schema, matching this
-- repo's existing convention (every table here is FK-less; cascades are
-- handled in app code, see index.html's deleteAccount-style handlers).

-- ── war_heroes: admin-managed master hero list ──
create table if not exists war_heroes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  class text not null check (class in ('Infantry','Lancer','Marksman','Support')),
  created_at timestamptz not null default now()
);

-- ── war_teams: one row per rally team ──
create table if not exists war_teams (
  id uuid primary key default gen_random_uuid(),
  team_name text not null,
  alliance text not null,
  leader_name text not null,
  -- leader's ATTACK formation (3 hero slots, uuid referencing war_heroes.id,
  -- resolved client-side, no FK per this repo's convention)
  atk_hero1 uuid, atk_hero2 uuid, atk_hero3 uuid,
  atk_infantry_pct int not null default 0,
  atk_lancer_pct   int not null default 0,
  atk_marksman_pct int not null default 0,
  -- leader's DEFENSE formation (independent from attack)
  def_hero1 uuid, def_hero2 uuid, def_hero3 uuid,
  def_infantry_pct int not null default 0,
  def_lancer_pct   int not null default 0,
  def_marksman_pct int not null default 0,
  created_by text,
  created_at timestamptz not null default now(),
  constraint war_teams_atk_pct_check check (atk_infantry_pct + atk_lancer_pct + atk_marksman_pct = 100),
  constraint war_teams_def_pct_check check (def_infantry_pct + def_lancer_pct + def_marksman_pct = 100)
);

-- ── war_team_members: squad list, one formation each (not split atk/def) ──
create table if not exists war_team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  player_name text not null,
  position int not null,
  hero1 uuid, hero2 uuid, hero3 uuid,
  infantry_pct int not null default 0,
  lancer_pct   int not null default 0,
  marksman_pct int not null default 0,
  constraint war_team_members_pct_check check (infantry_pct + lancer_pct + marksman_pct = 100)
);

-- ── RLS ──
-- Reuses is_super_admin()/has_role()/current_player() from
-- rls-step2-critical-locks.sql / rls-step3-chunk1.sql.
create or replace function is_war_admin(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'war_admin');
$$;

alter table war_heroes enable row level security;
alter table war_heroes force row level security;
create policy "war_heroes_select" on war_heroes for select using (current_player() is not null);
create policy "war_heroes_write"  on war_heroes for all
  using (is_war_admin(current_player())) with check (is_war_admin(current_player()));

alter table war_teams enable row level security;
alter table war_teams force row level security;
create policy "war_teams_select" on war_teams for select using (current_player() is not null);
create policy "war_teams_write"  on war_teams for all
  using (is_war_admin(current_player())) with check (is_war_admin(current_player()));

alter table war_team_members enable row level security;
alter table war_team_members force row level security;
create policy "war_team_members_select" on war_team_members for select using (current_player() is not null);
create policy "war_team_members_write"  on war_team_members for all
  using (is_war_admin(current_player())) with check (is_war_admin(current_player()));

-- ── Widen admin_roles CHECK to allow 'war_admin' ──
-- Current definition as of rls-step9 (confirmed live 2026-07-28, and no
-- later rls-step file touches admin_roles before this one):
--   CHECK (role = ANY (ARRAY['super_admin','svs_admin','cj_admin',
--     'moderator','prep_admin','album_admin','library_admin',
--     'stronghold_admin']))
-- This adds 'war_admin' without dropping any existing value. If the
-- live definition differs, re-check with:
--   select conname, pg_get_constraintdef(oid) from pg_constraint where conname='admin_roles_role_check';
alter table admin_roles drop constraint admin_roles_role_check;
alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array['super_admin','svs_admin','cj_admin','moderator','prep_admin','album_admin','library_admin','stronghold_admin','war_admin']));

-- ── Seed hero master list (combat classes only; Gathering heroes are
-- out of scope for war formations) ──
insert into war_heroes (name, class) values
  ('Sergey','Infantry'), ('Jeronimo','Infantry'), ('Flint','Infantry'), ('Logan','Infantry'),
  ('Ahmose','Infantry'), ('Hector','Infantry'), ('Wu Ming','Infantry'), ('Edith','Infantry'),
  ('Jessie','Lancer'), ('Patrick','Lancer'), ('Ling Xue','Lancer'), ('Molly','Lancer'),
  ('Philly','Lancer'), ('Mia','Lancer'), ('Reina','Lancer'), ('Norah','Lancer'),
  ('Renee','Lancer'), ('Gordon','Lancer'),
  ('Bahiti','Marksman'), ('Jasser','Marksman'), ('Seo-yoon','Marksman'), ('Gina','Marksman'),
  ('Natalia','Marksman'), ('Alonso','Marksman'), ('Greg','Marksman'), ('Lynn','Marksman'),
  ('Gwen','Marksman'), ('Wayne','Marksman'), ('Bradley','Marksman'),
  ('Zinman','Support')
on conflict (name) do nothing;

-- ── Verify after running ──
-- select * from pg_policies where tablename in ('war_heroes','war_teams','war_team_members');
-- select proname from pg_proc where proname='is_war_admin';
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conname in ('war_teams_atk_pct_check','war_teams_def_pct_check','war_team_members_pct_check','admin_roles_role_check');
-- select count(*) from war_heroes; -- expect 30
