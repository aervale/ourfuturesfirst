-- Email delivery, as Resend reports it. Resend calls the function supabase/functions/resend-webhook each time an
-- email is sent, delivered, delayed, bounced, marked as spam, or fails; the function hands the request to
-- mail_event() below, which checks Resend's signature and keeps one row per event.
--
-- What this can and cannot show: "delivered" means the receiving mail server accepted the email. Whether it then went
-- to the inbox or to Junk is never reported to senders (Microsoft and Google keep that to themselves), so the admin page
-- also shows the share of sign-ups who press the link in their email, per university: a university whose people rarely
-- confirm is the likeliest place for emails to be landing in Junk. "complained" is someone pressing "Report spam".
--
-- The signing secret Resend gives the webhook is kept in Vault as 'resend_webhook_secret'. It is written there straight
-- from Resend's reply when the webhook is created, so nobody has to copy it by hand.

create table public.mail_events (
  id         bigint generated always as identity primary key,
  svix_id    text unique,                 -- Resend's id for this delivery of the event; repeats are ignored
  email_id   text not null,               -- Resend's id for the email
  type       text not null,               -- sent, delivered, delivery_delayed, bounced, complained, failed, suppressed
  at         timestamptz not null,        -- when the event happened
  sent_at    timestamptz,                 -- when Resend accepted the email
  recipient  citext,
  subject    text not null default '',
  detail     text not null default '',    -- the reason given for a bounce, delay or failure
  queued_s   numeric                      -- on "sent": seconds from the person's request to Resend accepting the email
);
create index mail_events_email on public.mail_events (email_id);
create index mail_events_at on public.mail_events (at);
alter table public.mail_events enable row level security;
revoke all on table public.mail_events from anon, authenticated;

-- Called by the webhook function with the request exactly as it arrived. Returns 'ok', or why it was refused.
-- The signature is Svix's: HMAC-SHA256 of "<id>.<timestamp>.<body>" with the secret after "whsec_", base64.
create function public.mail_event(p_svix_id text, p_ts text, p_sig text, p_body text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  k text; want text; j jsonb; d jsonb; who text; sent timestamptz; asked timestamptz; t text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_webhook_secret' limit 1;
  if k is null or k = '' then return 'no_secret'; end if;
  if p_ts !~ '^\d{9,11}$' or abs(extract(epoch from now()) - p_ts::bigint) > 600 then return 'stale'; end if;
  want := encode(hmac(convert_to(p_svix_id || '.' || p_ts || '.' || p_body, 'UTF8'), decode(regexp_replace(k, '^whsec_', ''), 'base64'), 'sha256'), 'base64');
  if not exists (select 1 from regexp_split_to_table(coalesce(p_sig, ''), '\s+') s where split_part(s, ',', 2) = want) then
    return 'bad_signature';
  end if;

  j := p_body::jsonb; d := j -> 'data';
  t := regexp_replace(coalesce(j ->> 'type', ''), '^email\.', '');
  if d ->> 'email_id' is null or t = '' then return 'ok'; end if;   -- not about an email: nothing to keep
  who := lower(d -> 'to' ->> 0);
  sent := (d ->> 'created_at')::timestamptz;

  -- the request behind it, read the moment the email goes out (later sign-ups to the same address overwrite it)
  if t = 'sent' then
    select greatest(u.confirmation_sent_at, u.recovery_sent_at) into asked from auth.users u where lower(u.email) = who;
    if asked is null or asked > sent + interval '5 seconds' or asked < sent - interval '1 hour' then
      select i.created_at into asked from invites i where lower(i.email::text) = who and i.created_at <= sent + interval '5 seconds'
        order by i.created_at desc limit 1;
    end if;
  end if;

  insert into mail_events (svix_id, email_id, type, at, sent_at, recipient, subject, detail, queued_s)
  values (p_svix_id, d ->> 'email_id', t, coalesce((j ->> 'created_at')::timestamptz, now()), sent, who,
          left(coalesce(d ->> 'subject', ''), 200),
          left(coalesce(d -> 'bounce' ->> 'message', d -> 'failed' ->> 'reason', d -> 'delivery_delayed' ->> 'message', ''), 500),
          case when asked is not null and asked >= sent - interval '1 hour' then round(extract(epoch from sent - asked)::numeric, 1) end)
  on conflict (svix_id) do nothing;
  delete from mail_events where at < now() - interval '120 days';
  return 'ok';
end $$;

-- Admins: the delivery report on the admin page.
--   summary  the past 7 days: emails sent, delivered, how long delivery took, delays, bounces, spam reports
--   emails   the 40 most recent emails and what happened to each
--   confirm  for sign-ups made in the past 30 days (and at least an hour old): how many pressed the link, per university
create function public.admin_mail_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return mail_report();
end $$;

create or replace function public.mail_report() returns jsonb
language sql stable security definer set search_path = public as $$
  with e as (
    select email_id, min(sent_at) sent_at, max(recipient) recipient, max(subject) subject,
      max(queued_s) queued_s,
      min(at) filter (where type = 'delivered') delivered_at,
      bool_or(type = 'delivery_delayed') delayed,
      bool_or(type = 'bounced') bounced,
      bool_or(type = 'complained') complained,
      bool_or(type in ('failed', 'suppressed')) failed,
      string_agg(nullif(detail, ''), ' · ') detail
    from mail_events group by email_id),
  e2 as (select *, extract(epoch from delivered_at - sent_at) deliver_s,
           case when complained then 'reported as spam' when bounced then 'bounced' when failed then 'failed'
                when delivered_at is not null and delayed then 'delivered after a delay' when delivered_at is not null then 'delivered' when delayed then 'delayed' else 'sent' end status
         from e),
  wk as (select * from e2 where sent_at > now() - interval '7 days'),
  s as (
    select s.dom, s.uni, s.created_at, s.verified_at from signups s where s.created_at > now() - interval '30 days'
    union all
    select u.dom, u.uni, u.created_at, u.verified_at from signups_unconfirmed u where u.created_at > now() - interval '30 days'),
  c as (
    select dom, min(uni) uni, count(*) total, count(verified_at) confirmed,
      round((percentile_cont(.5) within group (order by extract(epoch from verified_at - created_at)) filter (where verified_at is not null) / 60)::numeric, 1) median_min
    from s where created_at < now() - interval '1 hour' group by dom)
  select jsonb_build_object(
    'tracking_since', (select min(at) from mail_events),
    'summary', (select jsonb_build_object(
        'sent', count(*), 'delivered', count(delivered_at),
        'deliver_median_s', round((percentile_cont(.5) within group (order by deliver_s))::numeric, 1),
        'deliver_p90_s', round((percentile_cont(.9) within group (order by deliver_s))::numeric, 1),
        'queued_median_s', round((percentile_cont(.5) within group (order by queued_s))::numeric, 1),
        'delayed', count(*) filter (where delayed), 'bounced', count(*) filter (where bounced),
        'complained', count(*) filter (where complained), 'failed', count(*) filter (where failed)) from wk),
    'emails', coalesce((select jsonb_agg(jsonb_build_object('sent_at', sent_at, 'to', recipient, 'subject', subject, 'status', status,
        'queued_s', queued_s, 'deliver_s', round(deliver_s::numeric, 1), 'detail', detail) order by sent_at desc)
      from (select * from e2 order by sent_at desc nulls last limit 40) x), '[]'::jsonb),
    'confirm', jsonb_build_object(
      'all', (select jsonb_build_object('total', coalesce(sum(total), 0), 'confirmed', coalesce(sum(confirmed), 0)) from c),
      'unis', coalesce((select jsonb_agg(jsonb_build_object('dom', dom, 'uni', uni, 'total', total, 'confirmed', confirmed, 'median_min', median_min)
                          order by total desc, uni) from (select * from c order by total desc, uni limit 25) x), '[]'::jsonb)));
$$;

revoke execute on function public.mail_event(text, text, text, text), public.admin_mail_report(), public.mail_report()
  from public, anon, authenticated;
grant execute on function public.mail_event(text, text, text, text) to service_role;
grant execute on function public.admin_mail_report() to authenticated;
