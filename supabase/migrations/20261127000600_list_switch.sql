-- One more page switch: the panel of names and universities beside the form. It starts on, because it is live today.
-- Switched off, the panel is greyed out with a line saying the list is not shown at the moment.
alter table public.page_switches drop constraint page_switches_name_check;
alter table public.page_switches add constraint page_switches_name_check check (name in ('ticker', 'results', 'who', 'sharing', 'letter', 'about', 'list'));
insert into public.page_switches (name, shown) values ('list', true);
