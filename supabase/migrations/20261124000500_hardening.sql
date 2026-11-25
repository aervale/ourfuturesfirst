-- Tighter access and abuse limits for a public launch.

-- 1. The page never touches tables directly; everything goes through the functions. Row level security
--    already blocks the anonymous and signed-in roles, and this takes away their table privileges as well
--    (including TRUNCATE, which row level security does not cover).
revoke all on table public.signups, public.signups_unconfirmed, public.invites, public.admins,
  public.uni_domains, public.majors from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- 2. Internal helpers get a fixed search path like the rest.
alter function public.entry_json(public.signups) set search_path = public;
alter function public.name_ok(text) set search_path = public;

-- 3. Rate limits for the two calls that write on behalf of an anonymous visitor.
--    Counted per network address over the past hour, with a ceiling across everyone as a circuit breaker.
--    The address is the one the hosting platform reports (it cannot be forged by the caller) and only a
--    hash of it is kept, for an hour.
create table public.throttle (
  kind text not null,
  who  text not null,
  at   timestamptz not null default now()
);
create index throttle_recent on public.throttle (kind, at);
alter table public.throttle enable row level security;
revoke all on table public.throttle from anon, authenticated;

create function public.throttle_check(p_kind text, p_per_address int, p_everyone int) returns void
language plpgsql security definer set search_path = public as $$
declare h jsonb := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
        xff text[] := string_to_array(replace(coalesce(h->>'x-forwarded-for', ''), ' ', ''), ',');
        ip text := coalesce(nullif(h->>'cf-connecting-ip', ''), nullif(h->>'sb-forwarded-for', ''), xff[array_length(xff, 1)], '');
        me text := md5(ip);
begin
  delete from throttle where at < now() - interval '1 hour';
  if (select count(*) from throttle where kind = p_kind and who = me) >= p_per_address
     or (select count(*) from throttle where kind = p_kind) >= p_everyone then
    raise exception 'slow_down';
  end if;
  insert into throttle (kind, who) values (p_kind, me);
end $$;

-- The existing functions keep their bodies under a new name; the public names become thin wrappers that
-- check the limit first. A whole campus can share a few addresses, so the per-address limits are generous.
alter function public.submit_interest(jsonb) rename to submit_interest_unlimited;
alter function public.send_invites(uuid, text[]) rename to send_invites_unlimited;

create function public.submit_interest(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform throttle_check('submit', 200, 5000);
  return submit_interest_unlimited(p);
end $$;

create function public.send_invites(p_token uuid, p_emails text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform throttle_check('invite', 40, 2000);
  return send_invites_unlimited(p_token, p_emails);
end $$;

revoke execute on function public.throttle_check(text, int, int), public.submit_interest_unlimited(jsonb),
  public.send_invites_unlimited(uuid, text[]), public.submit_interest(jsonb), public.send_invites(uuid, text[])
  from public, anon, authenticated;
grant execute on function public.submit_interest(jsonb), public.send_invites(uuid, text[]) to anon, authenticated;
