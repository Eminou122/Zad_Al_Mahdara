-- Gate 25: Admin Backend Foundation
-- Adds an internal admin-session helper, the pin_reset_requests foundation
-- table, and read/support admin RPCs. Does not implement PIN reset code
-- generation/redemption, notifications, invitations, or team shopping list.
--
-- APPLY MANUALLY: Supabase Dashboard → SQL Editor → Run
-- Additive-only. Does NOT modify 001–014 or any existing table/function
-- signature. Safe to re-apply (create or replace / if not exists).

-- ─── A. Internal admin helper ────────────────────────────────────────────────
-- Mirrors current_profile_id_from_session's hash/expiry/revoked/is_active
-- checks, and additionally requires is_admin = true. Internal only — never
-- granted to anon/authenticated, same treatment as current_profile_id_from_session.

create or replace function public.admin_profile_id_from_session(
  p_session_token text
) returns uuid
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
    raise exception 'invalid session';
  end if;

  select * into v_profile
  from profiles
  where id = v_session.profile_id and is_active = true;

  if not found then
    raise exception 'invalid session';
  end if;

  if not v_profile.is_admin then
    raise exception 'admin only';
  end if;

  update app_sessions set last_seen_at = now() where id = v_session.id;

  return v_profile.id;
end;
$$;

revoke execute on function public.admin_profile_id_from_session(text) from public;
revoke execute on function public.admin_profile_id_from_session(text) from anon;
revoke execute on function public.admin_profile_id_from_session(text) from authenticated;

-- ─── B. PIN reset foundation table (no code generation/redemption yet) ───────

create table if not exists public.pin_reset_requests (
  id              uuid        primary key default gen_random_uuid(),
  profile_id      uuid        not null references public.profiles(id) on delete cascade,
  status          text        not null default 'pending'
                    check (status in ('pending','code_issued','used','expired','cancelled')),
  code_hash       text        null,
  code_expires_at timestamptz null,
  created_at      timestamptz not null default now(),
  issued_at       timestamptz null,
  used_at         timestamptz null
);

create unique index if not exists pin_reset_requests_one_active
  on public.pin_reset_requests (profile_id)
  where status in ('pending','code_issued');

create index if not exists pin_reset_requests_status_created_at
  on public.pin_reset_requests (status, created_at desc);

alter table public.pin_reset_requests enable row level security;

revoke all on public.pin_reset_requests from anon, authenticated, public;

-- ─── C. Admin RPCs ────────────────────────────────────────────────────────────

create or replace function public.get_admin_dashboard(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id uuid;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  return jsonb_build_object(
    'active_users_count',
      (select count(*) from profiles where is_active = true),
    'inactive_users_count',
      (select count(*) from profiles where is_active = false),
    'public_teams_count',
      (select count(*) from teams where is_public = true and is_active = true),
    'pending_pin_reset_requests_count',
      (select count(*) from pin_reset_requests where status = 'pending')
  );
end;
$$;

create or replace function public.admin_list_users(
  p_session_token text,
  p_query         text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id uuid;
  v_query    text;
  v_result   jsonb;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  v_query := nullif(trim(coalesce(p_query, '')), '');

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',            p.id,
      'display_name',  p.display_name,
      'phone_masked',  p.phone_masked,
      'is_active',     p.is_active,
      'is_admin',      p.is_admin,
      'created_at',    p.created_at,
      'last_login_at', p.last_login_at
    ) order by p.created_at desc
  ), '[]'::jsonb) into v_result
  from (
    select id, display_name, phone_masked, is_active, is_admin, created_at, last_login_at
    from profiles
    where v_query is null
       or display_name ilike '%' || v_query || '%'
       or phone_masked  ilike '%' || v_query || '%'
    order by created_at desc
    limit 200
  ) p;

  return v_result;
end;
$$;

create or replace function public.admin_get_user_detail(
  p_session_token text,
  p_profile_id    uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id uuid;
  v_profile  profiles%rowtype;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  select * into v_profile from profiles where id = p_profile_id;
  if not found then
    raise exception 'user not found';
  end if;

  return jsonb_build_object(
    'id',                 v_profile.id,
    'display_name',       v_profile.display_name,
    'phone_masked',       v_profile.phone_masked,
    'is_active',          v_profile.is_active,
    'is_admin',           v_profile.is_admin,
    'created_at',         v_profile.created_at,
    'last_login_at',      v_profile.last_login_at,
    'failed_login_count', v_profile.failed_login_count,
    'locked_until',       v_profile.locked_until
  );
end;
$$;

create or replace function public.admin_deactivate_user(
  p_session_token text,
  p_profile_id    uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_admin_id uuid;
  v_target   profiles%rowtype;
begin
  v_admin_id := admin_profile_id_from_session(p_session_token);

  if p_profile_id = v_admin_id then
    raise exception 'cannot act on own account';
  end if;

  select * into v_target from profiles where id = p_profile_id;
  if not found then
    raise exception 'user not found';
  end if;

  if v_target.is_admin then
    raise exception 'cannot deactivate an admin account';
  end if;

  update profiles
  set is_active  = false,
      updated_at = now()
  where id = p_profile_id;

  return jsonb_build_object('id', p_profile_id, 'is_active', false);
end;
$$;

create or replace function public.admin_reactivate_user(
  p_session_token text,
  p_profile_id    uuid
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

  update profiles
  set is_active          = true,
      failed_login_count = 0,
      locked_until       = null,
      updated_at         = now()
  where id = p_profile_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'user not found';
  end if;

  return jsonb_build_object('id', p_profile_id, 'is_active', true);
end;
$$;

create or replace function public.admin_list_public_teams(
  p_session_token text
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

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',                    t.id,
      'name',                  t.name,
      'team_type',             t.team_type,
      'leader_name',           p.display_name,
      'member_count',          (select count(*) from team_members tm2
                                where tm2.team_id = t.id and tm2.removed_at is null),
      'active_member_count',   (select count(*) from team_members tm2
                                where tm2.team_id = t.id and tm2.is_active = true and tm2.removed_at is null),
      'inactive_member_count', (select count(*) from team_members tm2
                                where tm2.team_id = t.id and tm2.is_active = false and tm2.removed_at is null),
      'status',                t.status,
      'created_at',            t.created_at
    ) order by t.created_at desc
  ), '[]'::jsonb) into v_result
  from (
    select id, name, team_type, status, created_at, leader_id
    from teams
    where is_active = true and is_public = true
    order by created_at desc
    limit 200
  ) t
  join profiles p on p.id = t.leader_id;

  return v_result;
end;
$$;

-- ─── Grants ─────────────────────────────────────────────────────────────────
-- Matches this project's pattern: authorization happens inside each function
-- body (via admin_profile_id_from_session), not via Postgres role grants, so
-- these are granted to anon like every other RPC. The internal helper above
-- is deliberately NOT granted to anon/authenticated.

grant execute on function public.get_admin_dashboard(text)       to anon;
grant execute on function public.admin_list_users(text, text)    to anon;
grant execute on function public.admin_get_user_detail(text, uuid) to anon;
grant execute on function public.admin_deactivate_user(text, uuid) to anon;
grant execute on function public.admin_reactivate_user(text, uuid) to anon;
grant execute on function public.admin_list_public_teams(text)   to anon;
