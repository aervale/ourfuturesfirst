-- The admin page's view of the Discord server: each university's channel, everyone who has confirmed an email
-- there (with whether they signed and whether they are a campus organizer), and requests to be let in by hand
-- that no one has answered yet. Read straight from the bot's tables, so it is always in step with the server.
create function public.admin_discord() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return jsonb_build_object(
    'unis', coalesce((select jsonb_agg(jsonb_build_object('dom', u.dom, 'uni', u.uni, 'channel', u.channel_id, 'made', u.created_at) order by u.uni)
                      from discord_unis u), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('name', m.discord_name, 'email', m.email, 'dom', m.dom, 'uni', m.uni,
                           'signup', m.signup_id, 'lead', coalesce('lead' = any(s.spread), false), 'intro', m.intro, 'joined', m.joined_at) order by m.joined_at desc)
                         from discord_members m left join signups s on s.id = m.signup_id), '[]'::jsonb),
    'waiting', coalesce((select jsonb_agg(jsonb_build_object('name', r.discord_name, 'email', r.email, 'dom', r.dom, 'uni', r.uni, 'intro', r.intro, 'asked', r.asked_at) order by r.asked_at)
                         from discord_requests r where r.decided_at is null), '[]'::jsonb));
end $$;

revoke execute on function public.admin_discord() from public, anon, authenticated;
grant execute on function public.admin_discord() to authenticated;
