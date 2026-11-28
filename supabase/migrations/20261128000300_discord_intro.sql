-- Discord: everyone writes a short introduction to get in, typed on the same form as their university email.
-- It waits with their code (or their request to be let in by hand) and is posted in the server once they are placed.
-- The organizers' "About you" box on the website is gone; for someone whose email has a confirmed sign-up, the intro
-- also becomes the description the admin page shows beside them (organizer_bios).
alter table public.discord_codes add column intro text not null default '';
alter table public.discord_requests add column intro text not null default '';
alter table public.discord_members add column intro text not null default '';

-- Step 1, now with the intro. Same as before otherwise. The old two-argument form is replaced; p_intro has no
-- default, so a caller that leaves it out gets an error rather than a member with no intro.
drop function public.discord_start(text, text);
create function public.discord_start(p_discord_id text, p_email text, p_intro text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  e text := lower(trim(coalesce(p_email, ''))); i text := left(trim(coalesce(p_intro, '')), 1000); u jsonb; k text; code text;
begin
  if p_discord_id !~ '^[0-9]{5,25}$' then return jsonb_build_object('error', 'bad_request'); end if;
  if e !~ '^[^\s@]+@[^\s@]+$' or length(e) > 160 then return jsonb_build_object('error', 'bad_email'); end if;
  if char_length(i) < 20 then return jsonb_build_object('error', 'short_intro'); end if;
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
  insert into discord_codes (discord_id, email, code_hash, intro) values (p_discord_id, e, discord_code_hash(p_discord_id, code), i)
    on conflict (discord_id) do update set email = excluded.email, code_hash = excluded.code_hash, intro = excluded.intro, tries = 0, created_at = now();

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

-- What this account last typed, so the form opens filled in when they try again.
create function public.discord_draft(p_discord_id text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('email', email, 'intro', intro) from discord_codes where discord_id = p_discord_id),
                  (select jsonb_build_object('email', email, 'intro', intro) from discord_members where discord_id = p_discord_id),
                  '{}'::jsonb);
$$;

-- Placing now carries the intro: kept on the member, copied to the sign-up's description, and returned for the bot to post.
drop function public.discord_place(text, citext, text);
create function public.discord_place(p_discord_id text, p_email citext, p_discord_name text, p_intro text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u jsonb; s signups; old_id text; old_dom text; n int; i text := left(trim(coalesce(p_intro, '')), 1000);
begin
  u := lookup_uni(p_email::text);
  if u is null then return jsonb_build_object('error', 'not_university'); end if;
  select * into s from signups where email = p_email and verified_at is not null;

  select discord_id into old_id from discord_members where email = p_email and discord_id <> p_discord_id;
  select dom into old_dom from discord_members where discord_id = p_discord_id and dom <> u->>'dom';
  delete from discord_members where email = p_email or discord_id = p_discord_id;
  insert into discord_members (discord_id, discord_name, email, dom, uni, signup_id, intro)
    values (p_discord_id, left(coalesce(p_discord_name, ''), 80), p_email, u->>'dom', u->>'name', s.id, i);
  delete from discord_codes where discord_id = p_discord_id;
  if s.id is not null and i <> '' then
    insert into organizer_bios (signup_id, bio) values (s.id, i)
      on conflict (signup_id) do update set bio = excluded.bio, updated_at = now();
  end if;

  select count(*) into n from discord_members where dom = u->>'dom';
  return jsonb_build_object('ok', true, 'dom', u->>'dom', 'uni', u->>'name', 'signed', s.id is not null,
    'first_name', case when s.id is not null and name_ok(s.name) then split_part(trim(s.name), ' ', 1) else '' end,
    'count', n, 'replaced', old_id, 'moved_from', old_dom, 'intro', i);
end $$;

create or replace function public.discord_finish(p_discord_id text, p_code text, p_discord_name text) returns jsonb
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

  placed := discord_place(p_discord_id, c.email, p_discord_name, c.intro);
  if placed ? 'error' then return placed; end if;
  return placed || jsonb_build_object('team', exists (select 1 from discord_team where email = c.email));
end $$;

-- The request to be let in by hand carries the intro too, so the core team can read it before approving.
create or replace function public.discord_request(p_discord_id text, p_discord_name text) returns jsonb
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
    update discord_requests set intro = c.intro where id = r.id;
    return jsonb_build_object('ok', true, 'id', r.id, 'post', r.message_id is null, 'email', r.email, 'dom', r.dom, 'uni', r.uni, 'held_by', held, 'intro', c.intro);
  end if;
  if found and r.approved is false and r.decided_at > now() - interval '1 day' then return jsonb_build_object('error', 'declined'); end if;
  if (select count(*) from discord_requests where asked_at > now() - interval '1 hour') >= 40 then return jsonb_build_object('error', 'busy'); end if;

  delete from discord_requests where discord_id = p_discord_id;
  insert into discord_requests (discord_id, discord_name, email, dom, uni, intro)
    values (p_discord_id, left(coalesce(p_discord_name, ''), 80), c.email, u->>'dom', u->>'name', c.intro) returning * into r;
  return jsonb_build_object('ok', true, 'id', r.id, 'post', true, 'email', r.email, 'dom', r.dom, 'uni', r.uni, 'held_by', held, 'intro', r.intro);
end $$;

create or replace function public.discord_decide(p_request bigint, p_by text, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r discord_requests; placed jsonb; base jsonb;
begin
  select * into r from discord_requests where id = p_request and decided_at is null for update;
  if not found then return jsonb_build_object('error', 'no_request'); end if;
  base := jsonb_build_object('ok', true, 'approved', p_approve, 'discord_id', r.discord_id, 'uni', r.uni);
  if p_approve and not exists (select 1 from discord_members where discord_id = r.discord_id and email = r.email) then
    placed := discord_place(r.discord_id, r.email, r.discord_name, r.intro);
    if placed ? 'error' then return placed; end if;
    base := placed || base;
  elsif p_approve then
    base := base || jsonb_build_object('already', true);
  end if;
  update discord_requests set decided_at = now(), decided_by = p_by, approved = p_approve where id = p_request;
  return base;
end $$;

revoke execute on function public.discord_start(text, text, text), public.discord_draft(text),
  public.discord_place(text, citext, text, text) from public, anon, authenticated;
grant execute on function public.discord_start(text, text, text), public.discord_draft(text) to service_role;
