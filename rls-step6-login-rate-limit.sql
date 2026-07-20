-- Brute-force protection for the login edge function: tracks failed PIN
-- attempts per player_name and locks the account out for 15 minutes
-- after 5 consecutive failures. Only edge-functions/login/index.ts
-- (service-role key) reads/writes this table.

create table if not exists login_failures (
  player_name   text primary key,
  attempt_count int not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now()
);

alter table login_failures enable row level security;
-- Same pattern as sessions-setup.sql: RLS on, zero policies -- anon/
-- authenticated have no access at all, only the service-role key
-- (used exclusively by the login edge function) can read or write.
