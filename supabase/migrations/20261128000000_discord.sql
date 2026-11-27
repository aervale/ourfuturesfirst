-- Discord: the organizers' server. A bot (supabase/functions/discord) asks each newcomer for their
-- university email, emails it a 6-digit code, and once the code comes back puts them in their
-- university's channel. These tables and functions are the bot's side of that; only the bot
-- (service_role) can reach them.

-- Everyone who has confirmed a university email in Discord, signed up or not, with their sign-up
-- when that email has a confirmed one. One Discord account per email address: confirming again
-- from a new account moves the entry.
-- (Nothing is added to public.signups itself: sweep_unconfirmed() copies its rows by position into
-- signups_unconfirmed, so a new column there would break every new sign-up.)
create table public.discord_members (
  discord_id   text primary key,
  discord_name text not null default '',
  email        citext not null unique,
  dom          text not null,
  uni          text not null,
  signup_id    uuid references public.signups(id) on delete set null,
  joined_at    timestamptz not null default now()
);
alter table public.discord_members enable row level security;

-- A code waiting to be typed back. One per Discord account; asking again replaces it.
-- Only a hash of the code is kept. It works for an hour and five tries: long enough to find an email
-- that a university's filter put in Junk, which is where the first real one landed.
create table public.discord_codes (
  discord_id text primary key,
  email      citext not null,
  code_hash  text not null,
  tries      smallint not null default 0,
  created_at timestamptz not null default now()
);
alter table public.discord_codes enable row level security;

-- Codes asked for, to cap how many go out: per Discord account, per address, and overall.
create table public.discord_asks (
  discord_id text not null,
  email      citext not null,
  at         timestamptz not null default now()
);
create index discord_asks_recent on public.discord_asks (at);
alter table public.discord_asks enable row level security;

-- Each university's role and channel in the server, made the first time someone from it arrives.
-- The row is written before the channel exists, so two people arriving at once make one channel.
create table public.discord_unis (
  dom        text primary key,
  uni        text not null,
  role_id    text,
  channel_id text,
  created_at timestamptz not null default now()
);
alter table public.discord_unis enable row level security;

-- "I didn't get a code": a request to be let in by hand, which a core team member approves or declines
-- in #mod-log. One per Discord account; asking again under another address replaces it (new id), so a
-- button on an old #mod-log message can never approve an address that message does not show.
create table public.discord_requests (
  id           bigint generated always as identity primary key,
  discord_id   text not null unique,
  discord_name text not null default '',
  email        citext not null,
  dom          text not null,
  uni          text not null,
  message_id   text,            -- the #mod-log message, once the bot has posted it
  asked_at     timestamptz not null default now(),
  decided_at   timestamptz,
  decided_by   text,            -- Discord id of the core team member
  approved     boolean
);
alter table public.discord_requests enable row level security;

-- The core team, by email. Someone who confirms one of these addresses with an emailed code is given
-- the Core team role as well. Approval by hand never gives it: that would let a typed address, not a
-- proven one, into the team. Add people with: insert into public.discord_team (email) values ('...');
create table public.discord_team (
  email    citext primary key,
  added_at timestamptz not null default now()
);
alter table public.discord_team enable row level security;

revoke all on table public.discord_members, public.discord_codes, public.discord_asks, public.discord_unis,
  public.discord_requests, public.discord_team from anon, authenticated;

create function public.discord_code_hash(p_discord_id text, p_code text) returns text
language sql immutable as $$
  select encode(sha256(convert_to(p_discord_id || ':' || p_code, 'UTF8')), 'hex');
$$;

-- Step 1: someone typed their university email. Emails it a code through Resend (the same key the
-- friend invitations use). Returns {ok, uni} or {error}: bad_email, not_university, slow_down, mail_off.
-- The code row is written before the mail is tried: it is also the record of which address this
-- account typed, which a request to be let in by hand (discord_request) reads.
-- The code goes out from contact@, the address the sign-up confirmation comes from, so signers have
-- already had mail from it, and with a plain-text copy beside the HTML: both make a university's
-- mail filter less likely to hold it back.
create function public.discord_start(p_discord_id text, p_email text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  e text := lower(trim(coalesce(p_email, ''))); u jsonb; k text; code text;
begin
  if p_discord_id !~ '^[0-9]{5,25}$' then return jsonb_build_object('error', 'bad_request'); end if;
  if e !~ '^[^\s@]+@[^\s@]+$' or length(e) > 160 then return jsonb_build_object('error', 'bad_email'); end if;
  u := lookup_uni(e);
  if u is null then return jsonb_build_object('error', 'not_university'); end if;

  delete from discord_asks where at < now() - interval '1 day';
  if (select count(*) from discord_asks where discord_id = p_discord_id and at > now() - interval '1 hour') >= 5
     or (select count(*) from discord_asks where email = e and at > now() - interval '1 hour') >= 3
     or (select count(*) from discord_asks where at > now() - interval '1 hour') >= 600 then
    return jsonb_build_object('error', 'slow_down');
  end if;

  code := lpad((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');
  insert into discord_asks (discord_id, email) values (p_discord_id, e);
  insert into discord_codes (discord_id, email, code_hash) values (p_discord_id, e, discord_code_hash(p_discord_id, code))
    on conflict (discord_id) do update set email = excluded.email, code_hash = excluded.code_hash, tries = 0, created_at = now();

  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null or k = '' then return jsonb_build_object('error', 'mail_off', 'uni', u->>'name'); end if;

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object(
      'from', 'Our Futures First <contact@ourfuturesfirst.org>',
      'reply_to', 'contact@ourfuturesfirst.org',
      'to', jsonb_build_array(e),
      'subject', code || ' is your Our Futures First Discord code',
      'text',
        'Your code for the Our Futures First Discord server: ' || code || E'\n\n' ||
        'Type it into Discord to join the chat for ' || (u->>'name') || '. It works for an hour.' || E'\n\n' ||
        'Someone typed this address in our Discord server. If that was not you, ignore this email and nothing happens.',
      'html',
        '<p>Your code for the Our Futures First Discord server:</p>' ||
        '<p style="font-size:28px;font-weight:700;letter-spacing:4px">' || code || '</p>' ||
        '<p>Type it into Discord to join the chat for ' || html_escape(u->>'name') || '. It works for an hour.</p>' ||
        '<p style="color:#777;font-size:13px">Someone typed this address in our Discord server. If that was not you, ignore this email and nothing happens.</p>')
  );
  return jsonb_build_object('ok', true, 'uni', u->>'name');
end $$;

-- Records an account as a member under an address that has been accepted (its code came back, or a core
-- team member approved it) and says which university it belongs with. Used by discord_finish and
-- discord_decide; not callable from outside. Returns {ok, dom, uni, signed, first_name, count, replaced, moved_from}.
-- `replaced` is the Discord account that held this email before, if any: the bot takes its roles away.
-- `moved_from` is the university this Discord account was in before, if it was a different one.
create function public.discord_place(p_discord_id text, p_email citext, p_discord_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u jsonb; s signups; old_id text; old_dom text; n int;
begin
  u := lookup_uni(p_email::text);
  if u is null then return jsonb_build_object('error', 'not_university'); end if;
  select * into s from signups where email = p_email and verified_at is not null;

  select discord_id into old_id from discord_members where email = p_email and discord_id <> p_discord_id;
  select dom into old_dom from discord_members where discord_id = p_discord_id and dom <> u->>'dom';
  delete from discord_members where email = p_email or discord_id = p_discord_id;
  insert into discord_members (discord_id, discord_name, email, dom, uni, signup_id)
    values (p_discord_id, left(coalesce(p_discord_name, ''), 80), p_email, u->>'dom', u->>'name', s.id);
  delete from discord_codes where discord_id = p_discord_id;

  select count(*) into n from discord_members where dom = u->>'dom';
  return jsonb_build_object('ok', true, 'dom', u->>'dom', 'uni', u->>'name', 'signed', s.id is not null,
    'first_name', case when s.id is not null and name_ok(s.name) then split_part(trim(s.name), ' ', 1) else '' end,
    'count', n, 'replaced', old_id, 'moved_from', old_dom);
end $$;

-- Step 2: the code came back. Records the member, links their sign-up if this email has a confirmed one,
-- and says which university they belong with. Returns what discord_place returns plus `team` (this
-- address is on the core team list), or {error}: no_code, expired, too_many_tries, wrong_code.
create function public.discord_finish(p_discord_id text, p_code text, p_discord_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c discord_codes; placed jsonb;
begin
  select * into c from discord_codes where discord_id = p_discord_id;
  if not found then return jsonb_build_object('error', 'no_code'); end if;
  if c.created_at < now() - interval '1 hour' then
    delete from discord_codes where discord_id = p_discord_id;
    return jsonb_build_object('error', 'expired');
  end if;
  if c.tries >= 5 then return jsonb_build_object('error', 'too_many_tries'); end if;
  if c.code_hash <> discord_code_hash(p_discord_id, regexp_replace(coalesce(p_code, ''), '\D', '', 'g')) then
    update discord_codes set tries = tries + 1 where discord_id = p_discord_id;
    return jsonb_build_object('error', 'wrong_code', 'left', 4 - c.tries);
  end if;

  placed := discord_place(p_discord_id, c.email, p_discord_name);
  if placed ? 'error' then return placed; end if;
  return placed || jsonb_build_object('team', exists (select 1 from discord_team where email = c.email));
end $$;

-- "I didn't get a code": asks the core team to let this account in by hand, under the address it last
-- typed (its discord_codes row, at most a day old). Returns {ok, id, post, email, dom, uni, held_by}:
-- `post` says the bot should put the request in #mod-log (false when it is already there), `held_by` is
-- another Discord account that has already confirmed this address. Errors: no_code, declined, busy.
create function public.discord_request(p_discord_id text, p_discord_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c discord_codes; u jsonb; r discord_requests; held text;
begin
  select * into c from discord_codes where discord_id = p_discord_id and created_at > now() - interval '1 day';
  if not found then return jsonb_build_object('error', 'no_code'); end if;
  u := lookup_uni(c.email::text);
  if u is null then return jsonb_build_object('error', 'not_university'); end if;
  select discord_id into held from discord_members where email = c.email and discord_id <> p_discord_id;

  select * into r from discord_requests where discord_id = p_discord_id;
  if found and r.decided_at is null and r.email = c.email then
    return jsonb_build_object('ok', true, 'id', r.id, 'post', r.message_id is null, 'email', r.email, 'dom', r.dom, 'uni', r.uni, 'held_by', held);
  end if;
  if found and r.approved is false and r.decided_at > now() - interval '1 day' then return jsonb_build_object('error', 'declined'); end if;
  if (select count(*) from discord_requests where asked_at > now() - interval '1 hour') >= 40 then return jsonb_build_object('error', 'busy'); end if;

  delete from discord_requests where discord_id = p_discord_id;
  insert into discord_requests (discord_id, discord_name, email, dom, uni)
    values (p_discord_id, left(coalesce(p_discord_name, ''), 80), c.email, u->>'dom', u->>'name') returning * into r;
  return jsonb_build_object('ok', true, 'id', r.id, 'post', true, 'email', r.email, 'dom', r.dom, 'uni', r.uni, 'held_by', held);
end $$;

create function public.discord_request_posted(p_request bigint, p_message_id text) returns void
language sql security definer set search_path = public as $$
  update discord_requests set message_id = p_message_id where id = p_request;
$$;

-- A core team member pressed Approve or Decline. Approving records the member exactly as a code would
-- (discord_place), without the Core team role. Returns {ok, approved, discord_id, uni} plus, when
-- approved, either `already` (their code arrived in the meantime) or what discord_place returns.
-- Error: no_request (already decided, or replaced by a newer request).
create function public.discord_decide(p_request bigint, p_by text, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r discord_requests; placed jsonb; base jsonb;
begin
  select * into r from discord_requests where id = p_request and decided_at is null for update;
  if not found then return jsonb_build_object('error', 'no_request'); end if;
  base := jsonb_build_object('ok', true, 'approved', p_approve, 'discord_id', r.discord_id, 'uni', r.uni);
  if p_approve and not exists (select 1 from discord_members where discord_id = r.discord_id and email = r.email) then
    placed := discord_place(r.discord_id, r.email, r.discord_name);
    if placed ? 'error' then return placed; end if;
    base := placed || base;
  elsif p_approve then
    base := base || jsonb_build_object('already', true);
  end if;
  update discord_requests set decided_at = now(), decided_by = p_by, approved = p_approve where id = p_request;
  return base;
end $$;

-- The university's role and channel. `mine` is true for the one caller who should create them;
-- everyone else gets the ids once that caller has saved them with discord_uni_save.
create function public.discord_uni(p_dom text, p_uni text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r discord_unis; fresh boolean := false; made int;
begin
  insert into discord_unis (dom, uni) values (p_dom, p_uni) on conflict (dom) do nothing;
  get diagnostics made = row_count;
  fresh := made > 0;
  select * into r from discord_unis where dom = p_dom;
  -- a row left without a channel for over a minute means its maker failed: hand the job to this caller
  if not fresh and r.channel_id is null and r.created_at < now() - interval '1 minute' then
    update discord_unis set created_at = now() where dom = p_dom;
    fresh := true;
  end if;
  return jsonb_build_object('mine', fresh, 'role_id', r.role_id, 'channel_id', r.channel_id);
end $$;

create function public.discord_uni_save(p_dom text, p_role_id text, p_channel_id text) returns void
language sql security definer set search_path = public as $$
  update discord_unis set role_id = p_role_id, channel_id = p_channel_id where dom = p_dom;
$$;

revoke execute on function public.discord_code_hash(text, text), public.discord_start(text, text),
  public.discord_place(text, citext, text), public.discord_finish(text, text, text),
  public.discord_request(text, text), public.discord_request_posted(bigint, text), public.discord_decide(bigint, text, boolean),
  public.discord_uni(text, text), public.discord_uni_save(text, text, text)
  from public, anon, authenticated;
grant execute on function public.discord_start(text, text), public.discord_finish(text, text, text),
  public.discord_request(text, text), public.discord_request_posted(bigint, text), public.discord_decide(bigint, text, boolean),
  public.discord_uni(text, text), public.discord_uni_save(text, text, text) to service_role;
