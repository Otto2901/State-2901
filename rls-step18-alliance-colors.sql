-- rls-step18-alliance-colors.sql
-- PART A: clean up alliance rows left stale by a pre-fix in-app rename
--         (FAL -> PAC main, fal -> (pac) farm).
-- PART B: move alliance colours from the hard-coded ALLIANCE_COLORS JS map into
--         a DB table so rename / add / delete keep colours in sync automatically.
--
-- Run in the Supabase SQL editor as the project owner. Verify with the SELECTs
-- at the bottom (paste the ROWS back, not just "Success").

-- ═══════════════════ PART A — data migration ════════════════════════════════
-- Wipe every leftover FAL variant. Main alliance FAL / (FAL) -> PAC ;
-- farm alliance fal / (fal) -> (pac). The two alliance_reps '(FAL)' rows
-- (ChiliXtreme, AshesToAshes) are verified main-alliance members.
-- Most of these hit 0 rows today; kept so the cleanup is exhaustive + idempotent.

-- alliance_reps has a UNIQUE (player_name, alliance) constraint. A player who
-- already has the canonical rep row plus a stale variant row would collide on
-- rename, so delete the redundant stale row first, then rename the survivors.
delete from alliance_reps a using alliance_reps b
  where a.player_name = b.player_name and a.alliance in ('FAL','(FAL)')   and b.alliance = 'PAC';
delete from alliance_reps a using alliance_reps b
  where a.player_name = b.player_name and a.alliance in ('fal','(fal)')   and b.alliance = '(pac)';

update players             set alliance = 'PAC' where alliance in ('FAL','(FAL)');
update alliance_reps       set alliance = 'PAC' where alliance in ('FAL','(FAL)');
update rotation_selections set alliance = 'PAC' where alliance in ('FAL','(FAL)');
update cj_teams            set alliance = 'PAC' where alliance in ('FAL','(FAL)');
update war_teams           set alliance = 'PAC' where alliance in ('FAL','(FAL)');
update transfer_invites    set alliance = 'PAC' where alliance in ('FAL','(FAL)');

update players             set alliance = '(pac)' where alliance in ('fal','(fal)');
update alliance_reps       set alliance = '(pac)' where alliance in ('fal','(fal)');
update rotation_selections set alliance = '(pac)' where alliance in ('fal','(fal)');
update cj_teams            set alliance = '(pac)' where alliance in ('fal','(fal)');
update war_teams           set alliance = '(pac)' where alliance in ('fal','(fal)');
update transfer_invites    set alliance = '(pac)' where alliance in ('fal','(fal)');

-- rotation_state.top4_order / bot5_order JSON arrays already hold PAC / (pac).

-- ═══════════════════ PART B — alliance_colors table ═════════════════════════
create table if not exists alliance_colors (
  alliance   text primary key,
  color      text not null,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table alliance_colors enable row level security;
alter table alliance_colors force row level security;

drop policy if exists "ac_select" on alliance_colors;
create policy "ac_select" on alliance_colors for select
  using (current_player() is not null);

drop policy if exists "ac_write" on alliance_colors;
create policy "ac_write" on alliance_colors for all
  using (is_super_admin(current_player()))
  with check (is_super_admin(current_player()));

-- Seed the current roster (BST, PAC, SEA, WLF, WTP, (pac), LHC, DND).
-- PAC keeps FAL's old orange; WTP / (pac) reuse the now-free HUM / FAM hues.
insert into alliance_colors (alliance, color) values
  ('BST','#ff453a'),
  ('SEA','#52c759'),
  ('PAC','#ff9500'),
  ('WLF','#bf5af2'),
  ('LHC','#ffd60a'),
  ('DND','#30d158'),
  ('WTP','#2a9fd6'),
  ('(pac)','#ff6b6b')
on conflict (alliance) do nothing;

-- ═══════════════════ VERIFY (paste rows back) ══════════════════════════════
select 'players' t, alliance, count(*) from players group by alliance
union all select 'alliance_reps', alliance, count(*) from alliance_reps group by alliance
order by t, alliance;
select * from alliance_colors order by alliance;
