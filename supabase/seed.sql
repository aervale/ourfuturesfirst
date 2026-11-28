-- Local development only: sample verified sign-ups so the page has something to show.
-- Seeds are not applied to a hosted project.
-- About 1,300 people at 80 universities, a few large and most small, signed up over the past three weeks:
-- a steady trickle plus five bursts (a mailing list, a post that travelled). Recent ones are partly unconfirmed.
with l as (select d.domain dom, d.name uni, row_number() over (order by array_position(x.a, d.domain)) k
           from (select string_to_array('mit.edu,harvard.edu,stanford.edu,berkeley.edu,cmu.edu,columbia.edu,uchicago.edu,yale.edu,princeton.edu,umich.edu,gatech.edu,ucla.edu,cornell.edu,nyu.edu,upenn.edu,duke.edu,northwestern.edu,utexas.edu,washington.edu,illinois.edu,wisc.edu,brown.edu,dartmouth.edu,jhu.edu,caltech.edu,rice.edu,vanderbilt.edu,usc.edu,ucsd.edu,umd.edu,purdue.edu,osu.edu,psu.edu,umn.edu,unc.edu,virginia.edu,gwu.edu,georgetown.edu,bu.edu,northeastern.edu,tufts.edu,emory.edu,wustl.edu,nd.edu,colorado.edu,asu.edu,arizona.edu,utah.edu,ufl.edu,fsu.edu,miami.edu,rutgers.edu,pitt.edu,msu.edu,indiana.edu,uiowa.edu,iastate.edu,ku.edu,unl.edu,ou.edu,tamu.edu,uh.edu,tulane.edu,lsu.edu,ua.edu,uga.edu,clemson.edu,ncsu.edu,vt.edu,rochester.edu,case.edu,uci.edu,ucdavis.edu,ucsb.edu,oregonstate.edu,uoregon.edu,unm.edu,hawaii.edu,umass.edu,uconn.edu,swarthmore.edu,williams.edu,amherst.edu,wellesley.edu,pomona.edu', ',') a) x
           join public.uni_domains d on d.domain = any(x.a) and d.mx is not null),
u as (select dom, uni, greatest(1, round(1348 * power(k + 2, -1.45) / (select sum(power(k + 2, -1.45)) from l where k <= 80)))::int n from l where k <= 80),
-- r holds 20 independent random numbers per person, so no two details move together by accident
r0 as (select dom, uni, i, array(select random() from generate_series(1, 20) where i > 0) r from u, generate_series(1, n) i),
r1 as (select *, now() - case when r[1] < .58 then r[2] * interval '21 days'
        else (array[18.4, 13.2, 9.3, 5.1, 1.7])[1 + floor((r[1] - .58) / .42 * 5)::int] * interval '1 day' - least(30, -ln(greatest(r[2], 1e-9)) * 5) * interval '1 hour' end t,
        case when r[3] < .61 then 'an undergraduate' when r[3] < .87 then 'a graduate student' when r[3] < .92 then 'a postdoc' when r[3] < .97 then 'faculty' else 'staff' end role
      from r0)
insert into public.signups (email, name, show_name, uni, dom, role, year, phone, major, title, show_info, answers, spread, verified_at, created_at)
select 'sample' || i || '@' || dom,
  (array['Maya','Daniel','Priya','Lucas','Aisha','Ethan','Sofia','Noah','Mei','Omar','Hannah','Leo','Zara','Jonah','Ines','Kai','Grace','Mateo','Amara','Owen',
         'Nadia','Caleb','Yuki','Elena','Marcus','Leila','Ben','Anika','Diego','Chloe','Tariq','Julia','Sam','Ruth','Arjun','Nora','Felix','Imani','Theo','Lucia'])[1 + floor(r[4] * 40)::int]
    || ' ' || (array['Chen','Okafor','Patel','Rivera','Kim','Novak','Haddad','Brooks','Tanaka','Silva','Meyer','Osei','Lindqvist','Park','Romano','Shah','Nguyen','Garcia','Cohen','Adeyemi',
         'Walker','Ivanov','Murphy','Sato','Khan','Bianchi','Wright','Dubois','Hernandez','Olsen','Rahman','Fischer','Lopez','Johnson','Zhang','Petrov','Ali','Carter','Yamamoto','Evans'])[1 + floor(r[5] * 40)::int],
  r[6] < .62, uni, dom, role,
  case when role = 'an undergraduate' then case when r[7] < .31 then 'Freshman' when r[7] < .58 then 'Sophomore' when r[7] < .81 then 'Junior' else 'Senior' end else '' end,
  case when r[8] < .035 then '(555) 555-01' || lpad((i % 100)::text, 2, '0') else '' end,
  case when r[9] < .9 and role not in ('faculty', 'staff') then (array['Computer Science','Computer Science','Computer Science','Computer Science','Computer Science','Computer Science','Mathematics','Mathematics','Mathematics','Economics','Economics',
    'Physics','Physics','Electrical Engineering','Electrical Engineering','Biology','Biology','Political Science','Political Science','Philosophy','Philosophy','Psychology','Mechanical Engineering',
    'Neuroscience','Data Science','Statistics','Public Policy','History','English','Sociology','Chemistry'])[1 + floor(r[10] * 31)::int] else '' end,
  case when role = 'faculty' then (array['Professor of Physics','Associate Professor of Computer Science','Assistant Professor of Philosophy','Lecturer in Economics','Professor of Law','Assistant Professor of Statistics'])[1 + floor(r[11] * 6)::int]
       when role = 'staff' then (array['Research Administrator','Academic Advisor','Librarian','Lab Manager'])[1 + floor(r[11] * 4)::int] else '' end,
  r[12] < .8,
  jsonb_build_object(
    'feel',    case when r[13] < .12 then 'Mostly excited' when r[13] < .52 then 'A mix of both' when r[13] < .93 then 'Mostly worried' else 'Haven''t thought about it' end,
    'plans',   case when r[14] < .21 then 'Yes, I changed my plans' when r[14] < .52 then 'I am reconsidering' when r[14] < .85 then 'No' else 'Not sure yet' end,
    'job',     case when r[15] < .34 then 'It already can' when r[15] < .62 then 'Before I graduate' when r[15] < .9 then 'Within ten years' else 'Later, or never' end,
    'control', case when r[16] < .27 then 'Very likely' when r[16] < .66 then 'Somewhat likely' when r[16] < .91 then 'Not very likely' else 'Not at all likely' end,
    'risk',    case when r[17] < .24 then 'Misuse of AI' when r[17] < .46 then 'Loss of control over AI' when r[17] < .93 then 'Both equally' else 'Neither' end,
    'say',     case when r[18] < .04 then 'A lot' when r[18] < .2 then 'Some' when r[18] < .66 then 'Very little' else 'None' end)
    - case when role in ('an undergraduate', 'a graduate student') then '{}'::text[] else array['plans','job','say'] end,
  array_remove(array[case when r[19] < .2 then 'lists' end, case when r[20] < .38 then 'chats' end, case when r[8] < .035 then 'lead' end], null),
  case when t > now() - interval '2 days' and r[6] > .8 then null else least(now(), t + (2 + r[12] * 40) * interval '1 minute') end, least(now(), t)
from r1;

-- About a third arrived through an earlier person's share link, mostly someone at their own university.
-- People who offered to share or organize bring in the most.
update public.signups s set ref_by = coalesce((
  select p.ref from public.signups p
  where p.created_at < s.created_at - interval '20 minutes' and (p.dom = s.dom or left(s.id::text, 1) in ('0', '1', '2'))
  order by random() * case when 'lead' = any(p.spread) then .08 when 'chats' = any(p.spread) then .45 else 1 end limit 1), '')
where left(s.ref, 1) in ('0', '1', '2', '3', '4', '5');

-- Local test mode (config.js: dev). These functions exist only here, in the seed, so a hosted project
-- never has them: read the admin data without signing in.
create function public.dev_admin_rows() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(s) - 'edit_token' order by s.created_at desc), '[]'::jsonb) from signups s;
$$;
create function public.dev_admin_set_hidden(p_id uuid, p_hidden boolean) returns void language sql security definer set search_path = public as $$
  update signups set name_hidden = p_hidden where id = p_id;
$$;
grant execute on function public.dev_admin_rows(), public.dev_admin_set_hidden(uuid, boolean) to anon, authenticated;

-- Sharing counts (local test mode): the admin page reads them without signing in, like the rows above.
create function public.dev_admin_events() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'events', coalesce((select jsonb_agg(jsonb_build_array(extract(epoch from e.at)::bigint, e.kind, e.ref, e.src) order by e.at) from events e), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_array(extract(epoch from i.created_at)::bigint, s.ref, i.sent_at is not null) order by i.created_at)
                         from invites i join signups s on s.id = i.signup_id), '[]'::jsonb));
$$;
grant execute on function public.dev_admin_events() to anon, authenticated;

-- Sample sharing activity. About four in ten people press a share button; links that brought people in were opened
-- a few times for each person who joined, and a spread of other links were opened without anyone joining.
select setseed(0.42);
insert into events (at, kind, ref, src)
select s.created_at + random() * interval '20 minutes', k.kind, s.ref, ''
from signups s, lateral (select (array['copy','copy','copy','text','text','whatsapp','instagram','threads','share'])[1 + floor(random() * 9)::int] kind
                         from generate_series(1, case when random() < .4 then 1 + floor(random() * 2)::int else 0 end + (s.id is null)::int)) k;
insert into events (at, kind, ref, src)
select c.created_at - random() * interval '30 minutes', 'open', c.ref_by, (array['','','','text','text','whatsapp','email','threads','share'])[1 + floor(random() * 9)::int]
from signups c, generate_series(1, 4) g
where c.ref_by <> '' and (g = 1 or random() < .45);
insert into events (at, kind, ref, src)
select s.created_at + random() * interval '2 days', 'open', s.ref, (array['','','text','whatsapp','email'])[1 + floor(random() * 5)::int]
from signups s, generate_series(1, 3) g where random() < .12;

-- Page switches (local test mode): the admin page flips them without signing in.
create function public.dev_admin_set_switch(p_name text, p_shown boolean) returns jsonb language sql security definer set search_path = public as $$
  update page_switches set shown = p_shown, changed_at = now(), changed_by = 'local test mode' where name = p_name;
  select page_switches();
$$;
grant execute on function public.dev_admin_set_switch(text, boolean) to anon, authenticated;

-- Letter suggestions (local test mode): read and marked without signing in, plus a few samples.
create function public.dev_admin_suggestions() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'at', g.at, 'body', g.body, 'done', g.done,
           'name', s.name, 'uni', s.uni, 'role', s.role, 'email', s.email) order by g.at desc), '[]'::jsonb)
  from suggestions g left join signups s on s.id = g.signup_id;
$$;
create function public.dev_admin_set_suggestion_done(p_id bigint, p_done boolean) returns void language sql security definer set search_path = public as $$
  update suggestions set done = p_done where id = p_id;
$$;
grant execute on function public.dev_admin_suggestions(), public.dev_admin_set_suggestion_done(bigint, boolean) to anon, authenticated;
insert into suggestions (at, body, signup_id, done) values
  (now() - interval '3 days',  'Say "advanced AI" instead of "superintelligence" in the first mention. Half my lab would stop reading at that word.', (select id from signups where verified_at is not null order by created_at limit 1), true),
  (now() - interval '2 days',  'The last sentence asks two different groups for one thing. Split it: one ask of the government, one of the companies.', null, false),
  (now() - interval '26 hours', '"Enterprise of thought" appears twice in two sentences. Vary it.', (select id from signups where verified_at is not null order by created_at offset 40 limit 1), false),
  (now() - interval '5 hours',  'Add something about jobs. That is what people on my floor actually talk about.', null, false),
  (now() - interval '40 minutes','Shorter. It should fit on a phone screen without scrolling.', (select id from signups where verified_at is not null order by created_at offset 200 limit 1), false);

-- Organizer limits (local test mode): the admin page works them without signing in.
create function public.dev_admin_remove_organizer(p_id uuid) returns void language sql security definer set search_path = public as $$
  update signups set spread = array_remove(spread, 'lead') where id = p_id;
$$;
create function public.dev_admin_caps() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(dom, cap), '{}'::jsonb) from organizer_caps;
$$;
create function public.dev_admin_set_cap(p_dom text, p_cap int) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_cap is null then delete from organizer_caps where dom = p_dom and dom <> '*';
  else insert into organizer_caps (dom, cap, changed_by) values (p_dom, p_cap, 'local test mode')
       on conflict (dom) do update set cap = excluded.cap, changed_at = now(); end if;
  return (select coalesce(jsonb_object_agg(dom, cap), '{}'::jsonb) from organizer_caps);
end $$;
grant execute on function public.dev_admin_remove_organizer(uuid), public.dev_admin_caps(), public.dev_admin_set_cap(text, int) to anon, authenticated;

-- Accepting organizers or not, per university (local test mode).
create function public.dev_admin_closed() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(dom), '[]'::jsonb) from organizer_closed;
$$;
create function public.dev_admin_set_accepting(p_dom text, p_accepting boolean) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_accepting then delete from organizer_closed where dom = p_dom;
  else insert into organizer_closed (dom, changed_by) values (p_dom, 'local test mode') on conflict (dom) do nothing; end if;
  return (select coalesce(jsonb_agg(dom), '[]'::jsonb) from organizer_closed);
end $$;
grant execute on function public.dev_admin_closed(), public.dev_admin_set_accepting(text, boolean) to anon, authenticated;

-- Organizer bios (local test mode), with a few samples.
create function public.dev_admin_bios() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(signup_id, bio), '{}'::jsonb) from organizer_bios;
$$;
grant execute on function public.dev_admin_bios() to anon, authenticated;
insert into organizer_bios (signup_id, bio)
select id, (array[
  'I am a second-year PhD student in computer science working on program synthesis. I ran the graduate student council''s housing campaign last year, so I know how to get a room of people to show up. I want to help because most of my lab has an opinion about where AI is going and no place to put it.',
  'Junior studying economics and philosophy. I write for the student paper and help run a debate society of about sixty people. I care about this because the people deciding how fast AI moves are not the people who will live longest with the result.',
  'Postdoc in neuroscience. Before that I organized a union drive at my last university. I can reach the postdoc association and three departments directly.'
])[1 + (row_number() over (order by created_at))::int % 3]
from signups where 'lead' = any(spread) and verified_at is not null order by created_at limit 14;

-- Discord (local test mode): the admin page reads the server's state without signing in. While the bot's tables are
-- empty it shows made-up channels and members built from the sample sign-ups, so the page has something to show;
-- nothing is written to those tables, which discord/test.mjs expects to find empty.
create function public.dev_admin_discord() returns jsonb language sql stable security definer set search_path = public as $$
  with real as (select exists (select 1 from discord_members) or exists (select 1 from discord_unis) or exists (select 1 from discord_requests) any_rows),
  su as (select dom, min(uni) uni, row_number() over (order by count(*) desc) k from signups
         where verified_at is not null and 'lead' = any(spread) group by dom order by count(*) desc limit 6),
  sm as (select s.*, row_number() over (order by s.verified_at desc) k from signups s join su on su.dom = s.dom
         where s.verified_at is not null and ('lead' = any(s.spread) or abs(hashtext(s.email)) % 25 = 0) limit 40)
  select case when (select any_rows from real) then jsonb_build_object(
    'unis', coalesce((select jsonb_agg(jsonb_build_object('dom', u.dom, 'uni', u.uni, 'channel', u.channel_id, 'made', u.created_at) order by u.uni) from discord_unis u), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('name', m.discord_name, 'email', m.email, 'dom', m.dom, 'uni', m.uni,
                 'signup', m.signup_id, 'lead', coalesce('lead' = any(s.spread), false), 'intro', m.intro, 'joined', m.joined_at) order by m.joined_at desc)
               from discord_members m left join signups s on s.id = m.signup_id), '[]'::jsonb),
    'waiting', coalesce((select jsonb_agg(jsonb_build_object('name', r.discord_name, 'email', r.email, 'dom', r.dom, 'uni', r.uni, 'intro', r.intro, 'asked', r.asked_at) order by r.asked_at)
               from discord_requests r where r.decided_at is null), '[]'::jsonb))
  else jsonb_build_object(
    'unis', coalesce((select jsonb_agg(jsonb_build_object('dom', dom, 'uni', uni, 'channel', (910000000000000000 + k)::text, 'made', now())) from su), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('name', lower(split_part(name, ' ', 1)) || '_' || k, 'email', email, 'dom', dom, 'uni', uni, 'signup', id,
                 'lead', 'lead' = any(spread), 'intro', 'Hi, I am ' || split_part(name, ' ', 1) || '. I study ' || coalesce(nullif(major, ''), 'here') || ' and want to help get people at my university involved.',
                 'joined', verified_at) order by verified_at desc) from sm), '[]'::jsonb),
    'waiting', coalesce((select jsonb_agg(jsonb_build_object('name', 'sam_k', 'email', 'sam.k@' || dom, 'dom', dom, 'uni', uni,
                 'intro', 'Sophomore here, my university mail filter seems to eat everything. Happy to help however I can.', 'asked', now())) from su where k = 1), '[]'::jsonb))
  end;
$$;
grant execute on function public.dev_admin_discord() to anon, authenticated;

-- Named links (local test mode): made and removed without signing in, plus a few samples with opens and sign-ups.
create function public.dev_admin_links() returns jsonb language sql stable security definer set search_path = public as $$ select links_json(); $$;
create function public.dev_admin_make_link(p_slug text, p_label text, p_dom text) returns jsonb language plpgsql security definer set search_path = public as $$
declare s text := lower(trim(coalesce(p_slug, ''))); l text := trim(coalesce(p_label, '')); u text := '';
begin
  if s !~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' then return jsonb_build_object('error', 'bad_slug'); end if;
  if l = '' or char_length(l) > 120 then return jsonb_build_object('error', 'bad_label'); end if;
  if exists (select 1 from links where slug = s) then return jsonb_build_object('error', 'taken'); end if;
  if coalesce(p_dom, '') <> '' then select coalesce(min(uni), (select name from uni_domains where domain = p_dom limit 1), p_dom) into u from signups where dom = p_dom; end if;
  insert into links (slug, label, dom, uni, made_by) values (s, l, nullif(p_dom, ''), coalesce(u, ''), 'local test mode');
  return jsonb_build_object('links', links_json());
end $$;
create function public.dev_admin_remove_link(p_slug text) returns jsonb language sql security definer set search_path = public as $$
  delete from links where slug = p_slug; select jsonb_build_object('links', links_json());
$$;
grant execute on function public.dev_admin_links(), public.dev_admin_make_link(text, text, text), public.dev_admin_remove_link(text) to anon, authenticated;
insert into links (slug, label, dom, uni, made_by, created_at) values
  ('mit-the-tech', 'The Tech newsletter', 'mit.edu', 'MIT', 'david@example.edu', now() - interval '6 days'),
  ('harvard-cs-list', 'Harvard CS undergrad mailing list', 'harvard.edu', 'Harvard', 'april@example.edu', now() - interval '4 days'),
  ('instagram-bio', 'Instagram bio link', null, '', 'april@example.edu', now() - interval '9 days'),
  ('stanford-flyer', 'Flyers in Gates', 'stanford.edu', 'Stanford', 'david@example.edu', now() - interval '2 days');
insert into link_opens (slug, at)
select l.slug, now() - (abs(hashtext(l.slug || g)) % 1000) / 1000.0 * (now() - l.created_at) from links l, generate_series(1, 60) g
where abs(hashtext(g || l.slug)) % 100 < case l.slug when 'instagram-bio' then 90 when 'mit-the-tech' then 60 else 30 end;
insert into link_signups (signup_id, slug)
select s.id, case when s.dom = 'mit.edu' then 'mit-the-tech' when s.dom = 'harvard.edu' then 'harvard-cs-list' when s.dom = 'stanford.edu' then 'stanford-flyer' else 'instagram-bio' end
from signups s where abs(hashtext(s.email || 'l')) % 90 = 0 on conflict do nothing;
-- Email delivery report (local test mode): read without signing in.
create function public.dev_admin_mail_report() returns jsonb language sql stable security definer set search_path = public as $$
  select mail_report();
$$;
grant execute on function public.dev_admin_mail_report() to anon, authenticated;

-- Local test mode only: the admin page's removal counts without signing in.
create or replace function public.dev_admin_removal_report() returns jsonb language sql stable security definer set search_path = public as $$
  select removal_report();
$$;
grant execute on function public.dev_admin_removal_report() to anon, authenticated;
