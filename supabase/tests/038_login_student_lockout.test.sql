begin;

create extension if not exists pgtap with schema extensions;
set local search_path = 'public', 'extensions';

select plan(30);

insert into public.profiles (
  display_name,
  phone_number,
  phone_masked,
  pin_hash,
  is_admin,
  is_active
) values
  (
    'AUTH-F2 disposable',
    '00000038',
    '00****38',
    crypt('2468', gen_salt('bf', 8)),
    false,
    true
  ),
  (
    'AUTH-F2 inactive disposable',
    '00000138',
    '00****38',
    crypt('2468', gen_salt('bf', 8)),
    false,
    false
  );

select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'first wrong PIN returns the generic failure'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  1,
  'first wrong PIN persists count one'
);

select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'second wrong PIN remains generic'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  2,
  'second wrong PIN persists count two'
);
select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'third wrong PIN remains generic'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  3,
  'third wrong PIN persists count three'
);
select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'fourth wrong PIN remains generic'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  4,
  'fourth wrong PIN persists count four'
);
select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'fifth wrong PIN remains generic'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  5,
  'fifth wrong PIN persists count five'
);
select ok(
  (select locked_until > now() from public.profiles where phone_number = '00000038'),
  'fifth wrong PIN sets a future lock'
);

select is(
  public.login_student('00000038', '2468'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'correct PIN during lock returns the generic failure'
);
select is(
  (select count(*) from public.app_sessions s
   join public.profiles p on p.id = s.profile_id
   where p.phone_number = '00000038'),
  0::bigint,
  'active lock creates no session'
);

select is(
  public.login_student('00000238', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'unknown phone returns the generic failure'
);
select is(
  public.login_student('00000138', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'inactive profile returns the generic failure'
);
select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'locked and wrong-PIN results are identical'
);
select is(
  public.login_student('bad', 'x'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'malformed input returns the generic failure'
);

update public.profiles
set failed_login_count = 5,
    locked_until = now() - interval '1 second'
where phone_number = '00000038';

select is(
  public.login_student('00000038', '1357'),
  jsonb_build_object('ok', false, 'error', 'INVALID_CREDENTIALS'),
  'wrong PIN after expiry remains generic'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  1,
  'wrong PIN after expiry starts a new failure window'
);
select ok(
  (select locked_until is null from public.profiles where phone_number = '00000038'),
  'first failure in the new window is not locked'
);

update public.profiles
set failed_login_count = 5,
    locked_until = now() - interval '1 second',
    last_login_at = null
where phone_number = '00000038';

create temporary table auth_f2_login_result(result jsonb) on commit drop;
insert into auth_f2_login_result
select public.login_student('00000038', '2468');

select ok(
  (select result ? 'session_token' from auth_f2_login_result),
  'correct PIN after expiry succeeds'
);
select is(
  (select failed_login_count from public.profiles where phone_number = '00000038'),
  0,
  'successful login resets the failure count'
);
select ok(
  (select locked_until is null from public.profiles where phone_number = '00000038'),
  'successful login clears the lock'
);
select ok(
  (select last_login_at is not null from public.profiles where phone_number = '00000038'),
  'successful login sets last_login_at'
);
select is(
  (select count(*)
   from public.app_sessions s, auth_f2_login_result r
   where s.token_hash = r.result->>'session_token'),
  0::bigint,
  'raw session token is not stored'
);
select is(
  (select count(*)
   from public.app_sessions s, auth_f2_login_result r
   where s.token_hash = encode(digest(r.result->>'session_token', 'sha256'), 'hex')),
  1::bigint,
  'stored session token is the SHA-256 hash'
);
select ok(
  (select s.expires_at between now() + interval '29 days 23 hours'
                           and now() + interval '30 days 1 hour'
   from public.app_sessions s
   join public.profiles p on p.id = s.profile_id
   where p.phone_number = '00000038'),
  'session expiry is approximately 30 days'
);

select is(
  (select count(*)
   from pg_proc p,
        lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
   where p.oid = 'public.login_student(text,text)'::regprocedure
     and acl.grantee = 0
     and acl.privilege_type = 'EXECUTE'),
  0::bigint,
  'PUBLIC cannot execute login_student'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.login_student(text,text)',
    'EXECUTE'
  ),
  'authenticated cannot execute login_student'
);
select ok(
  has_function_privilege('anon', 'public.login_student(text,text)', 'EXECUTE'),
  'anon can execute login_student'
);

select * from finish();
rollback;
