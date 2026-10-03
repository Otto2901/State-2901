-- rls-step30-player-delete-cleanup.sql
-- When a player account is deleted, its session tokens stayed valid for up to 30 days,
-- because the sessions table has no client policies and the app could not clear it.
-- If someone later registered the same name, an old token would act as the new account.
-- This trigger runs inside the same delete on players and removes the player's
-- sessions and push subscriptions, for every delete path.
-- Run once in the Supabase SQL editor after rls-step29, then run the VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────
-- 1. Cleanup function
-- ─────────────────────────────────────────────────────────────
create or replace function cleanup_deleted_player()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from sessions where player_name = old.name;
  delete from push_subscriptions where player_name = old.name;
  return old;
end;
$$;

revoke all on function cleanup_deleted_player() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 2. Trigger on players
-- ─────────────────────────────────────────────────────────────
drop trigger if exists players_delete_cleanup on players;
create trigger players_delete_cleanup
  after delete on players
  for each row execute function cleanup_deleted_player();

-- ─────────────────────────────────────────────────────────────
-- VERIFY: run this and paste the ROWS back
-- ─────────────────────────────────────────────────────────────
-- expect 3 rows:
--   function | cleanup_deleted_player | true
--   trigger  | players_delete_cleanup | true
--   policy   | push_subscriptions_delete | true
select 'function' as kind, proname::text as name, prosecdef as ok
  from pg_proc where proname = 'cleanup_deleted_player'
union all
select 'trigger', tgname::text, tgenabled <> 'D'
  from pg_trigger where tgname = 'players_delete_cleanup' and tgrelid = 'public.players'::regclass
union all
select 'policy', policyname::text, qual like '%is_super_admin%'
  from pg_policies where tablename = 'push_subscriptions' and policyname = 'push_subscriptions_delete';
