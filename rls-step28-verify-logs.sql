-- rls-step28-verify-logs.sql
-- Read-only check of the central log set up in rls-step27. Its VERIFY rows
-- were never pasted back, so this confirms in one query that the audit
-- triggers are on every admin-written table, the PIN never reaches the log,
-- and the old Presidency rows were copied. Nothing is created or changed.
-- Run once in the Supabase SQL editor after rls-step27, then paste the ROWS back.

select 1 as n, 'policies on log tables' as check_name,
       string_agg(tablename || '.' || policyname || ' ' || cmd, ', ' order by tablename, policyname) as result,
       'al_select SELECT, ce_select SELECT' as expected
  from pg_policies where tablename in ('audit_log','client_errors')
union all
select 2, 'audit_row triggers',
       count(*)::text, '24 or more'
  from pg_trigger t join pg_proc p on p.oid = t.tgfoid
  where p.proname = 'audit_row' and not t.tgisinternal
union all
select 3, 'log functions',
       string_agg(proname, ', ' order by proname), 'audit_row, log_client_error, prune_logs'
  from pg_proc where proname in ('audit_row','log_client_error','prune_logs')
union all
select 4, 'tables without audit trigger',
       coalesce(string_agg(c.relname, ', ' order by c.relname), 'none'), 'none'
  from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind = 'r'
    and c.relname not in ('push_subscriptions','notifications','sessions','login_failures',
                          'minister_submit_rate','audit_log','client_errors','presidency_audit_log')
    and not exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = c.oid and p.proname = 'audit_row' and not t.tgisinternal)
union all
select 5, 'log rows containing a PIN',
       count(*)::text, '0'
  from audit_log where old_row ? 'pin' or new_row ? 'pin'
union all
select 6, 'presidency rows old vs copied',
       (select count(*) from presidency_audit_log)::text || ' vs ' ||
       (select count(*) from audit_log where table_name like 'presidency%')::text,
       'second number equal or larger'
union all
select 7, 'audit_log rows total',
       count(*)::text, 'more than 0 if anything was edited since step 27'
  from audit_log
union all
select 8, 'old is_svsp_admin function',
       count(*)::text, '0'
  from pg_proc where proname = 'is_svsp_admin'
order by n;
-- expect 8 rows, each result matching its expected column
