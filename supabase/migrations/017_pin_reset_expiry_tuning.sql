-- Gate 27.4: PIN Reset Code Expiry Tuning
-- Shortens the admin-issued reset code lifetime from 15 minutes to 5 minutes.
-- Only the expiry interval changes; no other logic in admin_issue_pin_reset_code is touched.

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
  v_code_expires_at := now() + interval '5 minutes';

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
