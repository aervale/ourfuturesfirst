-- A signer's number for their Instagram story ("I signed. Signer #412"): their place among confirmed sign-ups,
-- in the order they confirmed. Only the holder of the sign-up's edit token can ask, and only once confirmed.
-- (Numbers can shift down by one when someone earlier removes their sign-up.)
create function public.signer_number(p_token uuid) returns int
language sql stable security definer set search_path = public as $$
  select (select count(*) from signups o
          where o.verified_at is not null
            and (o.verified_at, o.id) <= (s.verified_at, s.id))::int
  from signups s where s.edit_token = p_token and s.verified_at is not null;
$$;
revoke execute on function public.signer_number(uuid) from public;
grant execute on function public.signer_number(uuid) to anon, authenticated;
