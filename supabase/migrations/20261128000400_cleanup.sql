-- The website no longer asks organizers for a bio (the Discord intro fills organizer_bios instead),
-- so the two functions visitors could call to write and read one go. admin_bios stays for the admin page.
drop function if exists public.set_organizer_bio(uuid, text);
drop function if exists public.get_organizer_bio(uuid);

-- Pin the search path (security advisor: function_search_path_mutable). sha256 and convert_to are in pg_catalog.
alter function public.discord_code_hash(text, text) set search_path = pg_catalog;
