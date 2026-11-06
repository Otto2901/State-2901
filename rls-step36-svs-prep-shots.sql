-- rls-step36-svs-prep-shots.sql
-- SvS Prep Records get screenshots: at most 5 per record.
--
--   svs_prep_records.shots  ranked JSON list of the record's screenshots,
--                           shots = [{"path":"<uuid>.webp","w":2560,"h":1180}]
--   bucket svs-prep-shots   PRIVATE. Files are only reached through short
--                           signed links, never a public address.
--
-- Same rule as the records: super admin and svslog_viewer can look, only the
-- super admin uploads or deletes. Signed out visitors and other players see
-- nothing, not even the file list. Files are shrunk on the device to a long
-- side of 2560 px, WebP or JPEG, at most 5 MB.
--
-- Run once in the Supabase SQL editor after rls-step35, then run the VERIFY
-- query at the bottom and paste the ROWS back.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Column on the records
-- ─────────────────────────────────────────────────────────────────────────────
alter table svs_prep_records add column if not exists shots jsonb not null default '[]'::jsonb;

alter table svs_prep_records drop constraint if exists svs_prep_records_shots_check;
alter table svs_prep_records add constraint svs_prep_records_shots_check
  check (jsonb_typeof(shots) = 'array' and jsonb_array_length(shots) <= 5);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Private bucket
-- ─────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('svs-prep-shots', 'svs-prep-shots', false, 5242880, array['image/webp','image/jpeg'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/webp','image/jpeg'];

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Who may touch the files
-- ─────────────────────────────────────────────────────────────────────────────
-- A file name is a random id plus .webp or .jpg, no folders.
drop policy if exists "sps_select" on storage.objects;
create policy "sps_select" on storage.objects for select
  using (bucket_id = 'svs-prep-shots' and public.is_svslog_viewer(public.current_player()));

drop policy if exists "sps_insert" on storage.objects;
create policy "sps_insert" on storage.objects for insert
  with check (bucket_id = 'svs-prep-shots'
    and public.is_super_admin(public.current_player())
    and name ~ '^[0-9a-f-]{36}\.(webp|jpg)$');

drop policy if exists "sps_update" on storage.objects;
create policy "sps_update" on storage.objects for update
  using (bucket_id = 'svs-prep-shots' and public.is_super_admin(public.current_player()))
  with check (bucket_id = 'svs-prep-shots' and public.is_super_admin(public.current_player()));

drop policy if exists "sps_delete" on storage.objects;
create policy "sps_delete" on storage.objects for delete
  using (bucket_id = 'svs-prep-shots' and public.is_super_admin(public.current_player()));

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: run this ONE query and paste the ROWS back
-- ─────────────────────────────────────────────────────────────────────────────
select 'column' as kind, column_name as name, data_type || ' default ' || column_default as detail
  from information_schema.columns where table_name = 'svs_prep_records' and column_name = 'shots'
union all
select 'check', conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'svs_prep_records_shots_check'
union all
select 'bucket', id, 'public ' || public::text || ' / limit ' || file_size_limit::text || ' / ' || array_to_string(allowed_mime_types, ',')
  from storage.buckets where id = 'svs-prep-shots'
union all
select 'policy', policyname, cmd from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and (policyname like 'sps\_%' or coalesce(qual, '') like '%svs-prep-shots%' or coalesce(with_check, '') like '%svs-prep-shots%'
         or coalesce(qual, '') in ('true', '') )
order by 1, 2;
-- expect 7 rows: column shots jsonb, 1 check row with jsonb_array_length,
-- bucket row "public false / limit 5242880 / image/webp,image/jpeg",
-- 4 policy rows: sps_delete DELETE, sps_insert INSERT, sps_select SELECT, sps_update UPDATE.
-- Any OTHER policy row is a leftover that opens every bucket: paste it back, do not ignore it.
