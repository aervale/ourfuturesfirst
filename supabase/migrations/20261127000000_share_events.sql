-- Sharing counts for the admin page: how often personal links are opened, and which share buttons are pressed.
-- A row is a kind, the share link it belongs to, the channel and the time. Nothing about the visitor is kept:
-- no cookie, no network address, no device details.

create table public.events (
  id   bigint generated always as identity primary key,
  at   timestamptz not null default now(),
  kind text not null,              -- open (a personal link was opened), or a button: copy, text, whatsapp, threads, instagram, share
  ref  text not null references public.signups(ref) on delete cascade,  -- the share link it belongs to; removed with the sign-up
  src  text not null default ''    -- for open: how the link was sent, when the link says so
);
create index events_ref on public.events (ref);
alter table public.events enable row level security;
revoke all on table public.events from anon, authenticated;

-- Called by the page. Unknown kinds and unknown links are dropped quietly; the hourly limits are the same
-- kind as for sign-ups (per network address, with a ceiling across everyone).
create function public.log_event(p_kind text, p_ref text, p_src text default '') returns void
language plpgsql security definer set search_path = public as $$
declare v text := case p_src when 't' then 'text' when 'w' then 'whatsapp' when 'h' then 'threads' when 'e' then 'email' when 'n' then 'share' else '' end;
begin
  if p_kind not in ('open', 'copy', 'text', 'whatsapp', 'threads', 'instagram', 'share') then return; end if;
  if p_ref is null or not exists (select 1 from signups where ref = p_ref) then return; end if;
  perform throttle_check('event', 300, 50000);
  insert into events (kind, ref, src) values (p_kind, p_ref, case when p_kind = 'open' then v else '' end);
end $$;
revoke execute on function public.log_event(text, text, text) from public;
grant execute on function public.log_event(text, text, text) to anon, authenticated;

-- For the admin page: every event as [seconds, kind, link, channel], and every emailed invitation as [seconds, link, sent].
create function public.admin_events() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return jsonb_build_object(
    'events', coalesce((select jsonb_agg(jsonb_build_array(extract(epoch from e.at)::bigint, e.kind, e.ref, e.src) order by e.at) from events e), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_array(extract(epoch from i.created_at)::bigint, s.ref, i.sent_at is not null) order by i.created_at)
                         from invites i join signups s on s.id = i.signup_id), '[]'::jsonb));
end $$;
revoke execute on function public.admin_events() from public, anon;
grant execute on function public.admin_events() to authenticated;

-- Invitation emails carry s=e in their link, so opens that came from an email can be told apart.
-- Same function as before with that one change to the link.
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
