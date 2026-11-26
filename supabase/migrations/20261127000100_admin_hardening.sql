-- Stricter test for who counts as an admin. Every admin function calls this, so the rules live in one place.
-- Before, it only compared the email in the sign-in token with the admins list. Now all of these must hold:
--   * the account's email is confirmed, and is the one in the token
--   * the sign-in was by an emailed link or code, never a password (nobody here has one; this closes that door
--     even if password sign-in or automatic confirmation were ever switched on by mistake)
--   * the emailed link was used within the last 12 hours. A browser keeps a sign-in alive indefinitely by
--     refreshing it, so without this a laptop that signed in once would stay an admin for good.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u join admins a on a.email = u.email::citext
    where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and u.email::citext = (auth.jwt() ->> 'email')::citext
      and not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) m where m ->> 'method' = 'password')
      and exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) m
                  where m ->> 'method' in ('otp', 'magiclink') and (m ->> 'timestamp')::bigint > extract(epoch from now()) - 12 * 3600));
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
