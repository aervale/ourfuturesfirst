-- Admin page: how long the most recent email took, from the moment someone asked for it to the moment
-- Resend accepted it for sending.
--
-- The sending key (vault secret 'resend_api_key') can only send, by design. Reading Resend's list of sent
-- emails needs a second key with full access, kept in Vault under 'resend_read_key':
--   select vault.create_secret('re_...', 'resend_read_key');
-- Until it exists, the admin page says the timing is not set up. Neither key ever leaves the database.
--
-- Two calls, because the database fetches the web asynchronously: the first asks Resend and returns a
-- request number; the second, a moment later, reads the answer.

create or replace function public.admin_mail_check() returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare k text;
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_read_key' limit 1;
  if k is null or k = '' then return null; end if;
  return net.http_get('https://api.resend.com/emails?limit=1',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k));
end $$;

create or replace function public.admin_mail_result(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r record; e jsonb; who text; sent timestamptz; asked timestamptz; kind text;
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  select status_code, content into r from net._http_response where id = p_id;
  if not found then return jsonb_build_object('state', 'waiting'); end if;
  if r.status_code <> 200 then return jsonb_build_object('state', 'error', 'code', r.status_code); end if;
  e := (r.content::jsonb) -> 'data' -> 0;
  if e is null then return jsonb_build_object('state', 'none'); end if;
  who := lower(e -> 'to' ->> 0);
  sent := (e ->> 'created_at')::timestamptz;
  -- the request behind it: a confirmation or sign-in link for that address, or a friend's invitation to it
  select greatest(u.confirmation_sent_at, u.recovery_sent_at), 'link' into asked, kind
    from auth.users u where lower(u.email) = who;
  if asked is null or asked > sent + interval '5 seconds' or asked < sent - interval '1 hour' then
    select i.created_at, 'invite' into asked, kind from invites i
      where lower(i.email::text) = who and i.created_at <= sent + interval '5 seconds'
      order by i.created_at desc limit 1;
  end if;
  return jsonb_build_object('state', 'ok', 'subject', e ->> 'subject', 'sent_at', sent,
    'last_event', e ->> 'last_event', 'kind', kind,
    'seconds', case when asked is not null and asked >= sent - interval '1 hour'
                    then round(extract(epoch from sent - asked)::numeric, 1) end);
end $$;

revoke execute on function public.admin_mail_check(), public.admin_mail_result(bigint) from public, anon;
grant execute on function public.admin_mail_check(), public.admin_mail_result(bigint) to authenticated;
