-- Named links: links the core team makes on the admin page and hands out (a club's mailing list, a newsletter,
-- a flyer, an Instagram post), each tracked on its own. They look like ourfuturesfirst.org/?l=mit-tech-newsletter.
-- Opening one is counted; a sign-up made after opening one is credited to it (the first such link only).
-- As with personal links, nothing about the visitor is kept beyond the time of the open.

create table public.links (
  slug       text primary key check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  label      text not null check (char_length(label) between 1 and 120),  -- what it is for, e.g. "The Tech newsletter"
  dom        text,                                                          -- the university it is for, if any
  uni        text not null default '',
  made_by    text not null default '',                                      -- admin email that made it
  created_at timestamptz not null default now()
);
alter table public.links enable row level security;

create table public.link_opens (
  slug text not null references public.links(slug) on delete cascade,
  at   timestamptz not null default now()
);
create index link_opens_slug on public.link_opens (slug);
alter table public.link_opens enable row level security;

create table public.link_signups (
  signup_id uuid primary key references public.signups(id) on delete cascade,
  slug      text not null references public.links(slug) on delete cascade,
  at        timestamptz not null default now()
);
alter table public.link_signups enable row level security;

revoke all on table public.links, public.link_opens, public.link_signups from anon, authenticated;

-- Called by the page when someone arrives on ?l=. Unknown links are dropped quietly.
create function public.open_link(p_slug text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_slug is null or not exists (select 1 from links where slug = p_slug) then return; end if;
  perform throttle_check('event', 300, 50000);
  insert into link_opens (slug) values (p_slug);
end $$;

-- Called by the page right after a sign-up, with that sign-up's edit token: credits it to the link it came from.
create function public.claim_link(p_token uuid, p_slug text) returns void
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  select id into sid from signups where edit_token = p_token;
  if sid is null or not exists (select 1 from links where slug = p_slug) then return; end if;
  insert into link_signups (signup_id, slug) values (sid, p_slug) on conflict (signup_id) do nothing;
end $$;

revoke execute on function public.open_link(text), public.claim_link(uuid, text) from public;
grant execute on function public.open_link(text), public.claim_link(uuid, text) to anon, authenticated;

-- Admin page: every link with its counts.
create function public.links_json() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', l.slug, 'label', l.label, 'dom', l.dom, 'uni', l.uni, 'made_by', l.made_by, 'made', l.created_at,
           'opens', (select count(*) from link_opens o where o.slug = l.slug),
           'opens7', (select count(*) from link_opens o where o.slug = l.slug and o.at > now() - interval '7 days'),
           'signups', (select count(*) from link_signups x where x.slug = l.slug),
           'confirmed', (select count(*) from link_signups x join signups s on s.id = x.signup_id where x.slug = l.slug and s.verified_at is not null))
         order by l.created_at desc), '[]'::jsonb)
  from links l;
$$;
revoke execute on function public.links_json() from public, anon, authenticated;

create function public.admin_links() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return links_json();
end $$;

-- Make a link. Returns the updated list, or {error}: taken, bad_slug, bad_label.
create function public.admin_make_link(p_slug text, p_label text, p_dom text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s text := lower(trim(coalesce(p_slug, ''))); l text := trim(coalesce(p_label, '')); u text := '';
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  if s !~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' then return jsonb_build_object('error', 'bad_slug'); end if;
  if l = '' or char_length(l) > 120 then return jsonb_build_object('error', 'bad_label'); end if;
  if exists (select 1 from links where slug = s) then return jsonb_build_object('error', 'taken'); end if;
  if coalesce(p_dom, '') <> '' then select coalesce(min(uni), (select name from uni_domains where domain = p_dom limit 1), p_dom) into u from signups where dom = p_dom; end if;
  insert into links (slug, label, dom, uni, made_by) values (s, l, nullif(p_dom, ''), coalesce(u, ''), coalesce(auth.jwt() ->> 'email', ''));
  return jsonb_build_object('links', links_json());
end $$;

-- Remove a link and its counts. The sign-ups it brought in stay.
create function public.admin_remove_link(p_slug text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  delete from links where slug = p_slug;
  return jsonb_build_object('links', links_json());
end $$;

revoke execute on function public.admin_links(), public.admin_make_link(text, text, text), public.admin_remove_link(text) from public, anon, authenticated;
grant execute on function public.admin_links(), public.admin_make_link(text, text, text), public.admin_remove_link(text) to authenticated;
