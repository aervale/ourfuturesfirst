-- One university, one entry: about 120 universities are listed under more than one email domain
-- (northeastern.edu and neu.edu, uw.edu and washington.edu, a college's old and new domains, student subdomains).
-- Each extra domain now points at a main one, so its sign-ups count toward the same university and the same star.
-- Different schools that share a name (the Bethel Universities, the Lincoln Universities) are left apart:
-- a domain is only folded in when its map position matches the main one's, or when it has no position and
-- every placed domain with that name is in one spot.

alter table public.uni_domains add column if not exists alias_of text references public.uni_domains(domain);

with n as (select name from public.uni_domains group by name having count(*) > 1),
m as (select d.domain, d.name, d.mx, d.my,
        (select x.domain from public.uni_domains x where x.name = d.name and x.mx is not null
          order by (x.domain like '%.%.%'), length(x.domain), x.domain limit 1) main
      from public.uni_domains d join n using (name)),
pick as (
  select m.domain, m.main from m join public.uni_domains k on k.domain = m.main
  where m.domain <> m.main and (
    (m.mx is not null and abs(m.mx - k.mx) <= 6 and abs(m.my - k.my) <= 6)
    or (m.mx is null and not exists (select 1 from public.uni_domains z where z.name = m.name and z.mx is not null
                                     and (abs(z.mx - k.mx) > 6 or abs(z.my - k.my) > 6)))))
update public.uni_domains u set alias_of = pick.main from pick where u.domain = pick.domain;

-- the same university under a different name, set by hand
update public.uni_domains u set alias_of = v.main from (values
  ('neu.edu', 'northeastern.edu'),
  ('jh.edu', 'jhu.edu'),
  ('johnshopkins.edu', 'jhu.edu'),
  ('washington.edu', 'uw.edu'),
  ('lhup.edu', 'lockhaven.edu')
) v(domain, main) where u.domain = v.domain;

-- a wrong name in the source list
update public.uni_domains set name = 'West Liberty University' where domain = 'westliberty.edu';

-- an email at an extra domain is recorded under the main one
create or replace function public.lookup_uni(p_email text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d text; l text[]; n int; s text; nm text; al text;
begin
  d := lower(split_part(trim(p_email), '@', 2));
  if d !~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' then return null; end if;
  l := string_to_array(d, '.'); n := array_length(l, 1);
  for i in 1..n-1 loop
    s := array_to_string(l[i:n], '.');
    select name, alias_of into nm, al from uni_domains where domain = s;
    if found then
      if al is not null then select domain, name into s, nm from uni_domains where domain = al; end if;
      return jsonb_build_object('dom', s, 'name', nm);
    end if;
  end loop;
  if l[n] <> 'edu' then return null; end if;
  s := array_to_string(l[n-1:n], '.');
  return jsonb_build_object('dom', s, 'name', s);
end $$;

-- move any existing sign-ups at an extra domain over to the main one
update public.signups s set dom = u.alias_of, uni = k.name
  from public.uni_domains u join public.uni_domains k on k.domain = u.alias_of
  where s.dom = u.domain and u.alias_of is not null;
update public.signups_unconfirmed s set dom = u.alias_of, uni = k.name
  from public.uni_domains u join public.uni_domains k on k.domain = u.alias_of
  where s.dom = u.domain and u.alias_of is not null;
