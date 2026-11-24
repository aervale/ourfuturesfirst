-- Local development only: sample verified sign-ups so the page has something to show.
-- Seeds are not applied to a hosted project.
with u(dom, uni, n) as (values
  ('mit.edu','MIT',34),('harvard.edu','Harvard',21),('stanford.edu','Stanford',17),('berkeley.edu','UC Berkeley',14),
  ('cmu.edu','Carnegie Mellon',11),('columbia.edu','Columbia',9),('uchicago.edu','UChicago',8),('yale.edu','Yale',7),
  ('princeton.edu','Princeton',6),('umich.edu','University of Michigan',6),('gatech.edu','Georgia Tech',5),
  ('ucla.edu','UCLA',4),('cornell.edu','Cornell',3),('nyu.edu','NYU',2)),
r as (select dom, uni, i, random() a, random() b, random() c, random() d, random() e, random() f from u, generate_series(1, n) i)
insert into public.signups (email, name, show_name, uni, dom, answers, spread, verified_at, created_at)
select 'sample' || i || '@' || dom,
  case when a < .6 then (array['Maya','Daniel','Priya','Lucas','Aisha','Ethan','Sofia','Noah','Mei','Omar','Hannah','Leo','Zara','Jonah','Ines','Kai'])[1 + floor(b * 16)::int]
    || ' ' || (array['Chen','Okafor','Patel','Rivera','Kim','Novak','Haddad','Brooks','Tanaka','Silva','Meyer','Osei','Lindqvist','Park','Romano','Shah'])[1 + floor(c * 16)::int] else '' end,
  true, uni, dom,
  jsonb_build_object(
    'feel',    (array['Mostly excited','A mix of both','Mostly worried','Haven''t thought about it'])[1 + floor(power(d, 0.7) * 3.4)::int],
    'plans',   (array['Yes, I changed my plans','I am reconsidering','No','Not sure yet'])[1 + floor(power(b, 0.9) * 3.6)::int],
    'job',     (array['It already can','Before I graduate','Within ten years','Later, or never'])[1 + floor(e * e * 4)::int],
    'control', (array['Very likely','Somewhat likely','Not very likely','Not at all likely'])[1 + floor(power(c, 1.3) * 3.7)::int],
    'risk',    (array['AI misuse','AI loss of control','Both equally','Neither'])[1 + floor(power(f, 0.8) * 3.3)::int],
    'say',     (array['A lot','Some','Very little','None'])[1 + floor(least(0.999, power(a, 0.5)) * 4)::int]),
  case when e < .1 then '{lead}'::text[] else '{}'::text[] end,
  now() - (a * interval '6 days'), now() - interval '7 days'
from r;
