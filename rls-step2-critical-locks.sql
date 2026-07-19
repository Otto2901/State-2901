-- Run this once in the Supabase SQL Editor.
-- Step 2 of the security hardening: lock the two most dangerous holes.
--   1) Nobody can grant themselves (or anyone) an admin role from the browser anymore.
--   2) Nobody can bulk-read every player's PIN hash from the browser anymore.

-- Helper: resolve the player_name behind the current request's session token
-- (sent as the 'x-session-token' header), or null if missing/expired/invalid.
create or replace function current_player()
returns text
language sql
security definer
stable
as $$
  select s.player_name
  from sessions s
  where s.token = coalesce(current_setting('request.headers', true)::json->>'x-session-token', '')
    and s.expires_at > now()
  limit 1;
$$;

-- Helper: is this player name a super admin? (hardcoded owner OR has the super_admin role)
create or replace function is_super_admin(p text)
returns boolean
language sql
security definer
stable
as $$
  select p = 'Otto' or exists (
    select 1 from admin_roles where player_name = p and role = 'super_admin'
  );
$$;

-- Lock down admin_roles: any logged-in player can read it (needed for role
-- badges in the UI), but only super admins can grant/change/revoke roles.
alter table admin_roles enable row level security;

create policy "admin_roles_select" on admin_roles
  for select using (current_player() is not null);

create policy "admin_roles_insert" on admin_roles
  for insert with check (is_super_admin(current_player()));

create policy "admin_roles_update" on admin_roles
  for update using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

create policy "admin_roles_delete" on admin_roles
  for delete using (is_super_admin(current_player()));

-- Stop anyone from bulk-reading PIN hashes directly (the app itself never
-- selects this column anymore -- login is verified server-side now).
--
-- NOTE: a plain column-level revoke is NOT enough here, because `anon`
-- already had a broad table-level SELECT grant (from Supabase's default
-- bootstrap) which overrides a column-level revoke -- Postgres tracks
-- table-level and column-level grants separately. Verified live with
-- curl: the naive version below left `pin` fully readable. The fix is
-- to revoke the table-level grant first, then grant back only the
-- columns the app actually needs.
revoke select on players from anon, authenticated, public;
grant select (name, created_at, status, player_id, alliance, valeria_level) on players to anon;
