-- Suggestions on the letter's wording, left from the Letter page.
-- Anyone can leave one anonymously. A person who has signed up and confirmed their email can attach their name
-- instead; that suggestion is then tied to their sign-up and removed with it. Suggestions are never shown publicly:
-- only admins read them.
create table public.suggestions (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  body      text not null check (char_length(body) between 1 and 2000),
  signup_id uuid references public.signups(id) on delete cascade,   -- null = anonymous
  done      boolean not null default false                          -- an admin has dealt with it
);
create index suggestions_at on public.suggestions (at desc);
alter table public.suggestions enable row level security;
revoke all on table public.suggestions from anon, authenticated;

-- Called by the page. With a token, the suggestion carries that person's name, but only if they are confirmed;
-- otherwise it is stored with no link to anyone. Limited per network address like the other public writes.
create function public.submit_suggestion(p_body text, p_token uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b text := trim(coalesce(p_body, '')); sid uuid;
begin
  if char_length(b) < 3 then raise exception 'too_short'; end if;
  if char_length(b) > 2000 then raise exception 'too_long'; end if;
  perform throttle_check('suggest', 12, 1500);
  if p_token is not null then
    select id into sid from signups where edit_token = p_token and verified_at is not null;
  end if;
  insert into suggestions (body, signup_id) values (b, sid);
  return jsonb_build_object('signed', sid is not null);
end $$;
revoke execute on function public.submit_suggestion(text, uuid) from public;
grant execute on function public.submit_suggestion(text, uuid) to anon, authenticated;

-- For the admin page: every suggestion, newest first, with who sent it when they chose to say.
create function public.admin_suggestions() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'at', g.at, 'body', g.body, 'done', g.done,
                            'name', s.name, 'uni', s.uni, 'role', s.role, 'email', s.email) order by g.at desc)
                   from suggestions g left join signups s on s.id = g.signup_id), '[]'::jsonb);
end $$;
revoke execute on function public.admin_suggestions() from public, anon;
grant execute on function public.admin_suggestions() to authenticated;

create function public.admin_set_suggestion_done(p_id bigint, p_done boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  update suggestions set done = p_done where id = p_id;
end $$;
revoke execute on function public.admin_set_suggestion_done(bigint, boolean) from public, anon;
grant execute on function public.admin_set_suggestion_done(bigint, boolean) to authenticated;
