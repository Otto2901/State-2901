-- Run this in Supabase SQL Editor

-- Push subscriptions table (one row per device)
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  player_name  text NOT NULL,
  endpoint     text NOT NULL UNIQUE,
  subscription jsonb NOT NULL,
  created_at   timestamptz DEFAULT now()
);

-- Index for fast lookup by player name
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_player
  ON push_subscriptions(player_name);
