-- Gate 28.1: Account Settings Backend
-- Logged-in-only RPCs: change display_name, change pin_hash via current PIN.
-- Additive-only. Does not create tables, does not touch RLS/table grants,
-- does not expose pin_hash or phone_number in any return payload.

-- ─── RPC: update_my_profile_name ────────────────────────────────────────────
create or replace function public.update_my_profile_name(
  p_session_token text,
  p_display_name  text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_profile    profiles%rowtype;
  v_name       text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  v_name := trim(p_display_name);
  if length(v_name) not between 1 and 80 then
    raise exception 'invalid display_name';
  end if;

  update profiles
  set display_name = v_name,
      updated_at   = now()
  where id = v_profile_id
  returning * into v_profile;

  return jsonb_build_object(
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

-- ─── RPC: change_my_pin ──────────────────────────────────────────────────────
create or replace function public.change_my_pin(
  p_session_token text,
  p_current_pin   text,
  p_new_pin       text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_profile    profiles%rowtype;
  v_token_hash text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_profile from profiles where id = v_profile_id;

  -- current_profile_id_from_session does not check locked_until, so a still-valid
  -- session on a locked account must be blocked here explicitly.
  if v_profile.locked_until is not null and v_profile.locked_until > now() then
    return jsonb_build_object('ok', false, 'message', 'account temporarily locked');
  end if;

  if p_current_pin !~ '^[0-9]{4}$' or p_new_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok', false, 'message', 'pin must be exactly 4 digits');
  end if;

  if crypt(p_current_pin, v_profile.pin_hash) <> v_profile.pin_hash then
    -- Must return (not raise) here: an uncaught exception rolls back this
    -- entire statement, including the failed_login_count update below,
    -- which would silently defeat the lockout counter.
    update profiles
    set
      failed_login_count = failed_login_count + 1,
      locked_until = case
        when failed_login_count + 1 >= 5 then now() + interval '5 minutes'
        else locked_until
      end,
      updated_at = now()
    where id = v_profile.id;
    return jsonb_build_object('ok', false, 'message', 'incorrect current pin');
  end if;

  v_token_hash := encode(digest(p_session_token, 'sha256'), 'hex');

  update profiles
  set pin_hash            = crypt(p_new_pin, gen_salt('bf', 8)),
      failed_login_count  = 0,
      locked_until        = null,
      updated_at          = now()
  where id = v_profile.id;

  -- Keep the calling session alive; revoke every other session for this profile.
  update app_sessions
  set revoked_at = now()
  where profile_id = v_profile.id
    and revoked_at is null
    and token_hash <> v_token_hash;

  return jsonb_build_object('ok', true);
end;
$$;

-- ─── Grants ──────────────────────────────────────────────────────────────────
revoke all on function public.update_my_profile_name(text, text)       from public;
revoke all on function public.change_my_pin(text, text, text)          from public;

grant execute on function public.update_my_profile_name(text, text)    to anon;
grant execute on function public.change_my_pin(text, text, text)       to anon;
