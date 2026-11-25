-- board() looks up each sign-up's major by lower(name). Without this index that is a full scan of the
-- majors list for every sign-up, which took several seconds at ~1,300 sign-ups and hit the 3s anon timeout.
create index if not exists majors_lower_name on public.majors (lower(name));
analyze public.majors;
