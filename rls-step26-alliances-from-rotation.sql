-- rls-step26-alliances-from-rotation.sql
-- state_alliances now lists the alliances in Rotation order, Top 4 then
-- Bot 5, from rotation_state row 1, the same list the app shows. Colours
-- still come from alliance_colors. Stale rows in alliance_colors no longer
-- reach the application form.
-- to_jsonb works whether the order columns are text arrays or jsonb.
--
-- Run once in the Supabase SQL editor after rls-step25, then run the
-- VERIFY query at the bottom and paste the ROWS back.

create or replace function state_alliances()
returns table (alliance text, color text)
language sql security definer stable
set search_path = public
as $$
  select a.tag, coalesce(c.color, '#a3b3c2')
  from rotation_state r
  cross join lateral (
    select t.tag, t.ord from jsonb_array_elements_text(coalesce(to_jsonb(r.top4_order), '[]'::jsonb)) with ordinality as t(tag, ord)
    union all
    select t.tag, 100 + t.ord from jsonb_array_elements_text(coalesce(to_jsonb(r.bot5_order), '[]'::jsonb)) with ordinality as t(tag, ord)
  ) a
  left join alliance_colors c on c.alliance = a.tag
  where r.id = 1
  order by a.ord;
$$;

revoke all on function state_alliances() from public;
grant execute on function state_alliances() to anon, authenticated;

-- VERIFY: run this ONE query and paste the ROWS back
select alliance, color from state_alliances();
-- expect the alliances exactly as Rotation shows them, in the same order
