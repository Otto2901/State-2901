-- Run this once in the Supabase SQL Editor.
-- Step 14: War Team Builder refinement. A team is now either Attack OR
-- Defense (not both), squad members no longer carry their own troop
-- percentages (they follow the team's single formation ratio), and
-- Zinman is corrected from Support to Marksman.
--
-- Safe to run as a clean column swap (not a data-preserving migration)
-- because war_teams/war_team_members are confirmed empty as of this
-- writing. The SELECT below re-confirms that immediately before the
-- destructive column drops — if it returns anything other than 0, STOP
-- and do not run the rest of this file.

select count(*) as war_teams_row_count from war_teams; -- expect 0 — stop here if not

-- ── war_teams: replace the atk_*/def_* pair with one formation + a type flag ──
alter table war_teams drop constraint war_teams_atk_pct_check;
alter table war_teams drop constraint war_teams_def_pct_check;
alter table war_teams
  drop column atk_hero1, drop column atk_hero2, drop column atk_hero3,
  drop column atk_infantry_pct, drop column atk_lancer_pct, drop column atk_marksman_pct,
  drop column def_hero1, drop column def_hero2, drop column def_hero3,
  drop column def_infantry_pct, drop column def_lancer_pct, drop column def_marksman_pct;

alter table war_teams add column formation_type text not null default 'Attack';
alter table war_teams alter column formation_type drop default;
alter table war_teams add constraint war_teams_formation_type_check check (formation_type in ('Attack','Defense'));

alter table war_teams add column hero1 uuid, add column hero2 uuid, add column hero3 uuid;
alter table war_teams add column infantry_pct int not null default 0;
alter table war_teams add column lancer_pct   int not null default 0;
alter table war_teams add column marksman_pct int not null default 0;
alter table war_teams add constraint war_teams_pct_check check (infantry_pct + lancer_pct + marksman_pct = 100);

-- ── war_team_members: drop per-member percentages — members inherit the
-- team's single ratio, they only ever picked their own heroes ──
alter table war_team_members drop constraint war_team_members_pct_check;
alter table war_team_members drop column infantry_pct, drop column lancer_pct, drop column marksman_pct;

-- ── Data fix: Zinman is a Marksman hero, not Support ──
update war_heroes set class='Marksman' where name='Zinman';

-- ── Verify after running ──
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conname in ('war_teams_pct_check','war_teams_formation_type_check','war_team_members_pct_check');
--   -- expect: first two present, war_team_members_pct_check GONE (0 rows for that one)
-- select column_name from information_schema.columns where table_name='war_teams' order by column_name;
-- select column_name from information_schema.columns where table_name='war_team_members' order by column_name;
-- select name, class from war_heroes where name='Zinman'; -- expect class='Marksman'
