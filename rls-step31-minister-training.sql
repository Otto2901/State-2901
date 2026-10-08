-- rls-step31-minister-training.sql
-- The minister application form asked for Construction, Research and General speedups,
-- but not Training speedups. Day 4 Minister of Education boosts troop training, so the
-- Education rank now uses Training plus General. This adds the speed_training column.
-- Older applications get 0. Policies and grants are unchanged.
-- Run once in the Supabase SQL editor after rls-step30, then run the VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────
-- 1. New column
-- ─────────────────────────────────────────────────────────────
alter table minister_applications
  add column if not exists speed_training numeric not null default 0;

-- ─────────────────────────────────────────────────────────────
-- VERIFY: run this and paste the ROWS back
-- expect 1 row: column | speed_training | numeric NO 0
-- expect 1 row: rows | total applications | a number, every row has a value
-- ─────────────────────────────────────────────────────────────
select 'column' as check_name, column_name::text as item,
       data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '') as detail
from information_schema.columns
where table_schema = 'public' and table_name = 'minister_applications' and column_name = 'speed_training'
union all
select 'rows', 'total applications',
       count(*)::text || ' total, ' || count(speed_training)::text || ' with a value'
from minister_applications;
