-- The site no longer asks campus organizers for a phone number. Volunteering as an organizer no longer waits for one,
-- and the public list marks organizers whether or not a number is on file. The phone column stays (see the note on
-- sweep_unconfirmed: columns of signups must not change), and numbers given before stay visible to admins only.

CREATE OR REPLACE FUNCTION public.board()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with v as (
    select s.*, (select m.name from majors m where lower(m.name) = lower(s.major) limit 1) major_ok,
      case s.role when 'an undergraduate' then 'Undergraduate' when 'a graduate student' then 'Graduate student'
        when 'a postdoc' then 'Postdoc' when 'faculty' then 'Faculty' when 'staff' then 'Staff' else '' end role_label,
      case when s.role = 'an undergraduate' and s.year in ('Freshman', 'Sophomore', 'Junior', 'Senior') then s.year else '' end year_ok
    from signups s where s.verified_at is not null)
  select jsonb_build_object(
    'total', (select count(*) from v),
    'named', (select count(*) from v where show_name and name <> '' and not name_hidden),
    'unis', coalesce((select jsonb_agg(jsonb_build_object('key', t.dom, 'name', t.uni, 'n', t.n, 'day', t.d24, 'named', t.named, 'x', d.mx, 'y', d.my) order by t.n desc, t.uni)
                      from (select dom, min(uni) uni, count(*) n, count(*) filter (where verified_at > now() - interval '24 hours') as d24, count(*) filter (where show_name and name <> '' and not name_hidden) named
                            from v group by dom) t left join uni_domains d on d.domain = t.dom), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'uni', uni, 'lead', lead, 'info', info) order by verified_at desc)
                        from (select regexp_replace(trim(name), '^(\S+)\s+(?:.*\s)?(\S)\S*$', '\1 \2.') name, uni, verified_at, ('lead' = any(spread)) lead,
                                case when show_info then concat_ws(', ',
                                  nullif(case when role in ('faculty', 'staff') and title <> '' and name_ok(title) then title when year_ok <> '' then year_ok else role_label end, ''),
                                  major_ok) else '' end info
                              from v where show_name and name <> '' and not name_hidden
                              order by verified_at desc limit 500) t), '[]'::jsonb),
    'demo', jsonb_build_object(
      'role', coalesce((select jsonb_object_agg(k, n) from (select role_label k, count(*) n from v where role_label <> '' group by 1) t), '{}'::jsonb),
      'year', coalesce((select jsonb_object_agg(k, n) from (select year_ok k, count(*) n from v where year_ok <> '' group by 1) t), '{}'::jsonb),
      'major', coalesce((select jsonb_agg(jsonb_build_array(k, n) order by n desc, k)
                         from (select major_ok k, count(*) n from v where major_ok is not null group by 1 order by 2 desc, 1 limit 8) t), '[]'::jsonb)),
    'answers', coalesce((select jsonb_object_agg(q, o)
                         from (select q, jsonb_object_agg(a, n) o
                               from (select e.key q, e.value a, count(*) n from v, jsonb_each_text(v.answers) e group by 1, 2) x
                               group by q) y), '{}'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.submit_interest_unlimited(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e text := lower(trim(coalesce(p->>'email', ''))); u jsonb; t uuid; rf text;
begin
  if e !~ '^[^\s@]+@[^\s@]+$' or length(e) > 160 then raise exception 'bad_email'; end if;
  u := lookup_uni(e);
  if u is null then raise exception 'not_university'; end if;
  if trim(coalesce(p->>'name', '')) = '' then raise exception 'no_name'; end if;
  if jsonb_typeof(p->'answers') is distinct from 'object' or length((p->'answers')::text) > 2000 then
    raise exception 'bad_answers';
  end if;
  perform sweep_unconfirmed();
  insert into signups (ref_by, email, name, name_hidden, show_name, show_info, title, phone, major, role, year, uni, dom, answers, concern, letter, spread)
  values (coalesce((select ref from signups where ref = p->>'ref_by' and email <> e), ''), e, left(coalesce(p->>'name', ''), 120), not name_ok(left(coalesce(p->>'name', ''), 120)), coalesce((p->>'show_name')::boolean, true),
          coalesce((p->>'show_info')::boolean, true), left(trim(coalesce(p->>'title', '')), 80),
          left(coalesce(p->>'phone', ''), 30), norm_major(u->>'dom', p->>'major'),
          left(coalesce(p->>'role', ''), 30), left(coalesce(p->>'year', ''), 30), u->>'name', u->>'dom', p->'answers',
          left(coalesce(p->>'concern', ''), 1500), left(coalesce(p->>'letter', ''), 1500),
          array(select left(x, 20) from jsonb_array_elements_text(coalesce(p->'spread', '[]'::jsonb)) x limit 10))
  on conflict (email) do update set
    name = excluded.name, name_hidden = excluded.name_hidden, show_name = excluded.show_name, show_info = excluded.show_info, title = excluded.title, phone = excluded.phone, major = excluded.major, role = excluded.role, year = excluded.year, uni = excluded.uni,
    dom = excluded.dom, answers = excluded.answers, concern = excluded.concern, letter = excluded.letter,
    spread = excluded.spread, created_at = now(), edit_token = gen_random_uuid()
  where signups.verified_at is null
  returning edit_token, ref into t, rf;
  return u || jsonb_build_object('token', t, 'ref', rf);
end $function$;

CREATE OR REPLACE FUNCTION public.update_interest(p_token uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r signups; nm text := left(trim(coalesce(p->>'name', '')), 120);
begin
  if p ? 'answers' and (jsonb_typeof(p->'answers') <> 'object' or length((p->'answers')::text) > 2000) then
    raise exception 'bad_answers';
  end if;
  update signups set
    name_hidden = case when nm <> '' and nm <> name then not name_ok(nm) else name_hidden end,
    name      = case when nm <> '' then nm else name end,
    show_name = case when p ? 'show_name' then coalesce((p->>'show_name')::boolean, true) else show_name end,
    show_info = case when p ? 'show_info' then coalesce((p->>'show_info')::boolean, true) else show_info end,
    title     = case when p ? 'title' then left(trim(coalesce(p->>'title', '')), 80) else title end,
    major     = case when p ? 'major' then norm_major(dom, p->>'major') else major end,
    role      = case when p ? 'role' then left(coalesce(p->>'role', ''), 30) else role end,
    year      = case when p ? 'year' then left(coalesce(p->>'year', ''), 30) else year end,
    phone     = case when p ? 'phone' then left(coalesce(p->>'phone', ''), 30) else phone end,
    sms_ok    = case when p ? 'sms_ok' then coalesce((p->>'sms_ok')::boolean, false) else sms_ok end,
    answers   = case when p ? 'answers' then p->'answers' else answers end,
    concern   = case when p ? 'concern' then left(coalesce(p->>'concern', ''), 1500) else concern end,
    letter    = case when p ? 'letter' then left(coalesce(p->>'letter', ''), 1500) else letter end,
    spread    = case when p ? 'spread' then array(select left(x, 20) from jsonb_array_elements_text(p->'spread') x limit 10) else spread end
  where edit_token = p_token returning * into r;
  if not found then raise exception 'not_found'; end if;
  -- campus organizers are always listed by name
  if 'lead' = any(r.spread) and not r.show_name then
    update signups set show_name = true where edit_token = p_token returning * into r;
  end if;
  return entry_json(r);
end $function$;
