-- rls-step27-audit-log.sql
-- One central log for the whole app, readable by super admin only.
--   audit_log      who changed what, on every admin-meaningful table,
--                  Presidency included. Old presidency_audit_log rows are
--                  copied in; that table is kept untouched as a backup.
--   client_errors  JavaScript errors from players' devices, written only
--                  through the log_client_error RPC, which caps length and rate.
--   prune_logs     retention: changes 180 days, errors 30 days. The app calls
--                  it when a super admin opens Admin Panel, Logs tab.
-- PIN hashes and device keys are stripped before anything is stored. A
-- failure inside the logger never blocks the real write.
--
-- Run once in the Supabase SQL editor after rls-step26, then run the
-- VERIFY query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor text,
  table_name text not null,
  op text not null,
  row_key text,
  old_row jsonb,
  new_row jsonb
);
create index if not exists audit_log_at_idx on audit_log (at desc);
create index if not exists audit_log_table_at_idx on audit_log (table_name, at desc);

create table if not exists client_errors (
  id bigserial primary key,
  at timestamptz not null default now(),
  player text,
  message text,
  source text,
  line int,
  stack text,
  ua text,
  url text,
  app_version text
);
create index if not exists client_errors_at_idx on client_errors (at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Audit trigger. Runs as the function owner so it can write the log even
--    though clients have no insert policy. Actor comes from the session token
--    header; edge functions and the SQL editor show up as system.
--    Sensitive keys are removed. A PIN change is recorded as pin_changed only.
--    Updates that change nothing visible are skipped.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function audit_row() returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  o jsonb;
  n jsonb;
  pin_changed boolean := false;
begin
  begin
    if tg_op in ('UPDATE','DELETE') then o := to_jsonb(old); end if;
    if tg_op in ('INSERT','UPDATE') then n := to_jsonb(new); end if;
    if tg_op = 'UPDATE' and (o->>'pin') is distinct from (n->>'pin') then
      pin_changed := true;
    end if;
    o := o - 'pin' - 'token' - 'endpoint' - 'p256dh' - 'auth';
    n := n - 'pin' - 'token' - 'endpoint' - 'p256dh' - 'auth';
    if tg_op = 'UPDATE' and o = n and not pin_changed then
      return null;
    end if;
    if pin_changed then
      n := n || jsonb_build_object('pin_changed', true);
    end if;
    insert into audit_log (actor, table_name, op, row_key, old_row, new_row)
    values (
      coalesce(current_player(), 'system'),
      tg_table_name,
      tg_op,
      coalesce(n->>'id', o->>'id', n->>'player_name', o->>'player_name',
               n->>'name', o->>'name', n->>'type', o->>'type',
               n->>'alliance', o->>'alliance'),
      o,
      n
    );
  exception when others then
    raise warning 'audit_row failed on %: %', tg_table_name, sqlerrm;
  end;
  return null;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Attach the trigger. push_subscriptions, notifications, sessions and
--    login_failures are left out on purpose: system noise and device keys.
-- ─────────────────────────────────────────────────────────────────────────────
drop trigger if exists audit_players on players;
create trigger audit_players after insert or update or delete on players
  for each row execute function audit_row();
drop trigger if exists audit_admin_roles on admin_roles;
create trigger audit_admin_roles after insert or update or delete on admin_roles
  for each row execute function audit_row();
drop trigger if exists audit_alliance_reps on alliance_reps;
create trigger audit_alliance_reps after insert or update or delete on alliance_reps
  for each row execute function audit_row();
drop trigger if exists audit_alliance_colors on alliance_colors;
create trigger audit_alliance_colors after insert or update or delete on alliance_colors
  for each row execute function audit_row();
drop trigger if exists audit_rotation_state on rotation_state;
create trigger audit_rotation_state after insert or update or delete on rotation_state
  for each row execute function audit_row();
drop trigger if exists audit_rotation_selections on rotation_selections;
create trigger audit_rotation_selections after insert or update or delete on rotation_selections
  for each row execute function audit_row();
drop trigger if exists audit_location_rewards on location_rewards;
create trigger audit_location_rewards after insert or update or delete on location_rewards
  for each row execute function audit_row();
drop trigger if exists audit_transfer_periods on transfer_periods;
create trigger audit_transfer_periods after insert or update or delete on transfer_periods
  for each row execute function audit_row();
drop trigger if exists audit_transfer_invites on transfer_invites;
create trigger audit_transfer_invites after insert or update or delete on transfer_invites
  for each row execute function audit_row();
drop trigger if exists audit_id_change_requests on id_change_requests;
create trigger audit_id_change_requests after insert or update or delete on id_change_requests
  for each row execute function audit_row();
drop trigger if exists audit_rules_topics on rules_topics;
create trigger audit_rules_topics after insert or update or delete on rules_topics
  for each row execute function audit_row();
drop trigger if exists audit_library_entries on library_entries;
create trigger audit_library_entries after insert or update or delete on library_entries
  for each row execute function audit_row();
drop trigger if exists audit_cj_teams on cj_teams;
create trigger audit_cj_teams after insert or update or delete on cj_teams
  for each row execute function audit_row();
drop trigger if exists audit_cj_team_members on cj_team_members;
create trigger audit_cj_team_members after insert or update or delete on cj_team_members
  for each row execute function audit_row();
drop trigger if exists audit_war_teams on war_teams;
create trigger audit_war_teams after insert or update or delete on war_teams
  for each row execute function audit_row();
drop trigger if exists audit_war_team_members on war_team_members;
create trigger audit_war_team_members after insert or update or delete on war_team_members
  for each row execute function audit_row();
drop trigger if exists audit_war_heroes on war_heroes;
create trigger audit_war_heroes after insert or update or delete on war_heroes
  for each row execute function audit_row();
drop trigger if exists audit_minister_config on minister_config;
create trigger audit_minister_config after insert or update or delete on minister_config
  for each row execute function audit_row();
drop trigger if exists audit_minister_applications on minister_applications;
create trigger audit_minister_applications after insert or update or delete on minister_applications
  for each row execute function audit_row();
drop trigger if exists audit_minister_assignments on minister_assignments;
create trigger audit_minister_assignments after insert or update or delete on minister_assignments
  for each row execute function audit_row();
drop trigger if exists audit_player_troop_reports on player_troop_reports;
create trigger audit_player_troop_reports after insert or update or delete on player_troop_reports
  for each row execute function audit_row();
drop trigger if exists audit_rally_timer_presets on rally_timer_presets;
create trigger audit_rally_timer_presets after insert or update or delete on rally_timer_presets
  for each row execute function audit_row();

-- Presidency moves to the central log. Old triggers are replaced, old rows
-- copied once. presidency_audit_log itself stays as a backup.
drop trigger if exists presidency_queues_audit on presidency_queues;
create trigger presidency_queues_audit after insert or update or delete on presidency_queues
  for each row execute function audit_row();
drop trigger if exists presidency_records_audit on presidency_records;
create trigger presidency_records_audit after insert or update or delete on presidency_records
  for each row execute function audit_row();

insert into audit_log (at, actor, table_name, op, row_key, old_row, new_row)
select p.at, p.actor, p.table_name, p.op, p.row_key, p.old_row, p.new_row
from presidency_audit_log p
where not exists (
  select 1 from audit_log a
  where a.table_name = p.table_name and a.at = p.at and a.op = p.op
    and a.row_key is not distinct from p.row_key
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Client error RPC. Anyone may call it, logged in or not, but the player
--    name is taken from the session, fields are cut to size, and it stops
--    accepting after 20 rows per player in 10 minutes, 300 overall.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function log_client_error(
  p_message text, p_source text, p_line int, p_stack text,
  p_ua text, p_url text, p_version text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me text := current_player();
begin
  if (select count(*) from client_errors
      where at > now() - interval '10 minutes'
        and player is not distinct from me) >= 20 then
    return;
  end if;
  if (select count(*) from client_errors
      where at > now() - interval '10 minutes') >= 300 then
    return;
  end if;
  insert into client_errors (player, message, source, line, stack, ua, url, app_version)
  values (me, left(p_message, 500), left(p_source, 300), p_line,
          left(p_stack, 2000), left(p_ua, 300), left(p_url, 300), left(p_version, 40));
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Retention. Super admin only, called by the app on opening the Logs tab.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function prune_logs() returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not is_super_admin(current_player()) then return; end if;
  delete from audit_log where at < now() - interval '180 days';
  delete from client_errors where at < now() - interval '30 days';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RLS. On but NOT forced, so the definer functions can write. Clients get
--    select for super admin only and no write policy at all.
-- ─────────────────────────────────────────────────────────────────────────────
alter table audit_log enable row level security;
alter table client_errors enable row level security;

drop policy if exists "al_select" on audit_log;
create policy "al_select" on audit_log for select
  using (is_super_admin(current_player()));
drop policy if exists "ce_select" on client_errors;
create policy "ce_select" on client_errors for select
  using (is_super_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run these and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select tablename, policyname, cmd from pg_policies
where tablename in ('audit_log','client_errors')
order by tablename, policyname;
-- expect 2 rows: al_select, ce_select, both SELECT

select count(*) as audit_triggers from pg_trigger t join pg_proc p on p.oid = t.tgfoid
where p.proname = 'audit_row' and not t.tgisinternal;
-- expect 24

select proname from pg_proc
where proname in ('audit_row','log_client_error','prune_logs') order by proname;
-- expect 3 rows

select (select count(*) from presidency_audit_log) as old_rows,
       (select count(*) from audit_log where table_name like 'presidency%') as copied_rows;
-- expect copied_rows equal to old_rows

update presidency_queues set updated_at = now() where type = 'sfc';
select actor, table_name, op, row_key from audit_log order by id desc limit 1;
-- expect 1 UPDATE row on presidency_queues, row_key sfc, actor system

select count(*) as rows_with_pin from audit_log
where old_row ? 'pin' or new_row ? 'pin';
-- expect 0
