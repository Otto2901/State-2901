-- Run this once in the Supabase SQL Editor (Project > SQL Editor > New query > paste > Run).
-- Step 1 of the security hardening: a server-issued session token table.

create table if not exists sessions (
  token       text primary key default encode(gen_random_bytes(32), 'hex'),
  player_name text not null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default (now() + interval '30 days')
);

alter table sessions enable row level security;
-- Intentionally no policies added: with RLS on and zero policies, the
-- anon key (what the browser uses) has ZERO access to this table --
-- no select/insert/update/delete. Only server-side code using the
-- service role key (our edge functions) can read or write it. Nobody
-- in a browser can forge or read someone else's session token.
