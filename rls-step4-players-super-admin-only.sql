-- Restrict Players admin tab actions (update/delete on players, approve on id_change_requests)
-- to super_admin only. Moderator role no longer qualifies.
-- Run in Supabase SQL editor, then verify with: select * from pg_policies where tablename in ('players','id_change_requests');

drop policy if exists "players_update" on players;
create policy "players_update" on players for update
  using (name = current_player() or is_super_admin(current_player()))
  with check (name = current_player() or is_super_admin(current_player()));

drop policy if exists "players_delete" on players;
create policy "players_delete" on players for delete using (is_super_admin(current_player()));

drop policy if exists "id_change_requests_update" on id_change_requests;
create policy "id_change_requests_update" on id_change_requests for update
  using (is_super_admin(current_player()))
  with check (is_super_admin(current_player()));
