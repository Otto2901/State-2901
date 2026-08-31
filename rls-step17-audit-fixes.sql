-- rls-step17-audit-fixes.sql
-- Fixes found in the 2026-08-31 full-system audit. Run in the Supabase SQL editor
-- as the project owner. Each block is independent. After running, execute the
-- VERIFY queries at the bottom and paste the ROWS back (not just "Success").
--
-- Reuses helpers from rls-step2/3: current_player(), is_super_admin(), has_role().

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. id_change_requests: add the missing DELETE policy.
--    The table has FORCE RLS and only select/insert/update policies, so the
--    client's delete during player-removal / ID-change approval is a silent
--    no-op and pending requests for deleted players dangle forever.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "id_change_requests_delete" on id_change_requests;
create policy "id_change_requests_delete" on id_change_requests for delete
  using (is_super_admin(current_player()) or player_name = current_player());

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. push_subscriptions: allow a super admin to manage other players' rows.
--    Current policies are all self-only (player_name = current_player()), so the
--    super-admin account-delete / rename flow cannot touch a deleted player's
--    subscription -> orphaned rows, deleted player keeps getting push.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "push_subscriptions_delete" on push_subscriptions;
create policy "push_subscriptions_delete" on push_subscriptions for delete
  using (player_name = current_player() or is_super_admin(current_player()));

drop policy if exists "push_subscriptions_update" on push_subscriptions;
create policy "push_subscriptions_update" on push_subscriptions for update
  using (player_name = current_player() or is_super_admin(current_player()))
  with check (player_name = current_player() or is_super_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. is_rally_admin: make it SECURITY DEFINER like every other RLS helper.
--    Currently the only helper without it; works only by delegating to
--    has_role() (which is definer). Fragile.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function is_rally_admin(p text) returns boolean
language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'rally_admin');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. notifications.role column — the client's grantRole() inserts it and
--    showPendingRoleNotifs() reads it to show a "View Guide" button, but the
--    live table has no such column, so the whole role-grant notification 400s
--    silently. (rls-step11 was supposed to add this; evidently never applied.)
-- ─────────────────────────────────────────────────────────────────────────────
alter table notifications add column if not exists role text;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Drop the orphaned SvS-Prep helper (module removed in rls-step5, this was
--    missed). References the dead 'prep_admin' role.
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists is_svsp_admin(text);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. rules_topics — CHECK FIRST, then act. rules-step12 made select public
--    (using(true)) by design, but an old permissive "anon all" policy from an
--    early RLS attempt may still exist under a different name and let anon
--    WRITE. Run the SELECT below; if any policy other than
--    'rules_topics_select' and 'rules_topics_write' shows up, drop it by name.
-- ─────────────────────────────────────────────────────────────────────────────
--   select policyname, cmd, qual, with_check from pg_policies where tablename='rules_topics';
--   -- then, for each unexpected policy:
--   -- drop policy "<policyname>" on rules_topics;


-- ═════════════════════════════ VERIFY (paste rows back) ══════════════════════
select tablename, policyname, cmd
from pg_policies
where tablename in ('id_change_requests','push_subscriptions','rules_topics')
order by tablename, policyname;

select proname, prosecdef as is_security_definer
from pg_proc where proname in ('is_rally_admin','is_svsp_admin');

select column_name from information_schema.columns
where table_name='notifications' and column_name='role';
