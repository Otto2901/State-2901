-- Run this once in the Supabase SQL Editor.
-- Step 10: in-app notifications so a player finds out on next login that
-- they were granted an admin role, instead of only super admins seeing it
-- in the Admin Roles panel.

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  player_name text not null,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table notifications enable row level security;

-- Reuses current_player() and is_super_admin() from rls-step2-critical-locks.sql.
create policy "notifications_select" on notifications
  for select using (player_name = current_player());

create policy "notifications_update" on notifications
  for update using (player_name = current_player()) with check (player_name = current_player());

create policy "notifications_insert" on notifications
  for insert with check (is_super_admin(current_player()));
