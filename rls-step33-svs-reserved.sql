-- rls-step33-svs-reserved.sql
-- Lets the super admin override which Strongholds are reserved for the SvS winner this week,
-- for rare in-game cases such as the winner being auto-registered on 2 Strongholds.
-- Shape: {"week":"YYYY-MM-DD","sh":[1,3]}. It only applies while week matches the current
-- rotation week, so it lapses by itself. Null means automatic, from last week's pick.
-- Policies and grants are unchanged: rotation_state is already super admin write only.
-- Run once in the Supabase SQL editor after rls-step32, then run the VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────
-- 1. Weekly reserved SH override
-- ─────────────────────────────────────────────────────────────
alter table rotation_state
  add column if not exists svs_reserved jsonb;

-- ─────────────────────────────────────────────────────────────
-- VERIFY: run this and paste the ROWS back
-- expect 1 row: rotation_state | svs_reserved | jsonb YES
-- ─────────────────────────────────────────────────────────────
select table_name::text, column_name::text, data_type || ' ' || is_nullable as detail
from information_schema.columns
where table_schema = 'public' and table_name = 'rotation_state' and column_name = 'svs_reserved';
