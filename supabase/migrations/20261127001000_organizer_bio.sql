-- A short description campus organizers write about themselves (around 100 words). Kept in its own table, tied to the
-- sign-up and removed with it. Only the person and the admins can read it; it is not shown publicly.
create table public.organizer_bios (
  signup_id  uuid primary key references public.signups(id) on delete cascade,
  bio        text not null check (char_length(bio) between 1 and 1200),
  updated_at timestamptz not null default now()
);
alter table public.organizer_bios enable row level security;
revoke all on table public.organizer_bios from anon, authenticated;

-- The person's own, by the token that already lets them edit their entry. An empty text clears it.
create function public.set_organizer_bio(p_token uuid, p_bio text) returns void
language plpgsql security definer set search_path = public as $$
declare sid uuid; b text := left(trim(coalesce(p_bio, '')), 1200);
begin
  select id into sid from signups where edit_token = p_token;
  if sid is null then raise exception 'not_found'; end if;
  if b = '' then delete from organizer_bios where signup_id = sid;
  else insert into organizer_bios (signup_id, bio) values (sid, b)
       on conflict (signup_id) do update set bio = excluded.bio, updated_at = now(); end if;
end $$;

create function public.get_organizer_bio(p_token uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select b.bio from organizer_bios b join signups s on s.id = b.signup_id where s.edit_token = p_token), '');
$$;

-- Admins: every bio, by sign-up.
create function public.admin_bios() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return (select coalesce(jsonb_object_agg(signup_id, bio), '{}'::jsonb) from organizer_bios);
end $$;

revoke execute on function public.set_organizer_bio(uuid, text), public.get_organizer_bio(uuid), public.admin_bios() from public, anon, authenticated;
grant execute on function public.set_organizer_bio(uuid, text), public.get_organizer_bio(uuid) to anon, authenticated;
grant execute on function public.admin_bios() to authenticated;
