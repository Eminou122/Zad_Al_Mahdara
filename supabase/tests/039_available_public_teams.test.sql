begin;

create extension if not exists pgtap with schema extensions;
set local search_path = 'public', 'extensions';

select plan(59);

insert into public.profiles (
  display_name, phone_number, phone_masked, pin_hash, is_admin, is_active
) values
  ('039 caller', '00000391', '00****91', crypt('2468', gen_salt('bf', 8)), false, true),
  ('039 inactive caller', '00000392', '00****92', crypt('2468', gen_salt('bf', 8)), false, false),
  ('039 leader', '00000393', '00****93', crypt('2468', gen_salt('bf', 8)), false, true),
  ('039 inactive leader', '00000394', '00****94', crypt('2468', gen_salt('bf', 8)), false, false),
  ('039 registered member', '00000395', '00****95', crypt('2468', gen_salt('bf', 8)), false, true),
  ('039 inactive member', '00000396', '00****96', crypt('2468', gen_salt('bf', 8)), false, true),
  ('039 removed member', '00000397', '00****97', crypt('2468', gen_salt('bf', 8)), false, true);

insert into public.app_sessions (profile_id, token_hash, expires_at)
select id, encode(digest('039-active-token', 'sha256'), 'hex'), now() + interval '1 day'
from public.profiles where display_name = '039 caller';
insert into public.app_sessions (profile_id, token_hash, expires_at)
select id, encode(digest('039-inactive-token', 'sha256'), 'hex'), now() + interval '1 day'
from public.profiles where display_name = '039 inactive caller';

insert into public.external_students (display_name, phone_number, phone_masked, created_by)
select '039 external student', '00000398', '00****98', id
from public.profiles where display_name = '039 caller';

insert into public.teams (name, team_type, leader_id, is_public, status, is_active) values
  ('039 available', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true),
  ('039 inactive', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', false),
  ('039 private', 'other', (select id from public.profiles where display_name = '039 leader'), false, 'open', true),
  ('039 closed', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'closed', true),
  ('039 full', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'full', true),
  ('039 member team', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true),
  ('039 contact team', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true),
  ('039 inactive membership team', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true),
  ('039 removed membership team', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true),
  ('039 malformed leader', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true),
  ('039 inactive leader team', 'other', (select id from public.profiles where display_name = '039 inactive leader'), true, 'open', true),
  ('039 five hundred team', 'other', (select id from public.profiles where display_name = '039 leader'), true, 'open', true);

insert into public.team_members (team_id, profile_id, position, role, is_active)
select t.id, p.id, 1, 'leader', true
from public.teams t cross join public.profiles p
where t.name in (
  '039 available', '039 member team', '039 contact team',
  '039 inactive membership team', '039 removed membership team', '039 five hundred team'
) and p.display_name = '039 leader';

insert into public.team_members (team_id, profile_id, position, role, is_active)
select t.id, p.id, 1, 'leader', true
from public.teams t cross join public.profiles p
where t.name = '039 inactive leader team' and p.display_name = '039 inactive leader';

insert into public.team_members (team_id, profile_id, position, role, is_active) values
  ((select id from public.teams where name = '039 available'), (select id from public.profiles where display_name = '039 registered member'), 2, 'member', true),
  ((select id from public.teams where name = '039 available'), (select id from public.profiles where display_name = '039 inactive member'), 4, 'member', false),
  ((select id from public.teams where name = '039 member team'), (select id from public.profiles where display_name = '039 caller'), 2, 'member', true),
  ((select id from public.teams where name = '039 inactive membership team'), (select id from public.profiles where display_name = '039 caller'), 2, 'member', false),
  ((select id from public.teams where name = '039 removed membership team'), (select id from public.profiles where display_name = '039 caller'), 2, 'member', true);

insert into public.team_members (team_id, external_student_id, position, role, is_active)
select t.id, e.id, 3, 'member', true
from public.teams t cross join public.external_students e
where t.name = '039 available' and e.display_name = '039 external student';

insert into public.team_members (team_id, profile_id, position, role, is_active, removed_at)
select t.id, p.id, 5, 'member', true, now()
from public.teams t cross join public.profiles p
where t.name = '039 available' and p.display_name = '039 removed member';

update public.team_members
set removed_at = now()
where team_id = (select id from public.teams where name = '039 removed membership team')
  and profile_id = (select id from public.profiles where display_name = '039 caller');

create temporary table available_result on commit drop as
select public.get_available_public_teams('039-active-token') as response;

select ok(
  (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 available') from available_result),
  'active public open team is included'
);
select ok(not (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 inactive') from available_result), 'inactive team is excluded');
select ok(not (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 private') from available_result), 'private team is excluded');
select ok(not (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 closed') from available_result), 'closed team is excluded');
select ok(not (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 full') from available_result), 'manually full team is excluded');
select ok(
  (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 available' and (item->>'member_count')::integer = 3) from available_result),
  'active leader, registered member, and external student are counted while inactive and removed rows are excluded'
);
select ok(
  (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 member team' and (item->>'is_current_member')::boolean) from available_result),
  'active current member is marked true'
);
select ok(
  (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 contact team' and not (item->>'is_current_member')::boolean) from available_result),
  'non-member is marked false'
);
select ok(
  (select exists (select 1 from jsonb_array_elements(response->'items') item where item->>'name' = '039 malformed leader' and item->'leader_display_name' = 'null'::jsonb) from available_result),
  'team with no live leader remains listed with a null leader display name'
);
select ok(not (select bool_or(item ? 'leader_id' or item ? 'leader_profile_id') from available_result, jsonb_array_elements(response->'items') item), 'list response exposes no leader profile identifier');
select ok(not (select bool_or(item ? 'phone' or item ? 'leader_phone') from available_result, jsonb_array_elements(response->'items') item), 'list response exposes no phone field');
select ok(not (select bool_or(item ? 'capacity' or item ? 'max_members' or item ? 'remaining_places') from available_result, jsonb_array_elements(response->'items') item), 'list response exposes no count-based availability fields');
select ok(not exists (select 1 from available_result, jsonb_array_elements(response->'items') item, jsonb_object_keys(item) key where key not in ('team_id', 'name', 'team_type', 'note', 'leader_display_name', 'member_count', 'is_current_member')), 'list response contains only approved item fields');
select is(
  (select array_agg(item->>'name') from available_result, jsonb_array_elements(response->'items') item),
  (select array_agg(name order by name, id) from public.teams where is_active and is_public and status = 'open'),
  'list response has deterministic name then id ordering'
);
select throws_like($$select public.get_available_public_teams('bad-token')$$, 'invalid session', 'invalid list session is rejected');
select throws_like($$select public.get_available_public_teams('039-inactive-token')$$, 'invalid session', 'inactive caller is rejected from list');
select ok(has_function_privilege('anon', 'public.get_available_public_teams(text)', 'EXECUTE'), 'anon can execute list RPC');
select ok(not has_function_privilege('authenticated', 'public.get_available_public_teams(text)', 'EXECUTE'), 'authenticated cannot execute list RPC');
select is((select count(*) from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl where p.oid = 'public.get_available_public_teams(text)'::regprocedure and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'), 0::bigint, 'PUBLIC cannot execute list RPC');
select ok((select prosecdef from pg_proc where oid = 'public.get_available_public_teams(text)'::regprocedure), 'list RPC is security definer');
select ok((select 'search_path=public, extensions' = any(proconfig) from pg_proc where oid = 'public.get_available_public_teams(text)'::regprocedure), 'list RPC has fixed search path');
select ok(position('auth.uid' in (select pg_get_functiondef('public.get_available_public_teams(text)'::regprocedure))) = 0, 'list RPC does not depend on auth.uid');

create temp table contact_result(response jsonb);
insert into contact_result select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 contact team'), 'Please contact me');
select is((select response->>'ok' from contact_result),'true','valid non-member contact succeeds');
select ok((select (response->>'conversation_id')::uuid is not null from contact_result),'contact returns a conversation ID');
select is((select count(*) from public.team_conversations where id=(select (response->>'conversation_id')::uuid from contact_result)),1::bigint,'contact creates one conversation');
select is((select body from public.team_messages where conversation_id=(select (response->>'conversation_id')::uuid from contact_result)),'Please contact me','first contact message is stored');
select ok((select member_profile_id=(select id from profiles where display_name='039 caller') and join_leader_profile_id=(select id from profiles where display_name='039 leader') from team_conversations where id=(select (response->>'conversation_id')::uuid from contact_result)),'conversation binds applicant and leader');
select is((select action_payload->>'conversation_id' from public.notifications where type='available_team_contact' and team_id=(select id from teams where name='039 contact team') limit 1),(select response->>'conversation_id' from contact_result),'notification references the exact conversation');
select is((public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 contact team'), 'Please contact me')->>'conversation_id'),(select response->>'conversation_id' from contact_result),'repeated contact reuses the same conversation');
select is((select count(*) from public.team_conversations where team_id=(select id from teams where name='039 contact team') and member_profile_id=(select id from profiles where display_name='039 caller')),1::bigint,'repeated contact creates no duplicate conversation');
select is((select count(*) from public.notifications where type='available_team_contact' and team_id=(select id from teams where name='039 contact team')),2::bigint,'each contact message notifies the leader');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 member team'), 'hello')$$, 'team unavailable for contact', 'active existing member cannot contact leader');
select is((public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 inactive membership team'), 'hello')->>'ok'),'true','inactive membership does not block contact');
select is((public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 removed membership team'), 'hello')->>'ok'),'true','removed membership does not block contact');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 private'), 'hello')$$, 'team unavailable for contact', 'private team is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 inactive'), 'hello')$$, 'team unavailable for contact', 'inactive team is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 closed'), 'hello')$$, 'team unavailable for contact', 'closed team is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 full'), 'hello')$$, 'team unavailable for contact', 'full team is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', gen_random_uuid(), 'hello')$$, 'team unavailable for contact', 'missing team is rejected generically');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 malformed leader'), 'hello')$$, 'team unavailable for contact', 'missing live leader is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 inactive leader team'), 'hello')$$, 'team unavailable for contact', 'inactive leader is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 contact team'), '')$$, 'invalid contact message', 'blank body is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 contact team'), '   ')$$, 'invalid contact message', 'whitespace-only body is rejected');
select throws_like($$select public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 contact team'), repeat('x', 501))$$, 'invalid contact message', 'body longer than 500 is rejected');
select is((public.contact_available_team_leader('039-active-token', (select id from public.teams where name = '039 five hundred team'), repeat('x', 500))->>'ok'),'true','exactly 500 characters is accepted');
select throws_like($$select public.contact_available_team_leader('bad-token', (select id from public.teams where name = '039 contact team'), 'hello')$$, 'invalid session', 'invalid contact session is rejected');
select throws_like($$select public.contact_available_team_leader('039-inactive-token', (select id from public.teams where name = '039 contact team'), 'hello')$$, 'invalid session', 'inactive caller cannot contact');
select ok((select count(*) from public.team_conversations where team_id in (select id from public.teams where name like '039%')) >= 4,'prospect contacts create retained conversations');
select ok((select count(*) from public.team_messages) >= 5,'prospect contacts create retained messages');
select is((select count(*) from public.team_members where team_id = (select id from public.teams where name = '039 contact team')), 1::bigint, 'prospect contact creates no membership');
select ok((select length(body) <= 500 from public.notifications where type = 'available_team_contact' and team_id = (select id from public.teams where name = '039 five hundred team')),'notification body remains bounded');
select is((select team_id from public.notifications where type = 'available_team_contact' and team_id = (select id from public.teams where name = '039 contact team') limit 1), (select id from public.teams where name = '039 contact team'), 'notification references the target team');
select ok(not (select coalesce(string_agg(title || body, ''), '') like '%00000391%' from public.notifications where type = 'available_team_contact'), 'contact notification contains no caller phone');
select ok(has_function_privilege('anon', 'public.contact_available_team_leader(text,uuid,text)', 'EXECUTE'), 'anon can execute contact RPC');
select ok(not has_function_privilege('authenticated', 'public.contact_available_team_leader(text,uuid,text)', 'EXECUTE'), 'authenticated cannot execute contact RPC');
select is((select count(*) from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl where p.oid = 'public.contact_available_team_leader(text,uuid,text)'::regprocedure and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'), 0::bigint, 'PUBLIC cannot execute contact RPC');
select ok((select prosecdef from pg_proc where oid = 'public.contact_available_team_leader(text,uuid,text)'::regprocedure), 'contact RPC is security definer');
select ok((select 'search_path=public, extensions' = any(proconfig) from pg_proc where oid = 'public.contact_available_team_leader(text,uuid,text)'::regprocedure), 'contact RPC has fixed search path');
select ok(position('auth.uid' in (select pg_get_functiondef('public.contact_available_team_leader(text,uuid,text)'::regprocedure))) = 0, 'contact RPC does not depend on auth.uid');

select * from finish();
rollback;
