-- Allow rules_topics to be read before login (anon), so new players can
-- see the state's rules on the Auth screen before registering. Write
-- access stays super-admin-only, unchanged.
drop policy if exists "rules_topics_select" on rules_topics;
create policy "rules_topics_select" on rules_topics for select using (true);
