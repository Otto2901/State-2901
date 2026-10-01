-- rls-step20-minister-apps.sql
-- SvS Prep Minister Applications: players apply WITHOUT logging in for a
-- 30-minute minister slot on three prep days, super admin assigns slots.
--
-- Positions are keyed, not tied to a day number:
--   vp1 = Vice President, Day 1 fixed
--   edu = Minister of Education, Day 4 fixed
--   vp2 = Vice President, Day 2 or Day 5, set in minister_config
-- Slot = 0..47, slot n starts at n*30 minutes UTC, 0 = 00:00, 47 = 23:30.
--
-- - minister_config: one row, public read, super admin write
-- - minister_applications: super admin only, public inserts go through the
--   minister-apply edge function with the service-role key
-- - minister_assignments: super admin only, primary key position+slot makes
--   double booking impossible at the DB level
-- - minister_taken_slots: public function returning ONLY position and slot,
--   never names or player data
-- - minister_submit_rate: rate limit table, service-role only
--
-- No FK constraints, per repo convention: the client deletes assignments
-- before their application.
-- Run once in the Supabase SQL editor as the project owner, then run the
-- VERIFY queries at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists minister_config (
  id int primary key check (id = 1),
  prep_start_date date,
  second_vp_day int not null default 2 check (second_vp_day in (2,5)),
  updated_by text,
  updated_at timestamptz not null default now()
);

insert into minister_config (id) values (1) on conflict (id) do nothing;

create table if not exists minister_applications (
  id uuid primary key default gen_random_uuid(),
  player_name text not null,
  player_id text not null,
  speed_construction numeric not null default 0,
  speed_research numeric not null default 0,
  speed_general numeric not null default 0,
  fire_crystal int not null default 0,
  refined_fc int not null default 0,
  fc_shards int not null default 0,
  prefs jsonb not null default '{}'::jsonb,
  source text not null default 'public' check (source in ('public','admin')),
  entered_by text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create index if not exists minister_applications_player_id_idx on minister_applications (player_id);
create index if not exists minister_applications_created_at_idx on minister_applications (created_at);

create table if not exists minister_assignments (
  position text not null check (position in ('vp1','edu','vp2')),
  slot int not null check (slot between 0 and 47),
  application_id uuid not null,
  assigned_by text,
  assigned_at timestamptz not null default now(),
  primary key (position, slot),
  unique (application_id, position)
);

create table if not exists minister_submit_rate (
  ip_hash text primary key,
  count int not null default 0,
  window_start timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Public taken-slots function. Runs as owner so anon can see which slots
--    are taken without any read access to the assignments table itself.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function minister_taken_slots()
returns table (position text, slot int)
language sql security definer stable
set search_path = public
as $$
  select a.position, a.slot from minister_assignments a;
$$;

revoke all on function minister_taken_slots() from public;
grant execute on function minister_taken_slots() to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table minister_config enable row level security;
alter table minister_config force row level security;
alter table minister_applications enable row level security;
alter table minister_applications force row level security;
alter table minister_assignments enable row level security;
alter table minister_assignments force row level security;
-- Rate table: RLS on, zero policies, same as login_failures.
alter table minister_submit_rate enable row level security;

drop policy if exists "mc_select" on minister_config;
create policy "mc_select" on minister_config for select
  using (true);
drop policy if exists "mc_update" on minister_config;
create policy "mc_update" on minister_config for update
  using (is_super_admin(current_player()))
  with check (is_super_admin(current_player()));

drop policy if exists "ma_select" on minister_applications;
create policy "ma_select" on minister_applications for select
  using (is_super_admin(current_player()));
drop policy if exists "ma_insert" on minister_applications;
create policy "ma_insert" on minister_applications for insert
  with check (is_super_admin(current_player()));
drop policy if exists "ma_update" on minister_applications;
create policy "ma_update" on minister_applications for update
  using (is_super_admin(current_player()))
  with check (is_super_admin(current_player()));
drop policy if exists "ma_delete" on minister_applications;
create policy "ma_delete" on minister_applications for delete
  using (is_super_admin(current_player()));

drop policy if exists "mas_select" on minister_assignments;
create policy "mas_select" on minister_assignments for select
  using (is_super_admin(current_player()));
drop policy if exists "mas_insert" on minister_assignments;
create policy "mas_insert" on minister_assignments for insert
  with check (is_super_admin(current_player()));
drop policy if exists "mas_delete" on minister_assignments;
create policy "mas_delete" on minister_assignments for delete
  using (is_super_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run these and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select tablename, policyname, cmd, qual from pg_policies
where tablename in ('minister_config','minister_applications','minister_assignments','minister_submit_rate')
order by tablename, policyname;
-- expect exactly 9 rows: ma_delete, ma_insert, ma_select, ma_update,
-- mas_delete, mas_insert, mas_select, mc_select, mc_update
-- and nothing for minister_submit_rate

select relname, relrowsecurity, relforcerowsecurity from pg_class
where relname in ('minister_config','minister_applications','minister_assignments','minister_submit_rate');
-- expect rowsecurity true on all 4, force true on the first 3

select proname, prosecdef from pg_proc where proname = 'minister_taken_slots';
-- expect 1 row, prosecdef true

select id, prep_start_date, second_vp_day from minister_config;
-- expect 1 row: 1, null, 2
