-- Admin sign-ins last 30 days instead of 12 hours: an emailed link used within the last 30 days still counts.
-- Everything else in is_admin() is unchanged (confirmed email, the token's email, never a password sign-in).
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u join admins a on a.email = u.email::citext
    where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and u.email::citext = (auth.jwt() ->> 'email')::citext
      and not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) m where m ->> 'method' = 'password')
      and exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) m
                  where m ->> 'method' in ('otp', 'magiclink') and (m ->> 'timestamp')::bigint > extract(epoch from now()) - 30 * 86400));
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
