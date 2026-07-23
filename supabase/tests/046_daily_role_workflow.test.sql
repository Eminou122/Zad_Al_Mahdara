begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pgtap;
select plan(25);

insert into profiles(display_name,phone_number,phone_masked,pin_hash,is_admin,is_active) values
 ('046 leader','00000461','00****61',crypt('2468',gen_salt('bf',8)),false,true),
 ('046 account','00000462','00****62',crypt('2468',gen_salt('bf',8)),false,true),
 ('046 intruder','00000463','00****63',crypt('2468',gen_salt('bf',8)),false,true);
insert into app_sessions(profile_id,token_hash,expires_at)
 select id,encode(digest('046-' || split_part(display_name,' ',2),'sha256'),'hex'),now()+interval '1 day'
 from profiles where display_name in ('046 leader','046 account','046 intruder');

insert into teams(name,team_type,leader_id,is_public,status)
 select '046 breakfast', 'breakfast', id, true, 'open' from profiles where display_name='046 leader';
insert into team_members(team_id,profile_id,position,role)
 select t.id,p.id,1,'leader' from teams t join profiles p on p.display_name='046 leader' where t.name='046 breakfast';
insert into team_members(team_id,profile_id,position,role)
 select t.id,p.id,2,'member' from teams t join profiles p on p.display_name='046 account' where t.name='046 breakfast';
insert into external_students(display_name,phone_number,phone_masked,created_by)
 select '046 manual','00000464','00****64',id from profiles where display_name='046 leader';
insert into team_members(team_id,external_student_id,position,role)
 select t.id,e.id,3,'member' from teams t join external_students e on e.display_name='046 manual' where t.name='046 breakfast';

-- No purchase-list rows exist: starting must still create today's role.
select is((public.start_daily_role('046-leader',(select id from teams where name='046 breakfast'))->'today_turn'->>'display_name'),'046 leader','starts without a purchase list and uses saved position order');
select is((select meal_type from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date),'breakfast','meal type snapshots team breakfast type');
select is((select count(*) from team_shopping_items where team_id=(select id from teams where name='046 breakfast')),0::bigint,'no purchase list was required');
select throws_like($$select public.start_daily_role('046-intruder',(select id from teams where name='046 breakfast'))$$,'القائد فقط يمكنه بدء الدور','unauthorized start is rejected');
select is((select count(*) from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date),1::bigint,'start retry is idempotent');
select is((select count(*) from notifications where type='daily_role_assigned'),1::bigint,'assigned account member receives daily-role notification');

-- The leader is today\'s saved first position, so only they may confirm it.
select throws_like($$select public.member_complete_daily_role('046-account',(select id from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date))$$,'%العضو المكلف اليوم فقط%','wrong account member cannot complete');
select public.member_complete_daily_role('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date));
select is((select completion_source from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date),'account_member','assigned account member completion is recorded');
select is((select count(*) from notifications where type='daily_role_member_completed'),1::bigint,'leader receives completion notification');
select public.leader_finalize_daily_role('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date));
select is((select status from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date),'completed','leader finalizes exactly once');
select throws_like($$select public.leader_finalize_daily_role('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date))$$,'turn is not pending','duplicate finalization is blocked');
select ok((select finalized_at is not null and finalized_by=(select id from profiles where display_name='046 leader') from team_turns where team_id=(select id from teams where name='046 breakfast') and turn_date=current_date),'history keeps finalization metadata');

-- Isolated manual role exercises binding, one-time use, expiry and fallback.
insert into teams(name,team_type,leader_id,is_public,status,current_position)
 select '046 manual team','dinner',id,true,'open',2 from profiles where display_name='046 leader';
insert into team_members(team_id,profile_id,position,role)
 select t.id,p.id,1,'leader' from teams t join profiles p on p.display_name='046 leader' where t.name='046 manual team';
insert into team_members(team_id,external_student_id,position,role)
 select t.id,e.id,2,'member' from teams t join external_students e on e.display_name='046 manual' where t.name='046 manual team';
select public.start_daily_role('046-leader',(select id from teams where name='046 manual team'));
select is((public.get_daily_role_whatsapp_link('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date))->>'team_type'),'dinner','manual WhatsApp link uses actual dinner type');
select throws_like($$select public.leader_fallback_complete_daily_role('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date))$$,'%20 دقيقة%','fallback is blocked before 20 minutes');
select is((public.get_daily_role_public_confirmation((select encode(gen_random_bytes(32),'hex')))->>'status'),'invalid','unknown manual token reveals no team data');
select is((public.complete_daily_role_public((select token from (select encode(gen_random_bytes(32),'hex') token) x)) ->> 'status'),'invalid','wrong manual token cannot complete');
select is((public.get_daily_role_public_confirmation((select 'x')) ->> 'status'),'invalid','invalid token stays invalid');
-- Read the generated plaintext only inside this transaction to call its public RPC; DB stores only its hash.
select ok((select token_hash <> '' and token_hash !~ '^[0-9]{8}$' from team_role_confirmation_tokens where turn_id=(select id from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date)),'manual token is stored hashed');
update team_turns set started_at=now()-interval '21 minutes' where team_id=(select id from teams where name='046 manual team') and turn_date=current_date;
select public.leader_fallback_complete_daily_role('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date));
select is((select completion_source from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date),'leader_fallback','fallback preserves its source');
select public.leader_finalize_daily_role('046-leader',(select id from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date));
select is((select status from team_turns where team_id=(select id from teams where name='046 manual team') and turn_date=current_date),'completed','fallback role is retained and finalizable');

select ok(has_function_privilege('anon','public.start_daily_role(text,uuid)','EXECUTE'),'anon executes custom-session start RPC');
select ok(not has_function_privilege('authenticated','public.start_daily_role(text,uuid)','EXECUTE'),'authenticated execute revoked');
select ok((select prosecdef from pg_proc where oid='public.complete_daily_role_public(text)'::regprocedure),'public completion RPC is security definer');
select ok((select 'search_path=public, extensions'=any(proconfig) from pg_proc where oid='public.complete_daily_role_public(text)'::regprocedure),'public completion RPC has fixed search path');
select ok(position('auth.uid' in (select pg_get_functiondef('public.complete_daily_role_public(text)'::regprocedure)))=0,'public completion uses no auth.uid');

select * from finish(); rollback;
