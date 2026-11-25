-- Addresses a signer lists under "I'll share it with fellow students". Never shown
-- publicly; admins see them through admin_rows(). Its own small function, like set_social().
alter table public.signups add column invites text not null default '';

create function public.set_invites(p_token uuid, p_list text) returns void
language sql security definer set search_path = public as $$
  update signups set invites = left(trim(coalesce(p_list, '')), 2000) where edit_token = p_token;
$$;
revoke all on function public.set_invites(uuid, text) from public;
grant execute on function public.set_invites(uuid, text) to anon, authenticated;
