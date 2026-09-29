-- rls-step19-presidency.sql
-- Presidency Ledger module: SFC and SvS Supreme presidency rotation between
-- alliances, with a permanent record book and a tamper-proof audit log.
--
-- - presidency_queues: one row per type, alliances jsonb array, index 0 = next up
-- - presidency_records: every event, won or lost, including backfilled history
-- - presidency_audit_log: written ONLY by a DB trigger, readable only by super admin
--
-- New assignable role: presidency_admin. No FK constraints, per repo convention.
-- Run once in the Supabase SQL editor as the project owner, then run the
-- VERIFY queries at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Role + helper
-- ─────────────────────────────────────────────────────────────────────────────
alter table admin_roles drop constraint admin_roles_role_check;

alter table admin_roles add constraint admin_roles_role_check
  check (role = any (array[
    'super_admin','svs_admin','cj_admin','moderator','prep_admin',
    'album_admin','library_admin','stronghold_admin','war_admin','rally_admin',
    'presidency_admin'
  ]));

create or replace function is_presidency_admin(p text) returns boolean
language sql security definer stable as $$
  select is_super_admin(p) or has_role(p, 'presidency_admin');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Tables
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists presidency_queues (
  type text primary key check (type in ('sfc','supreme')),
  alliances jsonb not null default '[]'::jsonb,
  updated_by text,
  updated_at timestamptz not null default now()
);

insert into presidency_queues (type) values ('sfc'), ('supreme')
  on conflict (type) do nothing;

create table if not exists presidency_records (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('sfc','supreme')),
  event_date date not null,
  outcome text not null check (outcome in ('won','lost')),
  alliance text,
  president_name text,
  has_tm boolean not null default false,
  notes text,
  is_backfill boolean not null default false,
  created_by text,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz,
  constraint presidency_won_needs_alliance
    check (outcome = 'lost' or alliance is not null)
);

create table if not exists presidency_audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor text,
  table_name text not null,
  op text not null,
  row_key text,
  old_row jsonb,
  new_row jsonb
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Audit trigger. Runs as the function owner so it can write the log even
--    though clients have no insert policy on it. Actor comes from the session
--    token header, so a direct REST write via devtools is logged just the same.
--    Actor falls back to sql-editor when there is no app session.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function presidency_audit() returns trigger
language plpgsql security definer as $$
declare
  o jsonb;
  n jsonb;
begin
  if tg_op in ('UPDATE','DELETE') then o := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then n := to_jsonb(new); end if;
  insert into presidency_audit_log (actor, table_name, op, row_key, old_row, new_row)
  values (
    coalesce(current_player(), 'sql-editor'),
    tg_table_name,
    tg_op,
    coalesce(n->>'id', o->>'id', n->>'type', o->>'type'),
    o,
    n
  );
  return null;
end;
$$;

drop trigger if exists presidency_queues_audit on presidency_queues;
create trigger presidency_queues_audit
  after insert or update or delete on presidency_queues
  for each row execute function presidency_audit();

drop trigger if exists presidency_records_audit on presidency_records;
create trigger presidency_records_audit
  after insert or update or delete on presidency_records
  for each row execute function presidency_audit();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table presidency_queues enable row level security;
alter table presidency_queues force row level security;
alter table presidency_records enable row level security;
alter table presidency_records force row level security;
-- Audit log: RLS on but NOT forced, so the trigger owner can insert.
-- Clients get select for super admin only and no write policy at all.
alter table presidency_audit_log enable row level security;

drop policy if exists "pq_select" on presidency_queues;
create policy "pq_select" on presidency_queues for select
  using (current_player() is not null);
drop policy if exists "pq_update" on presidency_queues;
create policy "pq_update" on presidency_queues for update
  using (is_presidency_admin(current_player()))
  with check (is_presidency_admin(current_player()));

drop policy if exists "pr_select" on presidency_records;
create policy "pr_select" on presidency_records for select
  using (current_player() is not null);
drop policy if exists "pr_insert" on presidency_records;
create policy "pr_insert" on presidency_records for insert
  with check (is_presidency_admin(current_player()));
drop policy if exists "pr_update" on presidency_records;
create policy "pr_update" on presidency_records for update
  using (is_presidency_admin(current_player()))
  with check (is_presidency_admin(current_player()));
drop policy if exists "pr_delete" on presidency_records;
create policy "pr_delete" on presidency_records for delete
  using (is_super_admin(current_player()));

drop policy if exists "pal_select" on presidency_audit_log;
create policy "pal_select" on presidency_audit_log for select
  using (is_super_admin(current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run these and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select tablename, policyname, cmd from pg_policies
where tablename in ('presidency_queues','presidency_records','presidency_audit_log')
order by tablename, policyname;
-- expect 7 rows: pal_select, pq_select, pq_update, pr_delete, pr_insert, pr_select, pr_update

select tgname, tgrelid::regclass from pg_trigger
where tgname in ('presidency_queues_audit','presidency_records_audit');
-- expect 2 rows

select proname from pg_proc where proname in ('is_presidency_admin','presidency_audit');
-- expect 2 rows

select pg_get_constraintdef(oid) from pg_constraint where conname = 'admin_roles_role_check';
-- expect presidency_admin in the list

select type, alliances from presidency_queues;
-- expect 2 rows: sfc and supreme, both []

update presidency_queues set updated_at = now() where type = 'sfc';
select actor, table_name, op, row_key from presidency_audit_log;
-- expect 1 UPDATE row for sfc with actor sql-editor, proves the trigger works
