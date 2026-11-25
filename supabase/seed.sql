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

-- Local test mode (config.js: dev). These functions exist only here, in the seed, so a hosted project
-- never has them: confirm a sign-up without the email, and read the admin data without signing in.
create function public.dev_confirm(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r signups;
begin
  update signups set verified_at = now() where edit_token = p_token returning * into r;
  if not found then raise exception 'not_found'; end if;
  -- pretend three people came through this person's share link, so the card has numbers to show
  update signups set ref_by = r.ref where id in
    (select id from signups where dom = r.dom and verified_at is not null and ref_by = '' and id <> r.id limit 3);
  return entry_json(r);
end $$;
create function public.dev_admin_rows() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(s) - 'edit_token' order by s.created_at desc), '[]'::jsonb) from signups s;
$$;
create function public.dev_admin_set_hidden(p_id uuid, p_hidden boolean) returns void language sql security definer set search_path = public as $$
  update signups set name_hidden = p_hidden where id = p_id;
$$;
grant execute on function public.dev_confirm(uuid), public.dev_admin_rows(), public.dev_admin_set_hidden(uuid, boolean) to anon, authenticated;
