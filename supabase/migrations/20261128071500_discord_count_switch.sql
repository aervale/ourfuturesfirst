-- One more page switch: how many people are in our Discord server, shown under each "Join our Discord" button.
-- The number comes from Discord's public invite (approximate_member_count), read by the page itself. It starts off.
alter table public.page_switches drop constraint page_switches_name_check;
alter table public.page_switches add constraint page_switches_name_check check (name in ('ticker', 'results', 'who', 'sharing', 'letter', 'about', 'list', 'discord', 'discord_count'));
insert into public.page_switches (name, shown) values ('discord_count', false) on conflict (name) do nothing;
