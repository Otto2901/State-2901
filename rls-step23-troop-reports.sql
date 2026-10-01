-- rls-step23-troop-reports.sql
-- Permanent troop level data collected with every SvS minister application,
-- for registered and unregistered players alike. One dated row per
-- application, so history builds up across SvS events. New SvS deletes
-- applications but NOT these rows.
--
-- Per troop type: tier T9, T10 or T11, plus FC level below, FC5 to FC10.
-- Super admin only. Public rows are written by the minister-apply edge
-- function with the service-role key, there is no anon policy.
-- application_id is a plain reference, no FK, per repo convention.
-- Run once in the Supabase SQL editor, then paste the VERIFY rows back.

create table if not exists player_troop_reports (
  id uuid primary key default gen_random_uuid(),
  player_id text not null,
  player_name text not null,
  inf_tier text not null check (inf_tier in ('T9','T10','T11')),
  inf_fc   text not null check (inf_fc   in ('below','FC5','FC6','FC7','FC8','FC9','FC10')),
  lan_tier text not null check (lan_tier in ('T9','T10','T11')),
  lan_fc   text not null check (lan_fc   in ('below','FC5','FC6','FC7','FC8','FC9','FC10')),
  mar_tier text not null check (mar_tier in ('T9','T10','T11')),
  mar_fc   text not null check (mar_fc   in ('below','FC5','FC6','FC7','FC8','FC9','FC10')),
  source text not null default 'public' check (source in ('public','admin')),
  entered_by text,
  svs_start_date date,
  application_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists player_troop_reports_player_id_idx on player_troop_reports (player_id);
create index if not exists player_troop_reports_application_id_idx on player_troop_reports (application_id);

alter table player_troop_reports enable row level security;
alter table player_troop_reports force row level security;

drop policy if exists "ptr_select" on player_troop_reports;
create policy "ptr_select" on player_troop_reports for select
  using (is_super_admin(current_player()));
drop policy if exists "ptr_insert" on player_troop_reports;
create policy "ptr_insert" on player_troop_reports for insert
  with check (is_super_admin(current_player()));
drop policy if exists "ptr_update" on player_troop_reports;
create policy "ptr_update" on player_troop_reports for update
  using (is_super_admin(current_player()))
  with check (is_super_admin(current_player()));
drop policy if exists "ptr_delete" on player_troop_reports;
create policy "ptr_delete" on player_troop_reports for delete
  using (is_super_admin(current_player()));

-- VERIFY: run this ONE query and paste the ROWS back
select 'policy' as kind, policyname as name, cmd || ' / ' || coalesce(qual, '') || ' / ' || coalesce(with_check, '') as detail
  from pg_policies where tablename = 'player_troop_reports'
union all
select 'rls', relname, relrowsecurity::text || ' / force ' || relforcerowsecurity::text
  from pg_class where relname = 'player_troop_reports'
order by 1, 2;
-- expect 4 policy rows ptr_delete, ptr_insert, ptr_select, ptr_update
-- all using is_super_admin, and one rls row: true / force true
