-- Gate 6.2: Temporary Absence + Reactivation Fix
-- Apply manually: Supabase Dashboard → SQL Editor → Run
-- Additive-only. Does NOT modify 001, 002, 003, 004, or 005 migrations.
-- Safe to re-apply (create or replace). Never hard-deletes team_members rows.
--
-- Lifecycle meaning:
--   Active:    removed_at is null, is_active = true  → visible, private access, turn-eligible.
--   Inactive:  removed_at is null, is_active = false → visible as "غير نشط", private access,
--              can view team detail/turn history, skipped from turns, reactivatable by leader.
--   Removed:   removed_at is not null                → hidden from team member list, no private
--              access, old turn history stays valid (team_turns.member_id still resolves).
--
-- Rule split used throughout this file:
--   Team access / membership visibility = removed_at is null
--   Leader management permission        = role = 'leader' and is_active = true and removed_at is null
--   Turn eligibility                    = is_active = true and removed_at is null
--   History joins                       = no removed_at filter

-- ─── 1. get_team_detail ──────────────────────────────────────────────────────
-- Membership/access no longer requires is_active=true — inactive-but-not-removed
-- members keep full team access. can_edit now checks membership.is_active explicitly.

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
  where team_id = p_team_id and profile_id = v_profile_id and removed_at is null;
  v_is_member := found;

  -- Private teams are invisible to non-members. Inactive-but-not-removed members
  -- still count as members here.
  if not v_team.is_public and not v_is_member then
    raise exception 'team not found or access denied';
  end if;

  select display_name into v_leader_name from profiles where id = v_team.leader_id;
  select count(*) into v_member_count
  from team_members
  where team_id = p_team_id and is_active = true and removed_at is null;

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
    v_can_edit := v_membership.role = 'leader' and v_membership.is_active = true;

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'member_id',      tm.id,
        'profile_id',     tm.profile_id,
        'display_name',   p.display_name,
        'role',           tm.role,
        'position',       tm.position,
        'is_active',      tm.is_active,
        'deactivated_at', tm.deactivated_at,
        'joined_at',      tm.joined_at
      ) order by tm.position
    ), '[]'::jsonb) into v_members
    from team_members tm
    join profiles p on p.id = tm.profile_id
    where tm.team_id = p_team_id and tm.removed_at is null;
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

-- ─── 2. get_team_turn_state ──────────────────────────────────────────────────
-- Access no longer requires is_active=true — inactive-but-not-removed members can
-- still view today's turn, next member, and history. Leader flag stays strict.

create or replace function public.get_team_turn_state(
  p_session_token text,
  p_team_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_team       teams%rowtype;
  v_membership team_members%rowtype;
  v_is_member  boolean := false;
  v_is_leader  boolean := false;
  v_today      date    := current_date;
  v_today_turn jsonb   := null;
  v_next_mid   uuid;
  v_next_pos   int;
  v_next_name  text;
  v_next_member  jsonb := null;
  v_last_done  jsonb   := null;
  v_history    jsonb   := '[]'::jsonb;
  v_turn_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then raise exception 'team not found'; end if;

  select * into v_membership
  from team_members
  where team_id = p_team_id and profile_id = v_profile_id and removed_at is null;
  v_is_member := found;
  v_is_leader := found and v_membership.role = 'leader' and v_membership.is_active = true;

  if not v_team.is_public and not v_is_member then
    raise exception 'team not found or access denied';
  end if;

  if not v_is_member then
    return jsonb_build_object(
      'can_manage_turns',    false,
      'today_turn',          null,
      'next_member',         null,
      'last_completed_turn', null,
      'history',             '[]'::jsonb
    );
  end if;

  -- Today's turn
  select jsonb_build_object(
      'id',           tt.id,
      'turn_date',    tt.turn_date,
      'status',       tt.status,
      'member_id',    tt.member_id,
      'display_name', p.display_name,
      'position',     tt.position
    )
  into v_today_turn
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  join profiles p      on p.id  = tm.profile_id
  where tt.team_id = p_team_id and tt.turn_date = v_today
  limit 1;

  -- Next member logic
  if v_today_turn is not null then
    v_turn_pos := (v_today_turn->>'position')::int;
    if v_today_turn->>'status' = 'completed' then
      -- After completion, teams.current_position = next active person
      if v_team.current_position is not null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
          and tm.position = v_team.current_position
        limit 1;
      end if;
    else
      -- Pending: next active after today's position
      select tm.id, p.display_name, tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      join profiles p on p.id = tm.profile_id
      where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
        and tm.position > v_turn_pos
      order by tm.position limit 1;
      -- Wrap
      if v_next_mid is null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
        order by tm.position limit 1;
      end if;
    end if;
  else
    -- No today turn: mirror ensure_today_turn pick logic
    if v_team.current_position is not null then
      select tm.id, p.display_name, tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      join profiles p on p.id = tm.profile_id
      where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
        and tm.position = v_team.current_position
      limit 1;
    end if;
    if v_next_mid is null then
      if v_team.last_completed_position is not null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
          and tm.position > v_team.last_completed_position
        order by tm.position limit 1;
      end if;
      if v_next_mid is null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
        order by tm.position limit 1;
      end if;
    end if;
  end if;

  if v_next_mid is not null then
    v_next_member := jsonb_build_object(
      'member_id',    v_next_mid,
      'position',     v_next_pos,
      'display_name', v_next_name
    );
  end if;

  -- Last completed turn
  select jsonb_build_object(
      'id',           tt.id,
      'turn_date',    tt.turn_date,
      'status',       tt.status,
      'member_id',    tt.member_id,
      'display_name', p.display_name,
      'position',     tt.position,
      'completed_at', tt.completed_at
    )
  into v_last_done
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  join profiles p      on p.id  = tm.profile_id
  where tt.team_id = p_team_id and tt.status = 'completed'
  order by tt.turn_date desc
  limit 1;

  -- History (last 20) — unfiltered by removed_at/is_active on purpose
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',           sub.id,
      'turn_date',    sub.turn_date,
      'status',       sub.status,
      'member_id',    sub.member_id,
      'display_name', p.display_name,
      'position',     sub.position,
      'completed_at', sub.completed_at
    ) order by sub.turn_date desc
  ), '[]'::jsonb) into v_history
  from (
    select tt.id, tt.turn_date, tt.status, tt.member_id, tt.position, tt.completed_at
    from team_turns tt
    where tt.team_id = p_team_id
    order by tt.turn_date desc
    limit 20
  ) sub
  join team_members tm on tm.id = sub.member_id
  join profiles p      on p.id  = tm.profile_id;

  return jsonb_build_object(
    'can_manage_turns',    v_is_leader,
    'today_turn',          v_today_turn,
    'next_member',         v_next_member,
    'last_completed_turn', v_last_done,
    'history',             v_history
  );
end;
$$;

-- ─── 3. get_team_turn_history ────────────────────────────────────────────────
-- Access no longer requires is_active=true. History joins stay unfiltered.

create or replace function public.get_team_turn_history(
  p_session_token text,
  p_team_id       uuid
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

  if not exists(select 1 from teams where id = p_team_id and is_active = true) then
    raise exception 'team not found';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and removed_at is null
  ) then
    raise exception 'team not found or access denied';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',           sub.id,
      'turn_date',    sub.turn_date,
      'status',       sub.status,
      'member_id',    sub.member_id,
      'display_name', p.display_name,
      'position',     sub.position,
      'completed_at', sub.completed_at
    ) order by sub.turn_date desc
  ), '[]'::jsonb) into v_result
  from (
    select tt.id, tt.turn_date, tt.status, tt.member_id, tt.position, tt.completed_at
    from team_turns tt
    where tt.team_id = p_team_id
    order by tt.turn_date desc
    limit 20
  ) sub
  join team_members tm on tm.id = sub.member_id
  join profiles p      on p.id  = tm.profile_id;

  return v_result;
end;
$$;

-- ─── 4. ensure_today_turn ────────────────────────────────────────────────────
-- Unchanged from 005: leader check and turn picks were already strict. Re-declared
-- here so 006 is a self-contained snapshot of the Gate 6 turn RPCs.

create or replace function public.ensure_today_turn(
  p_session_token text,
  p_team_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_team       teams%rowtype;
  v_today      date := current_date;
  v_pick_mid   uuid;
  v_pick_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id
      and role = 'leader' and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه بدء الدور';
  end if;

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then raise exception 'team not found'; end if;

  -- Already have today's turn
  if exists(select 1 from team_turns where team_id = p_team_id and turn_date = v_today) then
    return get_team_turn_state(p_session_token, p_team_id);
  end if;

  -- Block if any older pending turn exists
  if exists(
    select 1 from team_turns
    where team_id = p_team_id and status = 'pending' and turn_date < v_today
  ) then
    raise exception 'أكمل الدور السابق أولاً';
  end if;

  -- Step 1: current_position → active member?
  if v_team.current_position is not null then
    select tm.id, tm.position into v_pick_mid, v_pick_pos
    from team_members tm
    where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
      and tm.position = v_team.current_position
    limit 1;
  end if;

  -- Step 2: next active after last_completed_position
  if v_pick_mid is null and v_team.last_completed_position is not null then
    select tm.id, tm.position into v_pick_mid, v_pick_pos
    from team_members tm
    where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
      and tm.position > v_team.last_completed_position
    order by tm.position limit 1;
    -- Wrap
    if v_pick_mid is null then
      select tm.id, tm.position into v_pick_mid, v_pick_pos
      from team_members tm
      where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
      order by tm.position limit 1;
    end if;
  end if;

  -- Step 3: first active (also handles last_completed_position is null)
  if v_pick_mid is null then
    select tm.id, tm.position into v_pick_mid, v_pick_pos
    from team_members tm
    where tm.team_id = p_team_id and tm.is_active = true and tm.removed_at is null
    order by tm.position limit 1;
  end if;

  if v_pick_mid is null then
    raise exception 'لا يوجد أعضاء نشطون في الفريق';
  end if;

  insert into team_turns (team_id, member_id, turn_date, position, status)
  values (p_team_id, v_pick_mid, v_today, v_pick_pos, 'pending');

  return get_team_turn_state(p_session_token, p_team_id);
end;
$$;

-- ─── 5. complete_team_turn ───────────────────────────────────────────────────
-- Unchanged from 005: leader check and next-member pick were already strict.
-- Re-declared here so 006 is a self-contained snapshot of the Gate 6 turn RPCs.

create or replace function public.complete_team_turn(
  p_session_token text,
  p_turn_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_turn       team_turns%rowtype;
  v_next_mid   uuid;
  v_next_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_turn from team_turns where id = p_turn_id;
  if not found then raise exception 'turn not found'; end if;

  if v_turn.status <> 'pending' then
    raise exception 'turn is not pending';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = v_turn.team_id and profile_id = v_profile_id
      and role = 'leader' and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه إكمال الدور';
  end if;

  -- Next active after completed position
  select tm.id, tm.position into v_next_mid, v_next_pos
  from team_members tm
  where tm.team_id = v_turn.team_id and tm.is_active = true and tm.removed_at is null
    and tm.position > v_turn.position
  order by tm.position limit 1;
  -- Wrap
  if v_next_mid is null then
    select tm.id, tm.position into v_next_mid, v_next_pos
    from team_members tm
    where tm.team_id = v_turn.team_id and tm.is_active = true and tm.removed_at is null
    order by tm.position limit 1;
  end if;

  update team_turns
  set status       = 'completed',
      completed_by = v_profile_id,
      completed_at = now(),
      updated_at   = now()
  where id = p_turn_id;

  update teams
  set last_completed_position = v_turn.position,
      current_position        = v_next_pos,
      updated_at              = now()
  where id = v_turn.team_id;

  return get_team_turn_state(p_session_token, v_turn.team_id);
end;
$$;

-- ─── 6. deactivate_team_member ───────────────────────────────────────────────
-- Unchanged from 005. Re-declared here so 006 is a self-contained snapshot.

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
  v_profile_id  uuid;
  v_target_role text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  -- Only leader may deactivate members
  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can remove members';
  end if;

  select role into v_target_role
  from team_members
  where id = p_member_id and team_id = p_team_id and removed_at is null;

  if not found then
    raise exception 'member not found';
  end if;

  if v_target_role = 'leader' then
    raise exception 'cannot remove the team leader';
  end if;

  update team_members
  set is_active      = false,
      deactivated_at = coalesce(deactivated_at, now()),
      updated_at     = now()
  where id = p_member_id and team_id = p_team_id and removed_at is null;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── 7. remove_team_member ───────────────────────────────────────────────────
-- Unchanged from 005. Re-declared here so 006 is a self-contained snapshot.

create or replace function public.remove_team_member(
  p_session_token text,
  p_team_id       uuid,
  p_member_id     uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id  uuid;
  v_target_role text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  -- Only leader may remove members
  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can remove members';
  end if;

  select role into v_target_role
  from team_members
  where id = p_member_id and team_id = p_team_id and removed_at is null;

  if not found then
    raise exception 'member not found';
  end if;

  if v_target_role = 'leader' then
    raise exception 'cannot remove the team leader';
  end if;

  update team_members
  set is_active      = false,
      deactivated_at = coalesce(deactivated_at, now()),
      removed_at     = now(),
      updated_at     = now()
  where id = p_member_id and team_id = p_team_id and removed_at is null;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── 8. reactivate_team_member ───────────────────────────────────────────────
-- New: brings a temporarily-absent (deactivated, non-removed) member back.
-- Same team_members.id/position, so old turn history and future turn eligibility
-- both pick it up automatically.

create or replace function public.reactivate_team_member(
  p_session_token text,
  p_team_id       uuid,
  p_member_id     uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  -- Only leader may reactivate members
  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can reactivate members';
  end if;

  if not exists(
    select 1 from team_members
    where id = p_member_id and team_id = p_team_id and removed_at is null
  ) then
    raise exception 'member not found';
  end if;

  update team_members
  set is_active      = true,
      deactivated_at = null,
      updated_at     = now()
  where id = p_member_id and team_id = p_team_id and removed_at is null;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── 9. add_team_member ──────────────────────────────────────────────────────
-- Duplicate check now rejects any non-removed membership (active or inactive),
-- not just active. A previously removed row does not block re-adding.
-- Position allocation now considers non-removed members (active or inactive), not
-- just active ones, so a new member can't reuse an inactive member's position.

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
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
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

  -- Prevent duplicating any visible (non-removed) membership, active or inactive
  if exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = p_user_id and removed_at is null
  ) then
    raise exception 'student is already a member of this team';
  end if;

  -- Next position = max position among non-removed members + 1 (not active-only,
  -- so a new member never reuses a still-reserved inactive member's position)
  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_members
  where team_id = p_team_id and removed_at is null;

  insert into team_members (team_id, profile_id, position, role, is_active)
  values (p_team_id, p_user_id, v_next_pos, 'member', true);

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

-- ─── 10. get_my_teams ────────────────────────────────────────────────────────
-- The 003 version joined team_members with is_active = true, so a temporarily
-- inactive member's own teams silently disappeared from "فرقي". Visibility now
-- only requires removed_at is null; member_count stays active-only.

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
                       where tm2.team_id = t.id and tm2.is_active = true and tm2.removed_at is null),
      'my_role',      tm.role,
      'is_leader',    tm.role = 'leader' and tm.is_active = true
    ) order by t.created_at desc
  ), '[]'::jsonb) into v_result
  from teams t
  join team_members tm on tm.team_id = t.id
                      and tm.profile_id = v_profile_id
                      and tm.removed_at is null
  join profiles p on p.id = t.leader_id
  where t.is_active = true;

  return v_result;
end;
$$;

-- ─── 11. Grants ───────────────────────────────────────────────────────────────
-- All re-declared functions keep their existing grants (CREATE OR REPLACE
-- preserves them). Only the new/changed-signature RPCs need a fresh grant.

grant execute on function public.reactivate_team_member(text, uuid, uuid) to anon;
grant execute on function public.get_my_teams(text) to anon;
