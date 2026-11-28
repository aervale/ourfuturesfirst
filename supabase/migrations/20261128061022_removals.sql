-- Count people who remove their own sign-up ("Remove me"), so the admin page can show how many leave.
-- Nothing that identifies the person is kept: only when, which university, whether they had confirmed,
-- and how long after signing up they left. (Sign-ups never confirmed and swept after 7 days are not counted.)
create table public.removals (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  dom text,
  uni text,
  confirmed boolean not null,
  hours_signed numeric
);
alter table public.removals enable row level security;
revoke all on public.removals from public, anon, authenticated;

-- Remove me: deletes the sign-up and the sign-in record for its address, and counts the removal.
create or replace function public.delete_interest(p_token uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e text; d text; u text; v timestamptz; c timestamptz;
begin
  delete from signups where edit_token = p_token returning email, dom, uni, verified_at, created_at into e, d, u, v, c;
  if e is null then raise exception 'not_found'; end if;
  insert into removals (dom, uni, confirmed, hours_signed)
    values (d, u, v is not null, round((extract(epoch from now() - c) / 3600)::numeric, 1));
  delete from auth.users where email = e;
end $$;

-- What the admin page shows:
--   total, week, confirmed  removals ever, in the past 7 days, and how many of all of them had confirmed
--   median_hours            typical time between signing up and removing
--   unis                    per university: removed, of them confirmed, sign-ups it has now, last removal
create function public.removal_report() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'total', (select count(*) from removals),
    'week', (select count(*) from removals where at > now() - interval '7 days'),
    'confirmed', (select count(*) from removals where confirmed),
    'median_hours', (select percentile_cont(0.5) within group (order by hours_signed) from removals),
    'unis', coalesce((
      select jsonb_agg(x order by x.removed desc, x.uni) from (
        select r.dom, max(r.uni) uni, count(*) removed, count(*) filter (where r.confirmed) confirmed,
          (select count(*) from signups s where s.dom = r.dom and s.verified_at is not null) now_confirmed,
          max(r.at) last_at
        from removals r group by r.dom) x), '[]'::jsonb));
$$;

create function public.admin_removal_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return removal_report();
end $$;

revoke execute on function public.removal_report(), public.admin_removal_report() from public, anon, authenticated;
grant execute on function public.admin_removal_report() to authenticated;
