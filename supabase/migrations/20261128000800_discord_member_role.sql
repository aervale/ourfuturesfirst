-- Discord roles: everyone who confirms their university email gets the Member role (which lets them see the server),
-- and only campus organizers, people whose confirmed sign-up offered to organize, also get Organizer. Placing someone
-- now says which they are (`lead`). The roles themselves are made by discord/setup.mjs and handed out by the bot.

create or replace function public.discord_place(p_discord_id text, p_email citext, p_discord_name text, p_intro text) returns jsonb
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
    'count', n, 'replaced', old_id, 'moved_from', old_dom, 'intro', i,
    'lead', s.id is not null and 'lead' = any(s.spread));
end $$;
