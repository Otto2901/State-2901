-- rls-step24-troops-admin.sql
-- New assignable role troops_admin: READ ONLY access to player_troop_reports,
-- shown in its own Admin Panel tab. No access to minister applications.
-- Insert, update and delete on troop reports stay super admin only.
--
-- Run once in the Supabase SQL editor after rls-step23, then run the
-- VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Role + helper
-- ─────────────────────────────────────────────────────────────────────────────
alter table admin_roles drop constraint admin_roles_role_check;

alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array[
    'super_admin','svs_admin','cj_admin','moderator','prep_admin',
    'album_admin','library_admin','stronghold_admin','war_admin','rally_admin',
    'presidency_admin','minister_admin','troops_admin'
  ]));

create or replace function is_troops_admin(p text) returns boolean
language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'troops_admin');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Widen SELECT only, insert update delete unchanged
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "ptr_select" on player_troop_reports;
create policy "ptr_select" on player_troop_reports for select
  using (is_troops_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run this ONE query and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select 'policy' as kind, policyname as name, cmd || ' / ' || coalesce(qual, '') || ' / ' || coalesce(with_check, '') as detail
  from pg_policies where tablename = 'player_troop_reports'
union all
select 'role_check', conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'admin_roles_role_check'
union all
select 'function', proname, '' from pg_proc where proname = 'is_troops_admin'
order by 1, 2;
-- expect 4 policy rows: ptr_select uses is_troops_admin, ptr_insert
-- ptr_update ptr_delete still use is_super_admin. role_check lists
-- troops_admin. function row: is_troops_admin.
