-- The public list now shows each named person's role beside their university
-- (or "campus organizer" for people who volunteered). Adds role to board().
create or replace function public.board() returns jsonb
language sql stable security definer set search_path = public as $$
  with v as (select * from signups where verified_at is not null)
  select jsonb_build_object(
    'total', (select count(*) from v),
    'named', (select count(*) from v where show_name and name <> ''),
    'unis', coalesce((select jsonb_agg(jsonb_build_object('key', dom, 'name', uni, 'n', n, 'named', named) order by n desc, uni)
                      from (select dom, min(uni) uni, count(*) n, count(*) filter (where show_name and name <> '') named
                            from v group by dom) t), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'uni', uni, 'role', role, 'lead', lead) order by verified_at desc)
                        from (select name, uni, role, verified_at, 'lead' = any(spread) lead from v where show_name and name <> ''
                              order by verified_at desc limit 500) t), '[]'::jsonb),
    'answers', coalesce((select jsonb_object_agg(q, o)
                         from (select q, jsonb_object_agg(a, n) o
                               from (select e.key q, e.value a, count(*) n from v, jsonb_each_text(v.answers) e group by 1, 2) x
                               group by q) y), '{}'::jsonb));
$$;
