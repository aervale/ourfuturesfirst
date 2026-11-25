-- Initial interest stage: sign-ups, university lookup, public board.
-- Tables are private (RLS on, no policies). The page talks to the functions below only.

create extension if not exists citext;

create table public.uni_domains (
  domain text primary key,
  name   text not null,
  mx     smallint,  -- position on the page's U.S. map, filled in by a later migration
  my     smallint
);
alter table public.uni_domains enable row level security;

create table public.signups (
  id          uuid primary key default gen_random_uuid(),
  email       citext not null unique,
  name        text not null default '',
  show_name   boolean not null default true,
  name_hidden boolean not null default false,  -- set by name screening or an admin; keeps the name off the public list
  phone       text not null default '',
  sms_ok      boolean not null default false,
  major       text not null default '',
  social      text not null default '',           -- optional social media handle; never shown publicly
  role        text not null default '',
  year        text not null default '',
  title       text not null default '',           -- faculty and staff
  show_info   boolean not null default true,      -- list year or title, and major, beside a public name
  uni         text not null,
  dom         text not null,
  answers     jsonb not null default '{}',
  concern     text not null default '',
  letter      text not null default '',
  spread      text[] not null default '{}',
  verified_at timestamptz,
  edit_token  uuid not null default gen_random_uuid(),
  ref         text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),  -- code in this person's share link
  ref_by      text not null default '',           -- share-link code they arrived with
  created_at  timestamptz not null default now()
);
alter table public.signups enable row level security;

-- Sign-ups that were never confirmed are moved here after 7 days, out of the main table.
create table public.signups_unconfirmed (like public.signups, moved_at timestamptz not null default now());
alter table public.signups_unconfirmed enable row level security;

create function public.sweep_unconfirmed() returns void
language sql security definer set search_path = public as $$
  with d as (delete from signups where verified_at is null and created_at < now() - interval '7 days' returning *)
  insert into signups_unconfirmed select d.*, now() from d;
$$;

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

-- Quick screen for names that should not go straight onto the public list: profanity and slurs as whole
-- words, links, or nothing that looks like a name. A name that fails is hidden until an admin reviews it.
create function public.name_ok(p text) returns boolean language sql immutable as $$
  select p ~* '[[:alpha:]]{2}'
     and p !~* '(https?:|www\.|@|\.(com|net|org|edu)\M|[0-9]{3})'
     and p !~* '\m(fuck\w*|motherfuck\w*|shit\w*|bullshit|bitch\w*|cunt\w*|ass(hole|hat|wipe)s?|bastard|whore|slut|pussy|penis|vagina|dildo|cock(s|sucker\w*)?|porn\w*|rape[sd]?|rapist|nazi\w*|hitler|nigg(er|a)\w*|fag(got)?s?|retard\w*|kike|spic|chink|tranny|pedo\w*)\M';
$$;

-- A person's own entry, as the page sees it. Internal helper.
create function public.entry_json(s public.signups) returns jsonb language sql stable as $$
  select jsonb_build_object('email', s.email, 'uni', s.uni, 'dom', s.dom, 'verified', s.verified_at is not null,
    'token', s.edit_token, 'name', s.name, 'show_name', s.show_name, 'major', s.major, 'social', s.social, 'role', s.role, 'year', s.year, 'title', s.title, 'show_info', s.show_info, 'phone', s.phone, 'sms_ok', s.sms_ok,
    'answers', s.answers, 'concern', s.concern, 'letter', s.letter, 'spread', to_jsonb(s.spread), 'ref', s.ref,
    -- confirmed people who joined straight from this person's share link, and everyone further down the chain
    'invited', (select count(*) from signups x where x.ref_by = s.ref and x.verified_at is not null),
    'downstream', (with recursive d as (select x.ref, x.verified_at from signups x where x.ref_by = s.ref
                     union select x.ref, x.verified_at from signups x join d on x.ref_by = d.ref)
                   select count(*) from d where verified_at is not null));
$$;

-- Store a submission as unverified. Resubmitting before verifying replaces it and restarts the 48 hours.
-- A verified entry is never overwritten here. Returns the university and an edit token: whoever holds
-- the token can read and change the entry later (get_interest / update_interest).
create function public.submit_interest(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  insert into signups (social, ref_by, email, name, name_hidden, show_name, show_info, title, phone, major, role, year, uni, dom, answers, concern, letter, spread)
  values (left(trim(coalesce(p->>'social', '')), 120), coalesce((select ref from signups where ref = p->>'ref_by' and email <> e), ''), e, left(coalesce(p->>'name', ''), 120), not name_ok(left(coalesce(p->>'name', ''), 120)), coalesce((p->>'show_name')::boolean, true),
          coalesce((p->>'show_info')::boolean, true), left(trim(coalesce(p->>'title', '')), 80),
          left(coalesce(p->>'phone', ''), 30), norm_major(u->>'dom', p->>'major'),
          left(coalesce(p->>'role', ''), 30), left(coalesce(p->>'year', ''), 30), u->>'name', u->>'dom', p->'answers',
          left(coalesce(p->>'concern', ''), 1500), left(coalesce(p->>'letter', ''), 1500),
          array(select left(x, 20) from jsonb_array_elements_text(coalesce(p->'spread', '[]'::jsonb)) x
                where x <> 'lead' or trim(coalesce(p->>'phone', '')) <> '' limit 10))
  on conflict (email) do update set
    social = excluded.social, name = excluded.name, name_hidden = excluded.name_hidden, show_name = excluded.show_name, show_info = excluded.show_info, title = excluded.title, phone = excluded.phone, major = excluded.major, role = excluded.role, year = excluded.year, uni = excluded.uni,
    dom = excluded.dom, answers = excluded.answers, concern = excluded.concern, letter = excluded.letter,
    spread = excluded.spread, created_at = now(), edit_token = gen_random_uuid()
  where signups.verified_at is null
  returning edit_token, ref into t, rf;
  return u || jsonb_build_object('token', t, 'ref', rf);
end $$;

-- Read or change an entry with its edit token. Email and university cannot be changed.
create function public.get_interest(p_token uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select entry_json(s) from signups s where edit_token = p_token;
$$;

create function public.update_interest(p_token uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
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
    social    = case when p ? 'social' then left(trim(coalesce(p->>'social', '')), 120) else social end,
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
  -- nobody is a campus organizer without a phone number
  if 'lead' = any(r.spread) and trim(r.phone) = '' then
    update signups set spread = array_remove(spread, 'lead') where edit_token = p_token returning * into r;
  end if;
  -- campus organizers are always listed by name
  if 'lead' = any(r.spread) and not r.show_name then
    update signups set show_name = true where edit_token = p_token returning * into r;
  end if;
  return entry_json(r);
end $$;

-- Remove me: deletes the sign-up and the sign-in record for its address.
create function public.delete_interest(p_token uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e text;
begin
  delete from signups where edit_token = p_token returning email into e;
  if e is null then raise exception 'not_found'; end if;
  delete from auth.users where email = e;
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

-- Admins: people listed here who sign in by emailed link can read every sign-up on admin.html.
create table public.admins (email citext primary key);
alter table public.admins enable row level security;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where email = auth.jwt() ->> 'email');
$$;

create function public.admin_rows() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return coalesce((select jsonb_agg(to_jsonb(s) - 'edit_token' order by s.created_at desc) from signups s), '[]'::jsonb);
end $$;

create function public.admin_set_hidden(p_id uuid, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  update signups set name_hidden = p_hidden where id = p_id;
end $$;

revoke execute on function public.lookup_uni(text), public.submit_interest(jsonb),
  public.confirm_signup(), public.get_interest(uuid), public.update_interest(uuid, jsonb),
  public.entry_json(public.signups), public.name_ok(text), public.sweep_unconfirmed(), public.delete_interest(uuid), public.is_admin(), public.admin_rows(),
  public.admin_set_hidden(uuid, boolean) from public, anon, authenticated;
grant execute on function public.lookup_uni(text), public.submit_interest(jsonb),
  public.get_interest(uuid), public.update_interest(uuid, jsonb), public.delete_interest(uuid) to anon, authenticated;
grant execute on function public.confirm_signup(), public.is_admin(), public.admin_rows(),
  public.admin_set_hidden(uuid, boolean) to authenticated;
