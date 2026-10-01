-- rls-step22-taken-slot-names.sql
-- Public Availability now shows the player NAME on assigned slots, so
-- players can see they got a time. Still never returns Player ID or
-- resources, and pending applications stay invisible.
--
-- The return type changes, so the function is dropped and recreated.
-- Run once in the Supabase SQL editor, then paste the VERIFY row back.

drop function if exists minister_taken_slots();

create function minister_taken_slots()
returns table (pos text, slot int, player_name text)
language sql security definer stable
set search_path = public
as $$
  select s."position", s.slot, a.player_name
  from minister_assignments s
  left join minister_applications a on a.id = s.application_id;
$$;

revoke all on function minister_taken_slots() from public;
grant execute on function minister_taken_slots() to anon, authenticated;

-- VERIFY: expect 1 row, prosecdef true,
-- result = TABLE pos text, slot integer, player_name text
select proname, prosecdef, pg_get_function_result(oid) as result
from pg_proc where proname = 'minister_taken_slots';
