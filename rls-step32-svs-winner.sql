-- rls-step32-svs-winner.sql
-- The alliance with the most SvS points that month gets 2 Strongholds and 2 Forts each week.
-- rotation_state.svs_winner holds that alliance tag, set by the super admin, it stays until changed.
-- rotation_selections gets stronghold2 and fort2. For the winner, stronghold is the auto SH
-- carried over from last week and stronghold2 is the extra pick. Everyone else leaves them empty.
-- Policies and grants are unchanged: rotation_state is already super admin write only.
-- Run once in the Supabase SQL editor after rls-step31, then run the VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────
-- 1. Monthly SvS winner
-- ─────────────────────────────────────────────────────────────
alter table rotation_state
  add column if not exists svs_winner text;

-- ─────────────────────────────────────────────────────────────
-- 2. Second stronghold and second fort per selection
-- ─────────────────────────────────────────────────────────────
alter table rotation_selections
  add column if not exists stronghold2 int;
alter table rotation_selections
  add column if not exists fort2 int;

-- ─────────────────────────────────────────────────────────────
-- VERIFY: run this and paste the ROWS back
-- expect 3 rows: rotation_selections fort2 integer YES, rotation_selections stronghold2 integer YES, rotation_state svs_winner text YES
-- ─────────────────────────────────────────────────────────────
select table_name::text, column_name::text, data_type || ' ' || is_nullable as detail
from information_schema.columns
where table_schema = 'public'
  and ((table_name = 'rotation_state' and column_name = 'svs_winner')
    or (table_name = 'rotation_selections' and column_name in ('stronghold2', 'fort2')))
order by table_name, column_name;
