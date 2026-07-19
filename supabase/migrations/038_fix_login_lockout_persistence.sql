-- Gate AUTH-F2: persist login failures without weakening generic errors.

create or replace function public.login_student(
  p_phone_number text,
  p_pin          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile      profiles%rowtype;
  v_pin_valid    boolean;
  v_failed_count int;
  v_token_raw    text;
  v_token_hash   text;
  -- Precomputed dummy bcrypt target. It avoids an obvious fast path for
  -- unknown accounts without looking up a real fallback identity.
  v_dummy_hash constant text := '$2a$08$engwxH0HSF5JQ7NYXnYXc.CoANat2VMLRR71aiRn8hvdSbvS3YXPy';
  v_failure constant jsonb := jsonb_build_object(
    'ok', false,
    'error', 'INVALID_CREDENTIALS'
  );
begin
  if p_phone_number !~ '^[0-9]{8}$' or p_pin !~ '^[0-9]{4}$' then
    return v_failure;
  end if;

  select * into v_profile
  from profiles
  where phone_number = p_phone_number
  for update;

  if not found then
    perform crypt(p_pin, v_dummy_hash);
    return v_failure;
  end if;

  -- Verify before the active/lock checks to reduce obvious response-time
  -- differences. This is timing mitigation, not a constant-time guarantee.
  v_pin_valid := crypt(p_pin, v_profile.pin_hash) = v_profile.pin_hash;

  if not v_profile.is_active then
    return v_failure;
  end if;

  if v_profile.locked_until is not null and v_profile.locked_until > now() then
    return v_failure;
  end if;

  if not v_pin_valid then
    -- Any non-null lock reaching here has expired, so this is attempt one of a
    -- new failure window. Otherwise continue the current window.
    v_failed_count := case
      when v_profile.locked_until is not null then 1
      else v_profile.failed_login_count + 1
    end;

    update profiles
    set failed_login_count = v_failed_count,
        locked_until = case
          when v_failed_count >= 5 then now() + interval '5 minutes'
          else null
        end,
        updated_at = now()
    where id = v_profile.id;

    return v_failure;
  end if;

  update profiles
  set failed_login_count = 0,
      locked_until       = null,
      last_login_at      = now(),
      updated_at         = now()
  where id = v_profile.id;

  v_token_raw  := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token_raw, 'sha256'), 'hex');

  insert into app_sessions (profile_id, token_hash, expires_at)
  values (v_profile.id, v_token_hash, now() + interval '30 days');

  return jsonb_build_object(
    'session_token', v_token_raw,
    'profile', jsonb_build_object(
      'id',           v_profile.id,
      'display_name', v_profile.display_name,
      'phone_masked', v_profile.phone_masked,
      'is_admin',     v_profile.is_admin,
      'is_active',    v_profile.is_active
    )
  );
end;
$$;

revoke execute on function public.login_student(text, text) from public;
revoke execute on function public.login_student(text, text) from authenticated;
grant execute on function public.login_student(text, text) to anon;
