-- A university can be closed to new campus organizers by hand, whatever its limit says, and opened again.
-- Closing never removes the organizers it already has.
create table public.organizer_closed (
  dom        text primary key,
  changed_at timestamptz not null default now(),
  changed_by text not null default ''
);
alter table public.organizer_closed enable row level security;
revoke all on table public.organizer_closed from anon, authenticated;

create or replace function public.signups_organizer_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare already boolean;
begin
  if not ('lead' = any(new.spread)) then return new; end if;
  if tg_op = 'UPDATE' then already := 'lead' = any(old.spread);
  else already := exists (select 1 from signups where email = new.email and 'lead' = any(spread)); end if;
  if already then return new; end if;
  if exists (select 1 from organizer_closed where dom = new.dom)
     or (select count(*) from signups where dom = new.dom and 'lead' = any(spread) and email <> new.email) >= organizer_cap(new.dom) then
    new.spread := array_remove(new.spread, 'lead');
  end if;
  return new;
end $$;

create or replace function public.organizer_room(p_dom text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('cap', organizer_cap(p_dom),
    'count', (select count(*) from signups where dom = p_dom and 'lead' = any(spread)),
    'closed', exists (select 1 from organizer_closed where dom = p_dom));
$$;

-- Admins: the list of closed universities, and opening or closing one.
create function public.admin_closed() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return (select coalesce(jsonb_agg(dom), '[]'::jsonb) from organizer_closed);
end $$;

create function public.admin_set_accepting(p_dom text, p_accepting boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  if p_accepting then delete from organizer_closed where dom = p_dom;
  else insert into organizer_closed (dom, changed_by) values (p_dom, coalesce(auth.jwt() ->> 'email', '')) on conflict (dom) do nothing; end if;
  return (select coalesce(jsonb_agg(dom), '[]'::jsonb) from organizer_closed);
end $$;

revoke execute on function public.admin_closed(), public.admin_set_accepting(text, boolean) from public, anon;
grant execute on function public.admin_closed(), public.admin_set_accepting(text, boolean) to authenticated;
