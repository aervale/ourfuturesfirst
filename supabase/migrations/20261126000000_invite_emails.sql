-- Friend invitations are emailed through Resend as soon as they are saved.
-- The Resend API key lives in Supabase Vault under the name 'resend_api_key'. Add it once in the SQL editor:
--   select vault.create_secret('re_...', 'resend_api_key');
-- Until that secret exists, invitations are saved but not sent (sent_at stays empty), and
-- send_pending_invites() sends them later.

create extension if not exists pg_net;

alter table public.invites add column if not exists request_id bigint;

create or replace function public.html_escape(t text) returns text
language sql immutable as $$
  select replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

-- Sends one invitation. Returns false if the key is missing or the invitation was already sent.
create or replace function public.send_invite_email(p_id uuid) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  i invites; s signups; k text; who text; link text; body text; rid bigint;
begin
  select * into i from invites where id = p_id;
  if not found or i.sent_at is not null then return false; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null or k = '' then return false; end if;
  select * into s from signups where id = i.signup_id;
  -- first name only, and only if it passes the same screen as the public list
  who := case when s.name <> '' and name_ok(s.name) then split_part(trim(s.name), ' ', 1) else '' end;
  link := 'https://ourfuturesfirst.org/?r=' || s.ref;
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

create or replace function public.invites_send_new() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform send_invite_email(new.id);
  return new;
end $$;

drop trigger if exists invites_send on public.invites;
create trigger invites_send after insert on public.invites for each row execute function public.invites_send_new();

-- Sends any invitations saved before the key was added. Run it by hand from the SQL editor.
create or replace function public.send_pending_invites() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from invites where sent_at is null order by created_at loop
    if send_invite_email(r.id) then n := n + 1; end if;
  end loop;
  return n;
end $$;

revoke execute on function public.send_invite_email(uuid), public.invites_send_new(), public.send_pending_invites(), public.html_escape(text)
  from public, anon, authenticated;
