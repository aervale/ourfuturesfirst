-- Two more page switches: the Letter page and the About page. Both start on, because they are live today.
-- Switched off, the tab is gone, the page cannot be opened, and links to it are hidden.
alter table public.page_switches drop constraint page_switches_name_check;
alter table public.page_switches add constraint page_switches_name_check check (name in ('ticker', 'results', 'who', 'sharing', 'letter', 'about'));
insert into public.page_switches (name, shown) values ('letter', true), ('about', true);
