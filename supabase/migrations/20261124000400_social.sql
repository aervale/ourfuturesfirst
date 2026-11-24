-- Optional social media handle on a sign-up. Private: used to contact the person, never shown.
alter table public.signups add column if not exists social text not null default '';

create or replace function public.entry_json(s public.signups) returns jsonb language sql stable as $$
  select jsonb_build_object('email', s.email, 'uni', s.uni, 'dom', s.dom, 'verified', s.verified_at is not null,
    'token', s.edit_token, 'name', s.name, 'show_name', s.show_name, 'major', s.major, 'role', s.role, 'year', s.year, 'phone', s.phone, 'sms_ok', s.sms_ok,
    'social', s.social, 'answers', s.answers, 'concern', s.concern, 'letter', s.letter, 'spread', to_jsonb(s.spread));
$$;

create or replace function public.submit_interest(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(coalesce(p->>'email', ''))); u jsonb; t uuid;
begin
  if e !~ '^[^\s@]+@[^\s@]+$' or length(e) > 160 then raise exception 'bad_email'; end if;
  u := lookup_uni(e);
  if u is null then raise exception 'not_university'; end if;
  if trim(coalesce(p->>'name', '')) = '' then raise exception 'no_name'; end if;
  if jsonb_typeof(p->'answers') is distinct from 'object' or length((p->'answers')::text) > 2000 then
    raise exception 'bad_answers';
  end if;
  insert into signups (email, name, show_name, phone, social, major, role, year, uni, dom, answers, concern, letter, spread)
  values (e, left(coalesce(p->>'name', ''), 120), coalesce((p->>'show_name')::boolean, true),
          left(coalesce(p->>'phone', ''), 30), left(coalesce(p->>'social', ''), 120), left(coalesce(p->>'major', ''), 80),
          left(coalesce(p->>'role', ''), 30), left(coalesce(p->>'year', ''), 30), u->>'name', u->>'dom', p->'answers',
          left(coalesce(p->>'concern', ''), 1500), left(coalesce(p->>'letter', ''), 1500),
          array(select left(x, 20) from jsonb_array_elements_text(coalesce(p->'spread', '[]'::jsonb)) x limit 10))
  on conflict (email) do update set
    name = excluded.name, show_name = excluded.show_name, phone = excluded.phone, social = excluded.social, major = excluded.major,
    role = excluded.role, year = excluded.year, uni = excluded.uni,
    dom = excluded.dom, answers = excluded.answers, concern = excluded.concern, letter = excluded.letter,
    spread = excluded.spread, created_at = now(), edit_token = gen_random_uuid()
  where signups.verified_at is null
  returning edit_token into t;
  return u || jsonb_build_object('token', t);
end $$;

create or replace function public.update_interest(p_token uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r signups;
begin
  if p ? 'answers' and (jsonb_typeof(p->'answers') <> 'object' or length((p->'answers')::text) > 2000) then
    raise exception 'bad_answers';
  end if;
  update signups set
    name      = case when p ? 'name' and trim(coalesce(p->>'name', '')) <> '' then left(p->>'name', 120) else name end,
    show_name = case when p ? 'show_name' then coalesce((p->>'show_name')::boolean, true) else show_name end,
    major     = case when p ? 'major' then left(coalesce(p->>'major', ''), 80) else major end,
    role      = case when p ? 'role' then left(coalesce(p->>'role', ''), 30) else role end,
    year      = case when p ? 'year' then left(coalesce(p->>'year', ''), 30) else year end,
    phone     = case when p ? 'phone' then left(coalesce(p->>'phone', ''), 30) else phone end,
    social    = case when p ? 'social' then left(coalesce(p->>'social', ''), 120) else social end,
    sms_ok    = case when p ? 'sms_ok' then coalesce((p->>'sms_ok')::boolean, false) else sms_ok end,
    answers   = case when p ? 'answers' then p->'answers' else answers end,
    concern   = case when p ? 'concern' then left(coalesce(p->>'concern', ''), 1500) else concern end,
    letter    = case when p ? 'letter' then left(coalesce(p->>'letter', ''), 1500) else letter end,
    spread    = case when p ? 'spread' then array(select left(x, 20) from jsonb_array_elements_text(p->'spread') x limit 10) else spread end
  where edit_token = p_token returning * into r;
  if not found then raise exception 'not_found'; end if;
  return entry_json(r);
end $$;
