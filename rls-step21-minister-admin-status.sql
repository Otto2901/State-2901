-- rls-step21-minister-admin-status.sql
-- Two additions to the SvS Minister Applications module:
--
-- 1. minister_config.status: open, closed or hidden.
--    open   = visible, players can apply
--    closed = visible, availability readable, applying blocked
--    hidden = entry button and home card hidden for everyone
--    Default hidden, so nothing shows until super admin opens it.
--    Only super admin changes it, mc_update is unchanged.
--
-- 2. New assignable role minister_admin, limited: can read applications,
--    add and edit entries, assign and unassign times. Deleting
--    applications, status, dates and New SvS reset stay super admin only.
--
-- Run once in the Supabase SQL editor after rls-step20, then run the
-- VERIFY queries at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Status column
-- ─────────────────────────────────────────────────────────────────────────────
alter table minister_config add column if not exists status text not null default 'hidden';
alter table minister_config drop constraint if exists minister_config_status_check;
alter table minister_config add constraint minister_config_status_check
  check (status in ('open','closed','hidden'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Role + helper
-- ─────────────────────────────────────────────────────────────────────────────
alter table admin_roles drop constraint admin_roles_role_check;

alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array[
    'super_admin','svs_admin','cj_admin','moderator','prep_admin',
    'album_admin','library_admin','stronghold_admin','war_admin','rally_admin',
    'presidency_admin','minister_admin'
  ]));

create or replace function is_minister_admin(p text) returns boolean
language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'minister_admin');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Widen policies to minister_admin, delete stays super admin
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "ma_select" on minister_applications;
create policy "ma_select" on minister_applications for select
  using (is_minister_admin(current_player()));
drop policy if exists "ma_insert" on minister_applications;
create policy "ma_insert" on minister_applications for insert
  with check (is_minister_admin(current_player()));
drop policy if exists "ma_update" on minister_applications;
create policy "ma_update" on minister_applications for update
  using (is_minister_admin(current_player()))
  with check (is_minister_admin(current_player()));

drop policy if exists "mas_select" on minister_assignments;
create policy "mas_select" on minister_assignments for select
  using (is_minister_admin(current_player()));
drop policy if exists "mas_insert" on minister_assignments;
create policy "mas_insert" on minister_assignments for insert
  with check (is_minister_admin(current_player()));
drop policy if exists "mas_delete" on minister_assignments;
create policy "mas_delete" on minister_assignments for delete
  using (is_minister_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run this ONE query and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select 'policy' as kind, tablename || '.' || policyname as name, qual || ' / ' || coalesce(with_check,'') as detail
  from pg_policies where tablename in ('minister_config','minister_applications','minister_assignments')
union all
select 'config', 'row 1', status || ' / ' || second_vp_day from minister_config
union all
select 'role_check', conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'admin_roles_role_check'
union all
select 'function', proname, '' from pg_proc where proname = 'is_minister_admin'
order by 1, 2;
-- expect 9 policy rows: ma_delete super admin, ma_insert ma_select ma_update
-- mas_delete mas_insert mas_select with is_minister_admin, mc_select true,
-- mc_update super admin. config row: hidden / 2. role_check lists
-- minister_admin. function row: is_minister_admin.
