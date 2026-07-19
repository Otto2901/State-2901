-- Step 3 of the security hardening: lock down every remaining table.
-- This file documents the FINAL state actually applied in the Supabase
-- SQL editor (in several small batches, with live curl verification
-- after each). A few notes from that process:
--
--   * svs_participant_guide is referenced in index.html (line ~1668) but
--     does not exist as a table in this project -- that save action was
--     already silently broken before this change; no policy needed.
--
--   * Several tables (svs_rally_leaders, rules_topics, cj_teams,
--     cj_team_members) had old leftover permissive policies from an
--     earlier, unfinished RLS attempt (e.g. "public read" using true,
--     "anon all" using true) that were found and dropped -- Postgres
--     OR's multiple permissive policies together, so a single forgotten
--     "using (true)" policy silently defeats an otherwise-correct
--     restrictive one. Always check `select * from pg_policies where
--     tablename = '...'` before trusting a new policy is actually
--     enforced.
--
--   * Every table below also gets `FORCE ROW LEVEL SECURITY` -- without
--     it, the table owner role bypasses RLS entirely, which can silently
--     defeat these policies depending on how/when the table was created.

-- ── Helper functions ──────────────────────────────────────────────────

create or replace function has_role(p text, r text)
returns boolean language sql security definer stable as $$
  select exists (select 1 from admin_roles where player_name = p and role = r);
$$;

create or replace function is_svs_admin(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'svs_admin');
$$;

create or replace function is_cj_admin(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'cj_admin');
$$;

create or replace function is_moderator(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'moderator');
$$;

create or replace function is_library_admin(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'library_admin');
$$;

create or replace function is_svsp_admin(p text) returns boolean language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'prep_admin');
$$;

create or replace function is_transfer_admin(p text)
returns boolean language sql security definer stable as $$
  select is_super_admin(p) or exists (
    select 1 from alliance_reps where player_name = p and alliance = 'TRANSFER'
  );
$$;

create or replace function is_alliance_rep(p text, a text)
returns boolean language sql security definer stable as $$
  select exists (select 1 from alliance_reps where player_name = p and alliance = a);
$$;

create or replace function is_castle_coord(p text, wid uuid)
returns boolean language sql security definer stable as $$
  select is_super_admin(p) or exists (
    select 1 from castle_coordinators where player_name = p and war_id = wid
  );
$$;

-- ── Purely role-gated tables (read: any logged-in player; write: one role) ──

alter table svs_rally_leaders enable row level security;
alter table svs_rally_leaders force row level security;
create policy "svs_rally_leaders_select" on svs_rally_leaders for select using (current_player() is not null);
create policy "svs_rally_leaders_write" on svs_rally_leaders for all using (is_svs_admin(current_player())) with check (is_svs_admin(current_player()));

alter table rules_topics enable row level security;
alter table rules_topics force row level security;
create policy "rules_topics_select" on rules_topics for select using (current_player() is not null);
create policy "rules_topics_write" on rules_topics for all using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

-- Library: the one table where SELECT itself is admin-only, not just write.
alter table library_entries enable row level security;
alter table library_entries force row level security;
create policy "library_entries_select" on library_entries for select using (is_library_admin(current_player()));
create policy "library_entries_write" on library_entries for all using (is_library_admin(current_player())) with check (is_library_admin(current_player()));

alter table rotation_state enable row level security;
alter table rotation_state force row level security;
create policy "rotation_state_select" on rotation_state for select using (current_player() is not null);
create policy "rotation_state_write" on rotation_state for all using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

alter table location_rewards enable row level security;
alter table location_rewards force row level security;
create policy "location_rewards_select" on location_rewards for select using (current_player() is not null);
create policy "location_rewards_write" on location_rewards for all using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

alter table alliance_reps enable row level security;
alter table alliance_reps force row level security;
create policy "alliance_reps_select" on alliance_reps for select using (current_player() is not null);
create policy "alliance_reps_write" on alliance_reps for all using (is_super_admin(current_player()) or is_moderator(current_player())) with check (is_super_admin(current_player()) or is_moderator(current_player()));

alter table transfer_periods enable row level security;
alter table transfer_periods force row level security;
create policy "transfer_periods_select" on transfer_periods for select using (current_player() is not null);
create policy "transfer_periods_write" on transfer_periods for all using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

alter table transfer_invites enable row level security;
alter table transfer_invites force row level security;
create policy "transfer_invites_select" on transfer_invites for select using (current_player() is not null);
create policy "transfer_invites_write" on transfer_invites for all using (is_transfer_admin(current_player())) with check (is_transfer_admin(current_player()));

alter table svsprep_sessions enable row level security;
alter table svsprep_sessions force row level security;
create policy "svsprep_sessions_select" on svsprep_sessions for select using (current_player() is not null);
create policy "svsprep_sessions_write" on svsprep_sessions for all using (is_svsp_admin(current_player())) with check (is_svsp_admin(current_player()));

alter table svsprep_days enable row level security;
alter table svsprep_days force row level security;
create policy "svsprep_days_select" on svsprep_days for select using (current_player() is not null);
create policy "svsprep_days_write" on svsprep_days for all using (is_svsp_admin(current_player())) with check (is_svsp_admin(current_player()));

alter table castle_wars enable row level security;
alter table castle_wars force row level security;
create policy "castle_wars_select" on castle_wars for select using (current_player() is not null);
create policy "castle_wars_write" on castle_wars for all using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

alter table castle_coordinators enable row level security;
alter table castle_coordinators force row level security;
create policy "castle_coordinators_select" on castle_coordinators for select using (current_player() is not null);
create policy "castle_coordinators_write" on castle_coordinators for all using (is_super_admin(current_player())) with check (is_super_admin(current_player()));

alter table castle_rallies enable row level security;
alter table castle_rallies force row level security;
create policy "castle_rallies_select" on castle_rallies for select using (current_player() is not null);
create policy "castle_rallies_write" on castle_rallies for all using (is_castle_coord(current_player(), war_id)) with check (is_castle_coord(current_player(), war_id));

alter table castle_ralliers enable row level security;
alter table castle_ralliers force row level security;
create policy "castle_ralliers_select" on castle_ralliers for select using (current_player() is not null);
create policy "castle_ralliers_write" on castle_ralliers for all using (is_castle_coord(current_player(), war_id)) with check (is_castle_coord(current_player(), war_id));

-- Crazy Joe (old leftover "read true / write true" policies dropped first)
drop policy if exists "cj_teams_read" on cj_teams;
drop policy if exists "cj_teams_write" on cj_teams;
alter table cj_teams enable row level security;
alter table cj_teams force row level security;
create policy "cj_teams_select" on cj_teams for select using (current_player() is not null);
create policy "cj_teams_write" on cj_teams for all using (is_cj_admin(current_player())) with check (is_cj_admin(current_player()));

drop policy if exists "cj_members_read" on cj_team_members;
drop policy if exists "cj_members_write" on cj_team_members;
alter table cj_team_members enable row level security;
alter table cj_team_members force row level security;
create policy "cj_team_members_select" on cj_team_members for select using (current_player() is not null);
create policy "cj_team_members_write" on cj_team_members for all using (is_cj_admin(current_player())) with check (is_cj_admin(current_player()));

-- ── players (self-service update, admin cascades, PIN column already locked in step 2) ──

alter table players enable row level security;
alter table players force row level security;
create policy "players_select" on players for select using (true);
create policy "players_insert" on players for insert with check (true);
create policy "players_update" on players for update
  using (name = current_player() or is_super_admin(current_player()) or is_moderator(current_player()))
  with check (name = current_player() or is_super_admin(current_player()) or is_moderator(current_player()));
create policy "players_delete" on players for delete using (is_super_admin(current_player()) or is_moderator(current_player()));

-- ── Self-service tables (any player writes their own row; admins write any) ──

alter table id_change_requests enable row level security;
alter table id_change_requests force row level security;
create policy "id_change_requests_select" on id_change_requests for select using (current_player() is not null);
create policy "id_change_requests_insert" on id_change_requests for insert with check (player_name = current_player());
create policy "id_change_requests_update" on id_change_requests for update
  using (is_super_admin(current_player()) or is_moderator(current_player()))
  with check (is_super_admin(current_player()) or is_moderator(current_player()));

alter table svsprep_submissions enable row level security;
alter table svsprep_submissions force row level security;
create policy "svsprep_submissions_select" on svsprep_submissions for select using (current_player() is not null);
create policy "svsprep_submissions_insert" on svsprep_submissions for insert with check (player_name = current_player() or is_svsp_admin(current_player()));
create policy "svsprep_submissions_update" on svsprep_submissions for update
  using (player_name = current_player() or is_svsp_admin(current_player()))
  with check (player_name = current_player() or is_svsp_admin(current_player()));

alter table rotation_selections enable row level security;
alter table rotation_selections force row level security;
create policy "rotation_selections_select" on rotation_selections for select using (current_player() is not null);
create policy "rotation_selections_insert" on rotation_selections for insert with check (is_alliance_rep(current_player(), alliance) or is_super_admin(current_player()));
create policy "rotation_selections_update" on rotation_selections for update
  using (is_alliance_rep(current_player(), alliance) or is_super_admin(current_player()))
  with check (is_alliance_rep(current_player(), alliance) or is_super_admin(current_player()));
create policy "rotation_selections_delete" on rotation_selections for delete using (is_alliance_rep(current_player(), alliance) or is_super_admin(current_player()));

-- ── Push notifications (self-service only; edge functions use the service key and bypass RLS) ──

alter table push_subscriptions enable row level security;
alter table push_subscriptions force row level security;
create policy "push_subscriptions_select" on push_subscriptions for select using (player_name = current_player());
create policy "push_subscriptions_insert" on push_subscriptions for insert with check (player_name = current_player());
create policy "push_subscriptions_update" on push_subscriptions for update using (player_name = current_player()) with check (player_name = current_player());
create policy "push_subscriptions_delete" on push_subscriptions for delete using (player_name = current_player());
