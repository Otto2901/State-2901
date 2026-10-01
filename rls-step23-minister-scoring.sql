-- rls-step23-minister-scoring.sql
-- Point values for the minister application score, set by super admin in
-- Admin Panel > Ministers > Setup. Two groups: vp for the VP days, edu for
-- the Minister of Education day. Speedup values are points per 1 minute,
-- item values are points per 1 item:
--   {"vp":{"construction":0,"research":0,"general":0,"fc":0,"rfc":0,"shards":0},
--    "edu":{...same keys...}}
-- Existing policies cover it: mc_select is public, mc_update super admin.
-- Run once in the Supabase SQL editor, then paste the VERIFY row back.

alter table minister_config add column if not exists score_weights jsonb not null default '{}'::jsonb;

-- VERIFY: expect 1 row, data_type jsonb, score_weights {}
select c.data_type, m.score_weights::text as score_weights
from information_schema.columns c, minister_config m
where c.table_name = 'minister_config' and c.column_name = 'score_weights' and m.id = 1;
