-- Castle War and SvS Prep modules have been fully removed from index.html
-- (client code, loadAll() queries, home cards, Admin Panel tab, edge function).
-- This drops the now-orphaned tables, RLS policies, and helper function on the DB side.
--
-- WARNING: this permanently deletes all data in these tables (rally history,
-- coordinator/rallier assignments, prep session/day/submission records).
-- Export/backup first if that data has any value, e.g.:
--   select * from castle_wars; select * from castle_rallies; -- etc.
-- Run in Supabase SQL editor, then verify with:
--   select tablename from pg_tables where tablename in
--     ('svsprep_sessions','svsprep_days','svsprep_submissions',
--      'castle_wars','castle_coordinators','castle_rallies','castle_ralliers');
--   -- should return 0 rows
--   select proname from pg_proc where proname = 'is_castle_coord'; -- should return 0 rows

drop table if exists svsprep_submissions;
drop table if exists svsprep_days;
drop table if exists svsprep_sessions;

drop table if exists castle_ralliers;
drop table if exists castle_rallies;
drop table if exists castle_coordinators;
drop table if exists castle_wars;

drop function if exists is_castle_coord(text, uuid);
