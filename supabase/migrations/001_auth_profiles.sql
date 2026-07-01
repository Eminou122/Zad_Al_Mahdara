-- Gate 3 Rebuild: Custom PIN Auth
-- No Supabase Auth. RPC-only access via pgcrypto PIN hashing + session tokens.
--
-- APPLY MANUALLY: Supabase Dashboard → SQL Editor → Run
-- Re-runnable on a fresh dev DB.
-- WARNING: includes DROP TABLE CASCADE — destroys existing data.
--          Only run this on a dev DB before any real users exist.

-- ─── Extensions ─────────────────────────────────────────────────────────────
create extension if not exists pgcrypto;

-- ─── Remove old Supabase Auth artifacts (Gate 2 cleanup) ────────────────────
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();

-- ─── Drop old tables (schema incompatible with Gate 2; safe on fresh DB) ─────
drop table if exists public.app_sessions cascade;
drop table if exists public.profiles cascade;

-- ─── profiles ───────────────────────────────────────────────────────────────
create table public.profiles (
  id                  uuid        primary key default gen_random_uuid(),
  display_name        text        not null,
  phone_number        text        not null unique,
  phone_masked        text        not null,
  pin_hash            text        not null,
  is_admin            boolean     not null default false,
  is_active           boolean     not null default true,
  failed_login_count  int         not null default 0,
  locked_until        timestamptz null,
  last_login_at       timestamptz null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint profiles_phone_8_digits
    check (phone_number ~ '^[0-9]{8}$'),
  constraint profiles_display_name_length
    check (length(trim(display_name)) between 1 and 80)
);

-- ─── app_sessions ────────────────────────────────────────────────────────────
create table public.app_sessions (
  id           uuid        primary key default gen_random_uuid(),
  profile_id   uuid        not null references public.profiles(id) on delete cascade,
  token_hash   text        not null unique,
  expires_at   timestamptz not null,
  revoked_at   timestamptz null,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz null
);

-- ─── RLS ────────────────────────────────────────────────────────────────────
alter table public.profiles     enable row level security;
alter table public.app_sessions enable row level security;

-- No anon/authenticated table policies — all access goes through SECURITY DEFINER RPCs.
revoke all on public.profiles     from anon, authenticated;
revoke all on public.app_sessions from anon, authenticated;

-- ─── RPC: register_student ──────────────────────────────────────────────────
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
    p_phone_number = '49413435'
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
      'is_admin',     p_phone_number = '49413435',
      'is_active',    true
    )
  );
end;
$$;

-- ─── RPC: login_student ─────────────────────────────────────────────────────
create or replace function public.login_student(
  p_phone_number text,
  p_pin          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile    profiles%rowtype;
  v_token_raw  text;
  v_token_hash text;
begin
  if p_phone_number !~ '^[0-9]{8}$' or p_pin !~ '^[0-9]{4}$' then
    raise exception 'invalid credentials';
  end if;

  select * into v_profile
  from profiles
  where phone_number = p_phone_number and is_active = true;

  if not found then
    raise exception 'invalid credentials';
  end if;

  if v_profile.locked_until is not null and v_profile.locked_until > now() then
    raise exception 'invalid credentials or account locked';
  end if;

  if crypt(p_pin, v_profile.pin_hash) <> v_profile.pin_hash then
    update profiles
    set
      failed_login_count = failed_login_count + 1,
      locked_until = case
        when failed_login_count + 1 >= 5 then now() + interval '5 minutes'
        else locked_until
      end,
      updated_at = now()
    where id = v_profile.id;
    raise exception 'invalid credentials';
  end if;

  update profiles
  set
    failed_login_count = 0,
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

-- ─── RPC: get_current_profile_by_session ────────────────────────────────────
create or replace function public.get_current_profile_by_session(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_token_hash text;
  v_session    app_sessions%rowtype;
  v_profile    profiles%rowtype;
begin
  v_token_hash := encode(digest(p_session_token, 'sha256'), 'hex');

  select * into v_session
  from app_sessions
  where token_hash = v_token_hash
    and revoked_at is null
    and expires_at > now();

  if not found then
    return null;
  end if;

  select * into v_profile
  from profiles
  where id = v_session.profile_id and is_active = true;

  if not found then
    return null;
  end if;

  update app_sessions
  set last_seen_at = now()
  where id = v_session.id;

  return jsonb_build_object(
    'id',           v_profile.id,
    'display_name', v_profile.display_name,
    'phone_masked', v_profile.phone_masked,
    'is_admin',     v_profile.is_admin,
    'is_active',    v_profile.is_active
  );
end;
$$;

-- ─── RPC: revoke_session ────────────────────────────────────────────────────
create or replace function public.revoke_session(
  p_session_token text
) returns void
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_token_hash text;
begin
  v_token_hash := encode(digest(p_session_token, 'sha256'), 'hex');
  update app_sessions
  set revoked_at = now()
  where token_hash = v_token_hash and revoked_at is null;
end;
$$;

-- ─── Grants ─────────────────────────────────────────────────────────────────
grant execute on function public.register_student(text, text, text)   to anon;
grant execute on function public.login_student(text, text)             to anon;
grant execute on function public.get_current_profile_by_session(text)  to anon;
grant execute on function public.revoke_session(text)                  to anon;
