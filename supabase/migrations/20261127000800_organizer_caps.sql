-- A limit on campus organizers per university: 5 unless an admin sets another number, overall or for one campus.
-- Once a university is at its limit, nobody new there can become an organizer; the people who already are stay.
create table public.organizer_caps (
  dom        text primary key,                 -- a university's domain, or '*' for the overall number
  cap        int not null check (cap between 0 and 1000),
  changed_at timestamptz not null default now(),
  changed_by text not null default ''
);
insert into public.organizer_caps (dom, cap) values ('*', 5);
alter table public.organizer_caps enable row level security;
revoke all on table public.organizer_caps from anon, authenticated;

create function public.organizer_cap(p_dom text) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select cap from organizer_caps where dom = p_dom), (select cap from organizer_caps where dom = '*'), 5);
$$;

-- Enforced where the row is written, so every path that saves a sign-up is covered. A person who is already an
-- organizer keeps it; someone newly asking is quietly left off when their university is full.
create function public.signups_organizer_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare already boolean;
begin
  if not ('lead' = any(new.spread)) then return new; end if;
  if tg_op = 'UPDATE' then already := 'lead' = any(old.spread);
  else already := exists (select 1 from signups where email = new.email and 'lead' = any(spread)); end if;
  if already then return new; end if;
  if (select count(*) from signups where dom = new.dom and 'lead' = any(spread) and email <> new.email) >= organizer_cap(new.dom) then
    new.spread := array_remove(new.spread, 'lead');
  end if;
  return new;
end $$;
create trigger signups_organizer_cap before insert or update of spread on public.signups
  for each row execute function public.signups_organizer_cap();

-- Read by the page to know whether to offer organizing at a university.
create function public.organizer_room(p_dom text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('cap', organizer_cap(p_dom),
    'count', (select count(*) from signups where dom = p_dom and 'lead' = any(spread)));
$$;

-- Admins: take organizer status away from one person, and read and set the limits.
create function public.admin_remove_organizer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  update signups set spread = array_remove(spread, 'lead') where id = p_id;
end $$;

create function public.admin_caps() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return (select coalesce(jsonb_object_agg(dom, cap), '{}'::jsonb) from organizer_caps);
end $$;

-- p_dom '*' sets the overall number. A null p_cap removes a campus's own number so it follows the overall one.
create function public.admin_set_cap(p_dom text, p_cap int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  if p_cap is null then
    if p_dom = '*' then raise exception 'overall_needs_a_number'; end if;
    delete from organizer_caps where dom = p_dom;
  else
    insert into organizer_caps (dom, cap, changed_by) values (p_dom, p_cap, coalesce(auth.jwt() ->> 'email', ''))
    on conflict (dom) do update set cap = excluded.cap, changed_at = now(), changed_by = excluded.changed_by;
  end if;
  return (select coalesce(jsonb_object_agg(dom, cap), '{}'::jsonb) from organizer_caps);
end $$;

revoke execute on function public.organizer_cap(text), public.signups_organizer_cap(), public.organizer_room(text),
  public.admin_remove_organizer(uuid), public.admin_caps(), public.admin_set_cap(text, int) from public, anon, authenticated;
grant execute on function public.organizer_room(text) to anon, authenticated;
grant execute on function public.admin_remove_organizer(uuid), public.admin_caps(), public.admin_set_cap(text, int) to authenticated;
