-- A fourth page switch: everything about sharing on the confirmation card (the personal link, the share buttons,
-- the reach sky and the option to email invitations). Unlike the other three it starts on, because it is live today.
alter table public.page_switches drop constraint page_switches_name_check;
alter table public.page_switches add constraint page_switches_name_check check (name in ('ticker', 'results', 'who', 'sharing'));
insert into public.page_switches (name, shown) values ('sharing', true);
