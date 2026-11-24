-- Initial interest stage: sign-ups, university lookup, public board.
-- Tables are private (RLS on, no policies). The page talks to the functions below only.

create extension if not exists citext;

create table public.uni_domains (
  domain text primary key,
  name   text not null
);
alter table public.uni_domains enable row level security;

create table public.signups (
  id          uuid primary key default gen_random_uuid(),
  email       citext not null unique,
  name        text not null default '',
  show_name   boolean not null default true,
  phone       text not null default '',
  sms_ok      boolean not null default false,
  major       text not null default '',
  role        text not null default '',
  year        text not null default '',
  uni         text not null,
  dom         text not null,
  answers     jsonb not null default '{}',
  concern     text not null default '',
  letter      text not null default '',
  spread      text[] not null default '{}',
  verified_at timestamptz,
  edit_token  uuid not null default gen_random_uuid(),
  created_at  timestamptz not null default now()
);
alter table public.signups enable row level security;

-- U.S. universities only. University for an email address: longest matching listed domain,
-- else any other .edu domain. Null when it is not a U.S. university address.
create function public.lookup_uni(p_email text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d text; l text[]; n int; s text; nm text;
begin
  d := lower(split_part(trim(p_email), '@', 2));
  if d !~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' then return null; end if;
  l := string_to_array(d, '.'); n := array_length(l, 1);
  for i in 1..n-1 loop
    s := array_to_string(l[i:n], '.');
    select name into nm from uni_domains where domain = s;
    if found then return jsonb_build_object('dom', s, 'name', nm); end if;
  end loop;
  if l[n] <> 'edu' then return null; end if;
  s := array_to_string(l[n-1:n], '.');
  return jsonb_build_object('dom', s, 'name', s);
end $$;

-- A person's own entry, as the page sees it. Internal helper.
create function public.entry_json(s public.signups) returns jsonb language sql stable as $$
  select jsonb_build_object('email', s.email, 'uni', s.uni, 'dom', s.dom, 'verified', s.verified_at is not null,
    'token', s.edit_token, 'name', s.name, 'show_name', s.show_name, 'major', s.major, 'role', s.role, 'year', s.year, 'phone', s.phone, 'sms_ok', s.sms_ok,
    'answers', s.answers, 'concern', s.concern, 'letter', s.letter, 'spread', to_jsonb(s.spread));
$$;

-- Store a submission as unverified. Resubmitting before verifying replaces it and restarts the 48 hours.
-- A verified entry is never overwritten here. Returns the university and an edit token: whoever holds
-- the token can read and change the entry later (get_interest / update_interest).
create function public.submit_interest(p jsonb) returns jsonb
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
  insert into signups (email, name, show_name, phone, major, role, year, uni, dom, answers, concern, letter, spread)
  values (e, left(coalesce(p->>'name', ''), 120), coalesce((p->>'show_name')::boolean, true),
          left(coalesce(p->>'phone', ''), 30), left(coalesce(p->>'major', ''), 80),
          left(coalesce(p->>'role', ''), 30), left(coalesce(p->>'year', ''), 30), u->>'name', u->>'dom', p->'answers',
          left(coalesce(p->>'concern', ''), 1500), left(coalesce(p->>'letter', ''), 1500),
          array(select left(x, 20) from jsonb_array_elements_text(coalesce(p->'spread', '[]'::jsonb)) x limit 10))
  on conflict (email) do update set
    name = excluded.name, show_name = excluded.show_name, phone = excluded.phone, major = excluded.major, role = excluded.role, year = excluded.year, uni = excluded.uni,
    dom = excluded.dom, answers = excluded.answers, concern = excluded.concern, letter = excluded.letter,
    spread = excluded.spread, created_at = now(), edit_token = gen_random_uuid()
  where signups.verified_at is null
  returning edit_token into t;
  return u || jsonb_build_object('token', t);
end $$;

-- Everything the public page shows. Verified sign-ups only; answers only as totals.
create function public.board() returns jsonb
language sql stable security definer set search_path = public as $$
  with v as (select * from signups where verified_at is not null)
  select jsonb_build_object(
    'total', (select count(*) from v),
    'named', (select count(*) from v where show_name and name <> ''),
    'unis', coalesce((select jsonb_agg(jsonb_build_object('key', dom, 'name', uni, 'n', n, 'named', named) order by n desc, uni)
                      from (select dom, min(uni) uni, count(*) n, count(*) filter (where show_name and name <> '') named
                            from v group by dom) t), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'uni', uni, 'lead', lead) order by verified_at desc)
                        from (select name, uni, verified_at, 'lead' = any(spread) lead from v where show_name and name <> ''
                              order by verified_at desc limit 500) t), '[]'::jsonb),
    'answers', coalesce((select jsonb_object_agg(q, o)
                         from (select q, jsonb_object_agg(a, n) o
                               from (select e.key q, e.value a, count(*) n from v, jsonb_each_text(v.answers) e group by 1, 2) x
                               group by q) y), '{}'::jsonb));
$$;

-- Read or change an entry with its edit token. Email and university cannot be changed.
create function public.get_interest(p_token uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select entry_json(s) from signups s where edit_token = p_token;
$$;

create function public.update_interest(p_token uuid, p jsonb) returns jsonb
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
    sms_ok    = case when p ? 'sms_ok' then coalesce((p->>'sms_ok')::boolean, false) else sms_ok end,
    answers   = case when p ? 'answers' then p->'answers' else answers end,
    concern   = case when p ? 'concern' then left(coalesce(p->>'concern', ''), 1500) else concern end,
    letter    = case when p ? 'letter' then left(coalesce(p->>'letter', ''), 1500) else letter end,
    spread    = case when p ? 'spread' then array(select left(x, 20) from jsonb_array_elements_text(p->'spread') x limit 10) else spread end
  where edit_token = p_token returning * into r;
  if not found then raise exception 'not_found'; end if;
  return entry_json(r);
end $$;

-- Called by the page when a visitor arrives signed in from the emailed link. Only that link gives a
-- session for the address, so this is the proof of ownership: it verifies their sign-up if it is under
-- 48 hours old, and returns their entry (with its edit token).
create function public.confirm_signup() returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text := auth.jwt() ->> 'email'; r jsonb;
begin
  update signups set verified_at = now()
  where email = e and verified_at is null and created_at > now() - interval '48 hours';
  select entry_json(s) into r from signups s where email = e;
  return r;
end $$;

revoke execute on function public.lookup_uni(text), public.submit_interest(jsonb), public.board(),
  public.confirm_signup(), public.get_interest(uuid), public.update_interest(uuid, jsonb),
  public.entry_json(public.signups) from public, anon, authenticated;
grant execute on function public.lookup_uni(text), public.submit_interest(jsonb), public.board(),
  public.get_interest(uuid), public.update_interest(uuid, jsonb) to anon, authenticated;
grant execute on function public.confirm_signup() to authenticated;
