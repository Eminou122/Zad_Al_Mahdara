begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pgtap;
select plan(15);

insert into profiles(display_name,phone_number,phone_masked,pin_hash,is_admin,is_active) values
 ('045 owner','00000451','00****51',crypt('2468',gen_salt('bf',8)),false,true),
 ('045 member a','00000452','00****52',crypt('2468',gen_salt('bf',8)),false,true),
 ('045 member b','00000453','00****53',crypt('2468',gen_salt('bf',8)),false,true),
 ('045 other','00000454','00****54',crypt('2468',gen_salt('bf',8)),false,true),
 ('045 newcomer','00000455','00****55',crypt('2468',gen_salt('bf',8)),false,true);

insert into app_sessions(profile_id,token_hash,expires_at) select id,encode(digest('045-owner','sha256'),'hex'),now()+interval '1 day' from profiles where display_name='045 owner';
insert into app_sessions(profile_id,token_hash,expires_at) select id,encode(digest('045-other','sha256'),'hex'),now()+interval '1 day' from profiles where display_name='045 other';

insert into teams(name,team_type,leader_id,is_public,status) select '045 team','other',id,true,'open' from profiles where display_name='045 owner';

insert into team_members(team_id,profile_id,position,role) select t.id,p.id,1,'leader' from teams t join profiles p on p.display_name='045 owner' where t.name='045 team';
insert into team_members(team_id,profile_id,position,role) select t.id,p.id,2,'member' from teams t join profiles p on p.display_name='045 member a' where t.name='045 team';
insert into team_members(team_id,profile_id,position,role) select t.id,p.id,3,'member' from teams t join profiles p on p.display_name='045 member b' where t.name='045 team';

-- Reorder to [member b, owner, member a].
select public.reorder_team_members(
  '045-owner',
  (select id from teams where name='045 team'),
  array[
    (select id from team_members where team_id=(select id from teams where name='045 team') and profile_id=(select id from profiles where display_name='045 member b')),
    (select id from team_members where team_id=(select id from teams where name='045 team') and profile_id=(select id from profiles where display_name='045 owner')),
    (select id from team_members where team_id=(select id from teams where name='045 team') and profile_id=(select id from profiles where display_name='045 member a'))
  ]
);

select is(
  (select array_agg(p.display_name order by tm.position) from team_members tm join profiles p on p.id=tm.profile_id
    where tm.team_id=(select id from teams where name='045 team') and tm.is_active and tm.removed_at is null),
  array['045 member b','045 owner','045 member a'],
  'reorder persists the new stored position order'
);

select is(
  (select jsonb_agg(m->>'display_name' order by (m->>'position')::int) from
     jsonb_array_elements(public.get_team_detail('045-owner',(select id from teams where name='045 team'))->'members') m),
  '["045 member b","045 owner","045 member a"]'::jsonb,
  'get_team_detail reflects the persisted reorder'
);

select throws_like(
  $$select public.reorder_team_members('045-other',(select id from teams where name='045 team'),
     array[(select id from team_members where team_id=(select id from teams where name='045 team') and profile_id=(select id from profiles where display_name='045 owner'))])$$,
  'only team leader can reorder members',
  'non-leader cannot reorder team members'
);

select is(
  (select array_agg(p.display_name order by tm.position) from team_members tm join profiles p on p.id=tm.profile_id
    where tm.team_id=(select id from teams where name='045 team') and tm.is_active and tm.removed_at is null),
  array['045 member b','045 owner','045 member a'],
  'rejected reorder attempt leaves stored order unchanged'
);

-- New member appends after the current max position (3).
select public.add_team_member('045-owner',(select id from teams where name='045 team'),
  (select id from profiles where display_name='045 newcomer'));

select is(
  (select position from team_members where team_id=(select id from teams where name='045 team')
    and profile_id=(select id from profiles where display_name='045 newcomer')),
  4,
  'newly added member appends at the next free position'
);

-- Remove a middle, non-leader member ("045 member a", position 3) and confirm
-- the displayed list compacts even though the raw position column is not
-- rewritten (matches the client, which renders by list index, not by the
-- stored position value).
select public.remove_team_member('045-owner',
  (select id from team_members where team_id=(select id from teams where name='045 team')
    and profile_id=(select id from profiles where display_name='045 member a')),
  'compaction test');

select is(
  (select count(*) from team_members where team_id=(select id from teams where name='045 team')
    and is_active and removed_at is null),
  3::bigint,
  'removed member no longer counts as active'
);

select is(
  (select position from team_members where team_id=(select id from teams where name='045 team')
    and profile_id=(select id from profiles where display_name='045 newcomer')),
  4,
  'surviving member keeps its original raw position; the gap is not rewritten'
);

select is(
  (select jsonb_array_length(public.get_team_detail('045-owner',(select id from teams where name='045 team'))->'members')),
  3,
  'displayed member list has no gap-shaped hole after removal'
);

select is(
  (select jsonb_agg(m->>'display_name' order by (m->>'position')::int) from
     jsonb_array_elements(public.get_team_detail('045-owner',(select id from teams where name='045 team'))->'members') m),
  '["045 member b","045 owner","045 newcomer"]'::jsonb,
  'displayed member list compacts around the removed member'
);

select ok(has_function_privilege('anon','public.reorder_team_members(text,uuid,uuid[])','EXECUTE'),'anon executes reorder RPC');
select ok(not has_function_privilege('authenticated','public.reorder_team_members(text,uuid,uuid[])','EXECUTE'),'authenticated cannot execute reorder RPC');
select ok((select prosecdef from pg_proc where oid='public.reorder_team_members(text,uuid,uuid[])'::regprocedure),'reorder RPC is security definer');
select ok((select 'search_path=public, extensions'=any(proconfig) from pg_proc where oid='public.reorder_team_members(text,uuid,uuid[])'::regprocedure),'reorder RPC has fixed search path');
select ok(has_function_privilege('anon','public.create_team_with_members(text,text,text,boolean,text,text,jsonb)','EXECUTE'),'anon executes create_team_with_members RPC');
select ok(not has_function_privilege('authenticated','public.create_team_with_members(text,text,text,boolean,text,text,jsonb)','EXECUTE'),'authenticated cannot execute create_team_with_members RPC');

select * from finish(); rollback;
