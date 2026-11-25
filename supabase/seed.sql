-- Local development only: sample verified sign-ups so the page has something to show.
-- Seeds are not applied to a hosted project.
-- About 1,300 people at 80 universities, a few large and most small, signed up over the past three weeks:
-- a steady trickle plus five bursts (a mailing list, a post that travelled). Recent ones are partly unconfirmed.
with l as (select d.domain dom, d.name uni, row_number() over (order by array_position(x.a, d.domain)) k
           from (select string_to_array('mit.edu,harvard.edu,stanford.edu,berkeley.edu,cmu.edu,columbia.edu,uchicago.edu,yale.edu,princeton.edu,umich.edu,gatech.edu,ucla.edu,cornell.edu,nyu.edu,upenn.edu,duke.edu,northwestern.edu,utexas.edu,washington.edu,illinois.edu,wisc.edu,brown.edu,dartmouth.edu,jhu.edu,caltech.edu,rice.edu,vanderbilt.edu,usc.edu,ucsd.edu,umd.edu,purdue.edu,osu.edu,psu.edu,umn.edu,unc.edu,virginia.edu,gwu.edu,georgetown.edu,bu.edu,northeastern.edu,tufts.edu,emory.edu,wustl.edu,nd.edu,colorado.edu,asu.edu,arizona.edu,utah.edu,ufl.edu,fsu.edu,miami.edu,rutgers.edu,pitt.edu,msu.edu,indiana.edu,uiowa.edu,iastate.edu,ku.edu,unl.edu,ou.edu,tamu.edu,uh.edu,tulane.edu,lsu.edu,ua.edu,uga.edu,clemson.edu,ncsu.edu,vt.edu,rochester.edu,case.edu,uci.edu,ucdavis.edu,ucsb.edu,oregonstate.edu,uoregon.edu,unm.edu,hawaii.edu,umass.edu,uconn.edu,swarthmore.edu,williams.edu,amherst.edu,wellesley.edu,pomona.edu', ',') a) x
           join public.uni_domains d on d.domain = any(x.a) and d.mx is not null),
u as (select dom, uni, greatest(1, round(1348 * power(k + 2, -1.45) / (select sum(power(k + 2, -1.45)) from l where k <= 80)))::int n from l where k <= 80),
r0 as (select dom, uni, i, random() a, random() b, random() c, random() d, random() e, random() f, random() g, random() h, random() j from u, generate_series(1, n) i),
r as (select *, now() - case when g < .58 then h * interval '21 days'
        else (array[18.4, 13.2, 9.3, 5.1, 1.7])[1 + floor((g - .58) / .42 * 5)::int] * interval '1 day' - least(30, -ln(greatest(h, 1e-9)) * 5) * interval '1 hour' end t from r0)
insert into public.signups (email, name, show_name, uni, dom, role, year, phone, major, title, show_info, answers, spread, verified_at, created_at)
select 'sample' || i || '@' || dom,
  case when a < .6 then (array['Maya','Daniel','Priya','Lucas','Aisha','Ethan','Sofia','Noah','Mei','Omar','Hannah','Leo','Zara','Jonah','Ines','Kai'])[1 + floor(b * 16)::int]
    || ' ' || (array['Chen','Okafor','Patel','Rivera','Kim','Novak','Haddad','Brooks','Tanaka','Silva','Meyer','Osei','Lindqvist','Park','Romano','Shah'])[1 + floor(c * 16)::int] else '' end,
  true, uni, dom,
  (array['an undergraduate','an undergraduate','an undergraduate','an undergraduate','an undergraduate','an undergraduate','a graduate student','a graduate student','a postdoc','faculty','staff'])[1 + floor(f * 11)::int],
  case when f * 11 < 6 then (array['Freshman','Sophomore','Junior','Senior'])[1 + floor(d * 4)::int] else '' end,
  case when e < .035 then '(555) 555-01' || lpad((i % 100)::text, 2, '0') else '' end,
  case when c < .85 then (array['Computer Science','Computer Science','Computer Science','Economics','Physics','Mathematics','Biology','Political Science','Mechanical Engineering','Philosophy','Psychology','Electrical Engineering'])[1 + floor(d * 12)::int] else '' end,
  case when f * 11 >= 9 and f * 11 < 10 then (array['Professor of Physics','Associate Professor of Computer Science','Assistant Professor of Philosophy','Lecturer in Economics'])[1 + floor(a * 4)::int] else '' end,
  b < .8,
  jsonb_build_object(
    'feel',    (array['Mostly excited','A mix of both','Mostly worried','Haven''t thought about it'])[1 + floor(power(d, 0.7) * 3.4)::int],
    'plans',   (array['Yes, I changed my plans','I am reconsidering','No','Not sure yet'])[1 + floor(power(b, 0.9) * 3.6)::int],
    'job',     (array['It already can','Before I graduate','Within ten years','Later, or never'])[1 + floor(e * e * 4)::int],
    'control', (array['Very likely','Somewhat likely','Not very likely','Not at all likely'])[1 + floor(power(c, 1.3) * 3.7)::int],
    'risk',    (array['Misuse of AI','Loss of control over AI','Both equally','Neither'])[1 + floor(power(f, 0.8) * 3.3)::int],
    'say',     (array['A lot','Some','Very little','None'])[1 + floor(least(0.999, power(a, 0.5)) * 4)::int])
    - case when f * 11 >= 8 then array['plans','job','say'] else '{}'::text[] end,
  array_remove(array[case when h < .2 then 'lists' end, case when j < .38 then 'chats' end, case when e < .035 then 'lead' end], null),
  case when t > now() - interval '2 days' and j < .2 then null else least(now(), t + (2 + j * 40) * interval '1 minute') end, least(now(), t)
from r;

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
