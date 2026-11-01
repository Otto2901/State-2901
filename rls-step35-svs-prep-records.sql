-- rls-step35-svs-prep-records.sql
-- SvS Prep Records: a monthly log of the top alliances and top players by
-- points in the SvS preparation phase. Overall totals only.
--
--   svs_prep_records  one row per prep. alliances and players are kept as
--                     ranked JSON lists inside the row, so a record is always
--                     saved in one go and never leaves loose rows behind.
--                     alliances = [{"name":"HUM","score":123}]
--                     players   = [{"name":"Otto","alliance":"HUM","score":45}]
--
-- New assignable role svslog_viewer: can open the module and read it, nothing
-- else. Only the super admin adds, edits or deletes records. Nobody else sees
-- anything. No FK constraints, per this repo's convention. Changes go to
-- Admin Panel > Logs through the audit_row trigger.
--
-- Run once in the Supabase SQL editor after rls-step34, then run the VERIFY
-- query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Role + helper
-- ─────────────────────────────────────────────────────────────────────────────
alter table admin_roles drop constraint admin_roles_role_check;

alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array[
    'super_admin','svs_admin','cj_admin','moderator','prep_admin',
    'album_admin','library_admin','stronghold_admin','war_admin','rally_admin',
    'presidency_admin','minister_admin','troops_admin','bear_admin','svslog_viewer'
  ]));

create or replace function is_svslog_viewer(p text) returns boolean
language sql security definer stable set search_path = public as $$
  select is_super_admin(p) or has_role(p, 'svslog_viewer');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Table
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists svs_prep_records (
  id uuid primary key default gen_random_uuid(),
  prep_date date not null,
  opponent_state int check (opponent_state between 1 and 99999),
  result text check (result in ('won','lost')),
  alliances jsonb not null default '[]'::jsonb check (jsonb_typeof(alliances) = 'array'),
  players jsonb not null default '[]'::jsonb check (jsonb_typeof(players) = 'array'),
  created_by text,
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists svs_prep_records_date_idx on svs_prep_records (prep_date desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS: viewers read, super admin writes
-- ─────────────────────────────────────────────────────────────────────────────
alter table svs_prep_records enable row level security;
alter table svs_prep_records force row level security;

drop policy if exists "spr_select" on svs_prep_records;
create policy "spr_select" on svs_prep_records for select
  using (is_svslog_viewer(current_player()));

drop policy if exists "spr_insert" on svs_prep_records;
create policy "spr_insert" on svs_prep_records for insert
  with check (is_super_admin(current_player()));

drop policy if exists "spr_update" on svs_prep_records;
create policy "spr_update" on svs_prep_records for update
  using (is_super_admin(current_player()))
  with check (is_super_admin(current_player()));

drop policy if exists "spr_delete" on svs_prep_records;
create policy "spr_delete" on svs_prep_records for delete
  using (is_super_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Audit log
-- ─────────────────────────────────────────────────────────────────────────────
drop trigger if exists audit_svs_prep_records on svs_prep_records;
create trigger audit_svs_prep_records after insert or update or delete on svs_prep_records
  for each row execute function audit_row();

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run this ONE query and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select 'policy' as kind, tablename || '.' || policyname as name, cmd as detail
  from pg_policies where tablename = 'svs_prep_records'
union all
select 'role_check', conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'admin_roles_role_check'
union all
select 'function', proname, '' from pg_proc where proname = 'is_svslog_viewer'
union all
select 'rls', relname, relrowsecurity::text || ' / force ' || relforcerowsecurity::text from pg_class where relname = 'svs_prep_records'
union all
select 'trigger', tgname, '' from pg_trigger where tgname = 'audit_svs_prep_records'
order by 1, 2;
-- expect 4 policy rows: spr_delete DELETE, spr_insert INSERT, spr_select SELECT,
-- spr_update UPDATE. role_check lists svslog_viewer. function row:
-- is_svslog_viewer. rls row: true / force true. 1 trigger row.
