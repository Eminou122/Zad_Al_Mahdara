-- Gate 5: Team Management Foundation
-- Apply manually: Supabase Dashboard → SQL Editor → Run
-- Re-runnable on a fresh dev DB (drops only team tables, never auth/budget tables).
-- WARNING: Destroys team data. Only run on dev DB before real team data exists.
-- Auth (001) and budget (002) migrations are NOT touched.

-- ─── Drop team tables safely ─────────────────────────────────────────────────
drop table if exists public.team_members cascade;
drop table if exists public.teams        cascade;

-- ─── teams ───────────────────────────────────────────────────────────────────
create table public.teams (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null check (length(trim(name)) between 1 and 80),
  team_type  text        not null check (team_type in ('lunch','breakfast','dinner','tea','other')),
  leader_id  uuid        not null references public.profiles(id) on delete restrict,
  is_public  boolean     not null default true,
  status     text        not null default 'open' check (status in ('open','closed','full')),
  note       text        null check (note is null or length(note) <= 300),
  is_active  boolean     not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index teams_public_idx on public.teams(is_public, status, created_at desc)
  where is_active = true;
create index teams_leader_idx  on public.teams(leader_id)
  where is_active = true;

-- ─── team_members ─────────────────────────────────────────────────────────────
create table public.team_members (
  id             uuid        primary key default gen_random_uuid(),
  team_id        uuid        not null references public.teams(id)    on delete cascade,
  profile_id     uuid        not null references public.profiles(id) on delete cascade,
  position       int         not null check (position > 0),
  role           text        not null default 'member' check (role in ('leader','member')),
  is_active      boolean     not null default true,
  joined_at      timestamptz not null default now(),
  deactivated_at timestamptz null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- unique active membership per team + profile
create unique index team_members_active_membership
  on public.team_members(team_id, profile_id)
  where is_active = true;

-- unique active position per team (display order; no rotation in Gate 5)
create unique index team_members_active_position
  on public.team_members(team_id, position)
  where is_active = true;

create index team_members_profile_idx on public.team_members(profile_id)  where is_active = true;
create index team_members_team_idx    on public.team_members(team_id)     where is_active = true;

-- ─── RLS: all access goes through SECURITY DEFINER RPCs ──────────────────────
alter table public.teams        enable row level security;
alter table public.team_members enable row level security;

revoke all on public.teams        from anon, authenticated;
revoke all on public.team_members from anon, authenticated;

-- ─── Helper: _team_json (internal, used by several RPCs) ─────────────────────
-- Not a standalone function — inlined in each RPC for simplicity.

-- ─── create_team ─────────────────────────────────────────────────────────────
create or replace function public.create_team(
  p_session_token text,
  p_name          text,
  p_team_type     text,
  p_is_public     boolean,
  p_status        text,
  p_note          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_team_id    uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_name)) not between 1 and 80 then
    raise exception 'name invalid';
  end if;
  if p_team_type not in ('lunch','breakfast','dinner','tea','other') then
    raise exception 'team_type invalid';
  end if;
  if p_status not in ('open','closed','full') then
    raise exception 'status invalid';
  end if;
  if p_note is not null and length(p_note) > 300 then
    raise exception 'note too long';
  end if;

  insert into teams (name, team_type, leader_id, is_public, status, note)
  values (trim(p_name), p_team_type, v_profile_id, coalesce(p_is_public, true), p_status, p_note)
  returning id into v_team_id;

  insert into team_members (team_id, profile_id, position, role, is_active)
  values (v_team_id, v_profile_id, 1, 'leader', true);

  return get_team_detail(p_session_token, v_team_id);
end;
$$;

-- ─── get_my_teams ────────────────────────────────────────────────────────────
create or replace function public.get_my_teams(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_result     jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',           t.id,
      'name',         t.name,
      'team_type',    t.team_type,
      'is_public',    t.is_public,
      'status',       t.status,
      'leader_name',  p.display_name,
      'member_count', (select count(*) from team_members tm2
                       where tm2.team_id = t.id and tm2.is_active = true),
      'my_role',      tm.role,
      'is_leader',    tm.role = 'leader'
    ) order by t.created_at desc
  ), '[]'::jsonb) into v_result
  from teams t
  join team_members tm on tm.team_id = t.id
                      and tm.profile_id = v_profile_id
                      and tm.is_active = true
  join profiles p on p.id = t.leader_id
  where t.is_active = true;

  return v_result;
end;
$$;

-- ─── get_public_teams ────────────────────────────────────────────────────────
create or replace function public.get_public_teams(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_result     jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',           t.id,
      'name',         t.name,
      'team_type',    t.team_type,
      'leader_name',  p.display_name,
      'member_count', (select count(*) from team_members tm2
                       where tm2.team_id = t.id and tm2.is_active = true),
      'status',       t.status
    ) order by t.created_at desc
  ), '[]'::jsonb) into v_result
  from (
    select id, name, team_type, status, created_at, leader_id
    from teams
    where is_active = true and is_public = true
    order by created_at desc
    limit 50
  ) t
  join profiles p on p.id = t.leader_id;

  return v_result;
end;
$$;

-- ─── get_team_detail ─────────────────────────────────────────────────────────
create or replace function public.get_team_detail(
  p_session_token text,
  p_team_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id   uuid;
  v_team         teams%rowtype;
  v_membership   team_members%rowtype;
  v_is_member    boolean := false;
  v_can_edit     boolean := false;
  v_leader_name  text;
  v_member_count bigint;
  v_members      jsonb;
  v_team_json    jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
  end if;

  select * into v_membership
  from team_members
  where team_id = p_team_id and profile_id = v_profile_id and is_active = true;
  v_is_member := found;

  -- Private teams are invisible to non-members
  if not v_team.is_public and not v_is_member then
    raise exception 'team not found or access denied';
  end if;

  select display_name into v_leader_name from profiles where id = v_team.leader_id;
  select count(*) into v_member_count from team_members where team_id = p_team_id and is_active = true;

  v_team_json := jsonb_build_object(
    'id',           v_team.id,
    'name',         v_team.name,
    'team_type',    v_team.team_type,
    'is_public',    v_team.is_public,
    'status',       v_team.status,
    'note',         v_team.note,
    'leader_id',    v_team.leader_id,
    'leader_name',  v_leader_name,
    'member_count', v_member_count,
    'created_at',   v_team.created_at
  );

  if v_is_member then
    v_can_edit := v_membership.role = 'leader';

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'member_id',    tm.id,
        'profile_id',   tm.profile_id,
        'display_name', p.display_name,
        'role',         tm.role,
        'position',     tm.position,
        'joined_at',    tm.joined_at
      ) order by tm.position
    ), '[]'::jsonb) into v_members
    from team_members tm
    join profiles p on p.id = tm.profile_id
    where tm.team_id = p_team_id and tm.is_active = true;
  else
    v_members  := '[]'::jsonb;
    v_can_edit := false;
  end if;

  return jsonb_build_object(
    'team',      v_team_json,
    'members',   v_members,
    'can_edit',  v_can_edit,
    'is_member', v_is_member
  );
end;
$$;

-- ─── update_team_settings ────────────────────────────────────────────────────
create or replace function public.update_team_settings(
  p_session_token text,
  p_team_id       uuid,
  p_name          text,
  p_team_type     text,
  p_is_public     boolean,
  p_status        text,
  p_note          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_rows       int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  -- Only leader may update
  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader' and is_active = true
  ) then
    raise exception 'only team leader can update settings';
  end if;

  if length(trim(p_name)) not between 1 and 80 then
    raise exception 'name invalid';
  end if;
  if p_team_type not in ('lunch','breakfast','dinner','tea','other') then
    raise exception 'team_type invalid';
  end if;
  if p_status not in ('open','closed','full') then
    raise exception 'status invalid';
  end if;
  if p_note is not null and length(p_note) > 300 then
    raise exception 'note too long';
  end if;

  update teams
  set name      = trim(p_name),
      team_type = p_team_type,
      is_public = coalesce(p_is_public, is_public),
      status    = p_status,
      note      = p_note,
      updated_at = now()
  where id = p_team_id and is_active = true;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'team not found';
  end if;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── search_students_for_team ────────────────────────────────────────────────
create or replace function public.search_students_for_team(
  p_session_token text,
  p_query         text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_result     jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_query)) < 2 then
    raise exception 'query too short';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'profile_id',   p.id,
      'display_name', p.display_name,
      'phone_masked', p.phone_masked
    ) order by p.display_name
  ), '[]'::jsonb) into v_result
  from (
    select p.id, p.display_name, p.phone_masked
    from profiles p
    where p.is_active = true
      and p.display_name ilike '%' || trim(p_query) || '%'
    limit 20
  ) p;

  return v_result;
end;
$$;

-- ─── add_team_member ─────────────────────────────────────────────────────────
create or replace function public.add_team_member(
  p_session_token text,
  p_team_id       uuid,
  p_user_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_next_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  -- Only leader may add members
  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader' and is_active = true
  ) then
    raise exception 'only team leader can add members';
  end if;

  -- Team must be active
  if not exists(select 1 from teams where id = p_team_id and is_active = true) then
    raise exception 'team not found';
  end if;

  -- Target must exist and be active
  if not exists(select 1 from profiles where id = p_user_id and is_active = true) then
    raise exception 'student not found';
  end if;

  -- Prevent duplicate active membership
  if exists(
    select 1 from team_members where team_id = p_team_id and profile_id = p_user_id and is_active = true
  ) then
    raise exception 'student is already a member of this team';
  end if;

  -- Next position = max active position + 1
  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_members
  where team_id = p_team_id and is_active = true;

  insert into team_members (team_id, profile_id, position, role, is_active)
  values (p_team_id, p_user_id, v_next_pos, 'member', true);

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── deactivate_team_member ───────────────────────────────────────────────────
create or replace function public.deactivate_team_member(
  p_session_token text,
  p_team_id       uuid,
  p_member_id     uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id     uuid;
  v_target_role    text;
  v_rows           int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  -- Only leader may deactivate members
  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader' and is_active = true
  ) then
    raise exception 'only team leader can remove members';
  end if;

  -- Get target member's role
  select role into v_target_role
  from team_members
  where id = p_member_id and team_id = p_team_id and is_active = true;

  if not found then
    raise exception 'member not found';
  end if;

  -- Cannot remove the team leader in Gate 5
  if v_target_role = 'leader' then
    raise exception 'cannot remove the team leader';
  end if;

  update team_members
  set is_active      = false,
      deactivated_at = now(),
      updated_at     = now()
  where id = p_member_id;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── Revoke helper (if one were created here; current_profile_id_from_session ─
-- is already restricted in 002_budget_foundation.sql). No new internal helpers.

-- ─── Grants: only public-facing RPCs granted to anon ────────────────────────
grant execute on function public.create_team(text, text, text, boolean, text, text)        to anon;
grant execute on function public.get_my_teams(text)                                         to anon;
grant execute on function public.get_public_teams(text)                                     to anon;
grant execute on function public.get_team_detail(text, uuid)                                to anon;
grant execute on function public.update_team_settings(text, uuid, text, text, boolean, text, text) to anon;
grant execute on function public.search_students_for_team(text, text)                       to anon;
grant execute on function public.add_team_member(text, uuid, uuid)                          to anon;
grant execute on function public.deactivate_team_member(text, uuid, uuid)                   to anon;
