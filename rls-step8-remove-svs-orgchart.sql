-- Removes the SvS Rally Setup module and the Alliance Org Chart module (both dropped from the app).

-- Step 1: check who currently holds the svs_admin role before deleting it.
-- Run this first and review the output.
select player_name from admin_roles where role = 'svs_admin';

-- Step 2: once you've reviewed step 1, remove those role grants.
delete from admin_roles where role = 'svs_admin';

-- Step 3: drop the SvS Rally Setup table (policies are dropped automatically with the table).
drop table if exists svs_rally_leaders;

-- Step 4: drop the now-unused RLS helper function (only used by svs_rally_leaders' policy).
drop function if exists is_svs_admin(text);

-- Step 5: drop the Alliance Org Chart table (added this session, never used in production).
drop table if exists alliance_org_chart;

-- Note: the admin_roles.role CHECK constraint (defined directly in the Supabase dashboard,
-- not in this repo's SQL) still allows the string 'svs_admin' as a value — that's harmless
-- since nothing in the app can assign or read it anymore, so it's left untouched here.
