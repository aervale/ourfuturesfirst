-- Fixes from a security review of the public database functions.

-- 1. A fresh edit key at the moment an email address is confirmed.
-- Until someone confirms, anyone who knows their address can resubmit the form and receive an edit key for
-- that entry (by design, so a typo can be fixed). Before this change that key kept working after the real
-- owner confirmed, so the other person could keep editing or delete a confirmed entry. Now confirming
-- replaces the key, and only the person who opened the emailed link gets the new one.
create or replace function public.confirm_signup() returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text := auth.jwt() ->> 'email'; r jsonb;
begin
  update signups set verified_at = now(), edit_token = gen_random_uuid()
  where email = e and verified_at is null and created_at > now() - interval '48 hours';
  select entry_json(s) into r from signups s where email = e;
  return r;
end $$;

-- 2. Friend invitations: at most one email per address.
create or replace function public.send_invite_email(p_id uuid) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  i invites; s signups; k text; who text; link text; body text; rid bigint;
begin
  select * into i from invites where id = p_id;
  if not found or i.sent_at is not null then return false; end if;
  -- one invitation per address, ever, and none to someone who has already signed up: the email promises
  -- "we will not email you again", and this stops several people (or one person with several accounts)
  -- from filling a stranger's inbox. Skipped invitations are marked sent with no request number.
  if exists (select 1 from invites x where x.email = i.email and x.id <> i.id and x.sent_at is not null)
     or exists (select 1 from signups x where x.email = i.email::text) then
    update invites set sent_at = now(), request_id = null where id = p_id;
    return false;
  end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null or k = '' then return false; end if;
  select * into s from signups where id = i.signup_id;
  -- first name only, and only if it passes the same screen as the public list
  who := case when s.name <> '' and name_ok(s.name) then split_part(trim(s.name), ' ', 1) else '' end;
  link := 'https://ourfuturesfirst.org/?r=' || s.ref || '&amp;s=e';
  body :=
    '<p>' || case when who <> '' then html_escape(who) || ' at ' || html_escape(s.uni) else 'Someone at ' || html_escape(s.uni) end ||
    ' thought you would want to hear about this.</p>' ||
    '<p>Students at U.S. universities are writing an open letter on regulating the development of AI, and we want as many voices as possible in it. ' ||
    'Tell us what you think in a two-minute form, and we will let you know when the letter is ready to sign.</p>' ||
    '<p><a href="' || link || '">Add your voice</a></p>' ||
    '<p style="color:#777;font-size:13px">You got this one email because ' || case when who <> '' then html_escape(who) else 'someone' end ||
    ' typed your address on ourfuturesfirst.org. We will not email you again unless you sign up yourself.</p>';
  select net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object(
      'from', 'Our Futures First <invites@ourfuturesfirst.org>',
      'reply_to', 'contact@ourfuturesfirst.org',
      'to', jsonb_build_array(i.email::text),
      'subject', case when who <> '' then who || ' invited you to help write an open letter on AI' else 'You''re invited to help write an open letter on AI' end,
      'html', body)
  ) into rid;
  update invites set sent_at = now(), request_id = rid where id = p_id;
  return true;
end $$;

revoke execute on function public.send_invite_email(uuid) from public, anon, authenticated;
