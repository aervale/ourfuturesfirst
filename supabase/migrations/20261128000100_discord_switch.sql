-- One more page switch: the Discord link for campus organizers (footer icon, the Contact list, the note shown to someone
-- volunteering as an organizer, and the sentence in "What is a campus organizer?"). It starts on.
alter table public.page_switches drop constraint page_switches_name_check;
alter table public.page_switches add constraint page_switches_name_check check (name in ('ticker', 'results', 'who', 'sharing', 'letter', 'about', 'list', 'discord'));
insert into public.page_switches (name, shown) values ('discord', true) on conflict (name) do nothing;
