-- Gate 46.1: Remove Hardcoded Admin Bootstrap
-- Apply manually: Supabase Dashboard → SQL Editor → Run
-- Additive-only. Does NOT modify any other RPC, table, RLS policy, or grant.
--
-- Problem (Gate 46.0 P1 finding): register_student (001_auth_profiles.sql)
-- hardcodes p_phone_number = '49413435' to auto-grant is_admin on
-- registration. If that account is ever deactivated and the number becomes
-- re-registrable, a new registrant with that exact phone number would
-- silently become admin. This migration removes that logic — new
-- registrations always start as is_admin = false — and, in the same
-- transaction, preserves admin on the existing account by profile data
-- (not registration logic) so the current admin loses no access.

-- ─── A. Redefine register_student without the hardcoded admin grant ─────────
create or replace function public.register_student(
  p_display_name text,
  p_phone_number text,
  p_pin          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id   uuid;
  v_token_raw    text;
  v_token_hash   text;
  v_phone_masked text;
begin
  if length(trim(p_display_name)) not between 1 and 80 then
    raise exception 'invalid display_name';
  end if;
  if p_phone_number !~ '^[0-9]{8}$' then
    raise exception 'phone_number must be exactly 8 digits';
  end if;
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'pin must be exactly 4 digits';
  end if;
  if exists(select 1 from profiles where phone_number = p_phone_number) then
    raise exception 'phone_number already registered';
  end if;

  v_phone_masked := substr(p_phone_number, 1, 2) || '****' || substr(p_phone_number, 7, 2);

  insert into profiles (display_name, phone_number, phone_masked, pin_hash, is_admin)
  values (
    trim(p_display_name),
    p_phone_number,
    v_phone_masked,
    crypt(p_pin, gen_salt('bf', 8)),
    false
  )
  returning id into v_profile_id;

  v_token_raw  := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token_raw, 'sha256'), 'hex');

  insert into app_sessions (profile_id, token_hash, expires_at)
  values (v_profile_id, v_token_hash, now() + interval '30 days');

  return jsonb_build_object(
    'session_token', v_token_raw,
    'profile', jsonb_build_object(
      'id',           v_profile_id,
      'display_name', trim(p_display_name),
      'phone_masked', v_phone_masked,
      'is_admin',     false,
      'is_active',    true
    )
  );
end;
$$;

-- Signature is unchanged (text, text, text) so CREATE OR REPLACE preserves
-- the existing grant, but re-declaring it explicitly matches project
-- convention and keeps this migration self-contained.
grant execute on function public.register_student(text, text, text) to anon;

-- ─── B. One-time data fix: preserve the existing admin account ──────────────
-- Not registration logic — a single idempotent UPDATE so the account that
-- previously relied on the hardcoded phone check keeps its admin access.
-- Safe to re-run: no-ops once is_admin is already true.
update public.profiles
set is_admin = true
where phone_number = '49413435'
  and is_admin = false;
