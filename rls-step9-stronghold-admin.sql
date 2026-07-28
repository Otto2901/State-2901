-- Adds a scoped "stronghold_admin" role: can edit Stronghold Rotation
-- rewards (location_rewards) and manage alliance representatives
-- (alliance_reps), but not the rotation order/reset/force-open-close
-- controls, which stay super-admin-only (enforced client-side in
-- renderRotAdmin, index.html).

-- Step 1: helper function, same pattern as is_cj_admin/is_library_admin
-- in rls-step3-chunk1.sql.
create or replace function is_stronghold_admin(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'stronghold_admin');
$$;

-- Step 2: widen location_rewards_write (was super-admin-only) to also
-- allow stronghold_admin.
drop policy if exists "location_rewards_write" on location_rewards;
create policy "location_rewards_write" on location_rewards for all
  using (is_super_admin(current_player()) or is_stronghold_admin(current_player()))
  with check (is_super_admin(current_player()) or is_stronghold_admin(current_player()));

-- Step 3: widen alliance_reps_write (was super-admin or moderator) to
-- also allow stronghold_admin.
drop policy if exists "alliance_reps_write" on alliance_reps;
create policy "alliance_reps_write" on alliance_reps for all
  using (is_super_admin(current_player()) or is_moderator(current_player()) or is_stronghold_admin(current_player()))
  with check (is_super_admin(current_player()) or is_moderator(current_player()) or is_stronghold_admin(current_player()));

-- Step 4: admin_roles.role has a CHECK constraint that is NOT defined
-- anywhere in this repo (confirmed via rls-step8's note and a live
-- pg_constraint query). Current definition (checked 2026-07-28):
--   CHECK (role = ANY (ARRAY['super_admin','svs_admin','cj_admin',
--     'moderator','prep_admin','album_admin','library_admin']))
-- (svs_admin/prep_admin/album_admin are dead values from removed
-- modules, left in place harmlessly per rls-step8's convention.)
-- This adds 'stronghold_admin' without dropping any existing value.
alter table admin_roles drop constraint admin_roles_role_check;
alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array['super_admin','svs_admin','cj_admin','moderator','prep_admin','album_admin','library_admin','stronghold_admin']));
