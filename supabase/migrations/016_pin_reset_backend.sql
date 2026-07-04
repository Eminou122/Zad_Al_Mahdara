-- Gate 27.1: PIN Reset Backend
-- Implements RPC-only PIN reset support for custom PIN auth.
-- Additive-only. Does not expose full phone numbers, PIN hashes, or reset hashes.

alter table public.pin_reset_requests
  add column if not exists issued_by uuid null references public.profiles(id),
  add column if not exists cancelled_at timestamptz null,
  add column if not exists expired_at timestamptz null,
  add column if not exists attempt_count int not null default 0,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists pin_reset_requests_status_updated_at
  on public.pin_reset_requests (status, updated_at desc);

create index if not exists pin_reset_requests_profile_status
  on public.pin_reset_requests (profile_id, status);

alter table public.pin_reset_requests enable row level security;
revoke all on public.pin_reset_requests from anon, authenticated, public;

create or replace function public.request_pin_reset(
  p_phone_number text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
begin
  if coalesce(p_phone_number, '') !~ '^[0-9]{8}$' then
    return jsonb_build_object(
      'ok', true,
      'message', 'If this number exists, your request was sent.'
    );
  end if;

  select p.id into v_profile_id
  from profiles p
  where p.phone_number = p_phone_number
    and p.is_active = true
    and p.is_admin = false;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'message', 'If this number exists, your request was sent.'
    );
  end if;

  update pin_reset_requests r
  set status = 'expired',
      expired_at = now(),
      updated_at = now()
  where r.profile_id = v_profile_id
    and r.status = 'code_issued'
    and r.code_expires_at < now();

  begin
    insert into pin_reset_requests (profile_id, status)
    select v_profile_id, 'pending'
    where not exists (
      select 1
      from pin_reset_requests r
      where r.profile_id = v_profile_id
        and r.status in ('pending', 'code_issued')
    );
  exception
    when unique_violation then
      null;
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'If this number exists, your request was sent.'
  );
end;
$$;

create or replace function public.admin_list_pin_reset_requests(
  p_session_token text,
  p_status text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id uuid;
  v_result   jsonb;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  if p_status is not null
     and p_status not in ('pending', 'code_issued', 'used', 'expired', 'cancelled') then
    raise exception 'invalid status';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',              q.id,
      'profile_id',      q.profile_id,
      'display_name',    q.display_name,
      'phone_masked',    q.phone_masked,
      'status',          q.status,
      'created_at',      q.created_at,
      'issued_at',       q.issued_at,
      'code_expires_at', q.code_expires_at,
      'used_at',         q.used_at,
      'cancelled_at',    q.cancelled_at,
      'expired_at',      q.expired_at,
      'attempt_count',   q.attempt_count
    ) order by q.created_at desc
  ), '[]'::jsonb) into v_result
  from (
    select
      r.id,
      r.profile_id,
      p.display_name,
      p.phone_masked,
      r.status,
      r.created_at,
      r.issued_at,
      r.code_expires_at,
      r.used_at,
      r.cancelled_at,
      r.expired_at,
      r.attempt_count
    from pin_reset_requests r
    join profiles p on p.id = r.profile_id
    where p.is_admin = false
      and (p_status is null or r.status = p_status)
    order by r.created_at desc
    limit 200
  ) q;

  return v_result;
end;
$$;

create or replace function public.admin_issue_pin_reset_code(
  p_session_token text,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id        uuid;
  v_request_id      uuid;
  v_random_bytes    bytea;
  v_random_number   bigint;
  v_code            text;
  v_code_expires_at timestamptz;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  select r.id into v_request_id
  from pin_reset_requests r
  join profiles p on p.id = r.profile_id
  where r.id = p_request_id
    and r.status in ('pending', 'code_issued')
    and p.is_active = true
    and p.is_admin = false
  for update of r;

  if not found then
    raise exception 'pin reset request not found';
  end if;

  v_random_bytes := gen_random_bytes(4);
  v_random_number :=
    get_byte(v_random_bytes, 0)::bigint * 16777216 +
    get_byte(v_random_bytes, 1)::bigint * 65536 +
    get_byte(v_random_bytes, 2)::bigint * 256 +
    get_byte(v_random_bytes, 3)::bigint;
  v_code := lpad((v_random_number % 100000000)::text, 8, '0');
  v_code_expires_at := now() + interval '15 minutes';

  update pin_reset_requests
  set status = 'code_issued',
      code_hash = crypt(v_code, gen_salt('bf', 8)),
      code_expires_at = v_code_expires_at,
      issued_by = v_admin_id,
      issued_at = now(),
      attempt_count = 0,
      updated_at = now(),
      cancelled_at = null,
      expired_at = null
  where id = v_request_id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_request_id,
    'code', v_code,
    'code_expires_at', v_code_expires_at,
    'status', 'code_issued'
  );
end;
$$;

create or replace function public.complete_pin_reset(
  p_phone_number text,
  p_code text,
  p_new_pin text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_request record;
  v_attempt_count int;
begin
  if coalesce(p_phone_number, '') !~ '^[0-9]{8}$'
     or coalesce(p_code, '') !~ '^[0-9]{8}$'
     or coalesce(p_new_pin, '') !~ '^[0-9]{4}$' then
    return jsonb_build_object(
      'ok', false,
      'message', 'invalid or expired reset code'
    );
  end if;

  select p.id into v_profile_id
  from profiles p
  where p.phone_number = p_phone_number
    and p.is_active = true
    and p.is_admin = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'message', 'invalid or expired reset code'
    );
  end if;

  select
    r.id,
    r.code_hash,
    r.code_expires_at,
    r.attempt_count
  into v_request
  from pin_reset_requests r
  where r.profile_id = v_profile_id
    and r.status = 'code_issued'
  order by r.issued_at desc nulls last, r.created_at desc
  limit 1
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'message', 'invalid or expired reset code'
    );
  end if;

  if v_request.code_expires_at is null
     or v_request.code_expires_at < now()
     or v_request.attempt_count >= 5 then
    update pin_reset_requests
    set status = 'expired',
        expired_at = coalesce(expired_at, now()),
        updated_at = now()
    where id = v_request.id;

    return jsonb_build_object(
      'ok', false,
      'message', 'invalid or expired reset code'
    );
  end if;

  if v_request.code_hash is null
     or crypt(p_code, v_request.code_hash) <> v_request.code_hash then
    v_attempt_count := v_request.attempt_count + 1;

    update pin_reset_requests
    set attempt_count = v_attempt_count,
        status = case when v_attempt_count >= 5 then 'expired' else status end,
        expired_at = case when v_attempt_count >= 5 then now() else expired_at end,
        updated_at = now()
    where id = v_request.id;

    return jsonb_build_object(
      'ok', false,
      'message', 'invalid or expired reset code'
    );
  end if;

  update profiles
  set pin_hash = crypt(p_new_pin, gen_salt('bf', 8)),
      failed_login_count = 0,
      locked_until = null,
      updated_at = now()
  where id = v_profile_id;

  update pin_reset_requests
  set status = 'used',
      used_at = now(),
      updated_at = now()
  where id = v_request.id;

  update app_sessions
  set revoked_at = now()
  where profile_id = v_profile_id
    and revoked_at is null;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_cancel_pin_reset_request(
  p_session_token text,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id uuid;
  v_rows     int;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  update pin_reset_requests r
  set status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  from profiles p
  where r.id = p_request_id
    and p.id = r.profile_id
    and p.is_admin = false
    and r.status in ('pending', 'code_issued');

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'pin reset request not found';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.request_pin_reset(text) to anon;
grant execute on function public.admin_list_pin_reset_requests(text, text) to anon;
grant execute on function public.admin_issue_pin_reset_code(text, uuid) to anon;
grant execute on function public.complete_pin_reset(text, text, text) to anon;
grant execute on function public.admin_cancel_pin_reset_request(text, uuid) to anon;
