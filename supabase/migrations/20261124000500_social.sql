-- Optional social media handle left on the interest form. Never shown publicly;
-- admins see it through admin_rows(). Kept as its own small function so the
-- sign-up functions in 20261124000000_interest.sql stay untouched.
alter table public.signups add column social text not null default '';

create function public.set_social(p_token uuid, p_social text) returns void
language sql security definer set search_path = public as $$
  update signups set social = left(trim(coalesce(p_social, '')), 120) where edit_token = p_token;
$$;
revoke all on function public.set_social(uuid, text) from public;
grant execute on function public.set_social(uuid, text) to anon, authenticated;
