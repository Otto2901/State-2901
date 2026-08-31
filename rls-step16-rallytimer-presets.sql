-- rls-step16-rallytimer-presets.sql
-- Moves Rally Timer presets off per-device localStorage into a shared table so
-- every rally admin sees the same presets on any device (phone / PC).
--
-- Shared pool: any rally admin can read, add, and delete any preset.
-- Reuses is_rally_admin() from rls-step15-rallytimer-admin.sql. No admin_roles
-- CHECK change needed. No FK constraints, per this repo's convention.
--
-- Run once in the Supabase SQL editor as the project owner.

create table if not exists rally_timer_presets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  dur int not null default 300 check (dur in (60,180,300)),
  leaders jsonb not null default '[]'::jsonb,   -- [{name, march, active}]
  created_by text,
  created_at timestamptz not null default now()
);

alter table rally_timer_presets enable row level security;
alter table rally_timer_presets force row level security;

create policy "rtp_select" on rally_timer_presets for select
  using (is_rally_admin(current_player()));
create policy "rtp_write" on rally_timer_presets for all
  using (is_rally_admin(current_player()))
  with check (is_rally_admin(current_player()));

-- ── Verify after running (return the ROWS, not just "Success") ──
-- select tablename, policyname, cmd from pg_policies where tablename = 'rally_timer_presets';
--   expect 2 rows: rtp_select (SELECT), rtp_write (ALL)
-- select column_name, data_type from information_schema.columns
--   where table_name = 'rally_timer_presets' order by ordinal_position;
