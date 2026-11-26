-- Three parts of the public page that an admin switches on from the admin page. All start off:
--   ticker  the scrolling list of universities under the banner
--   results the poll results ("Results so far"), and the percentages shown on the answers in the form
--   who     the "Who has signed up" rings (role, year, majors)
create table public.page_switches (
  name       text primary key check (name in ('ticker', 'results', 'who')),
  shown      boolean not null default false,
  changed_at timestamptz not null default now(),
  changed_by text not null default ''
);
insert into public.page_switches (name) values ('ticker'), ('results'), ('who');
alter table public.page_switches enable row level security;
revoke all on table public.page_switches from anon, authenticated;

-- Read by the public page: {"ticker": false, "results": false, "who": false}
create function public.page_switches() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(name, shown), '{}'::jsonb) from page_switches;
$$;
revoke execute on function public.page_switches() from public;
grant execute on function public.page_switches() to anon, authenticated;

-- Admins only. Records who changed it and when.
create function public.admin_set_switch(p_name text, p_shown boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  update page_switches set shown = p_shown, changed_at = now(), changed_by = coalesce(auth.jwt() ->> 'email', '') where name = p_name;
  if not found then raise exception 'unknown_switch'; end if;
  return page_switches();
end $$;
revoke execute on function public.admin_set_switch(text, boolean) from public, anon;
grant execute on function public.admin_set_switch(text, boolean) to authenticated;
