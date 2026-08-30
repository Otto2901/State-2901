-- rls-step15-rallytimer-admin.sql
-- Adds the "rally_admin" role so a Super Admin can grant Rally Timer access
-- to specific players. The Rally Timer module stores nothing server-side, so
-- no new RLS policy is required. This only widens the admin_roles CHECK
-- constraint and adds a parity helper function.
--
-- Run in the Supabase SQL editor as the project owner.

alter table admin_roles drop constraint admin_roles_role_check;

alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array[
    'super_admin','svs_admin','cj_admin','moderator','prep_admin',
    'album_admin','library_admin','stronghold_admin','war_admin','rally_admin'
  ]));

create or replace function is_rally_admin(p text) returns boolean
language sql stable as $$
  select is_super_admin(p) or has_role(p, 'rally_admin');
$$;

-- Verify: the constraint definition should now list rally_admin.
select conname, pg_get_constraintdef(oid) as def
from pg_constraint
where conname = 'admin_roles_role_check';

-- Verify: helper function exists.
select proname from pg_proc where proname = 'is_rally_admin';
