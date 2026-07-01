-- Gate 6.3: Recompute Next Turn After Deactivate/Remove
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run
-- Additive-only replacement functions. Does NOT modify 001-006.
-- Never hard-deletes team_members rows.

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
  v_anchor      int;
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

  -- Dynamic next-member picker. Stale current_position never makes next_member empty.
  if v_team.current_position is not null then
    select tm.id, p.display_name, tm.position
    into v_next_mid, v_next_name, v_next_pos
    from team_members tm
    join profiles p on p.id = tm.profile_id
    where tm.team_id = p_team_id
      and tm.position = v_team.current_position
      and tm.is_active = true
      and tm.removed_at is null
    limit 1;
  end if;

  if v_next_mid is null then
    v_anchor := coalesce(v_team.current_position, v_team.last_completed_position);

    if v_anchor is not null then
      select tm.id, p.display_name, tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      join profiles p on p.id = tm.profile_id
      where tm.team_id = p_team_id
        and tm.position > v_anchor
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;

    if v_next_mid is null then
      select tm.id, p.display_name, tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      join profiles p on p.id = tm.profile_id
      where tm.team_id = p_team_id
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;
  end if;

  if v_next_mid is not null then
    v_next_member := jsonb_build_object(
      'member_id',    v_next_mid,
      'position',     v_next_pos,
      'display_name', v_next_name
    );
  end if;

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
  v_anchor     int;
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

  if exists(select 1 from team_turns where team_id = p_team_id and turn_date = v_today) then
    return get_team_turn_state(p_session_token, p_team_id);
  end if;

  if exists(
    select 1 from team_turns
    where team_id = p_team_id and status = 'pending' and turn_date < v_today
  ) then
    raise exception 'أكمل الدور السابق أولاً';
  end if;

  if v_team.current_position is not null then
    select tm.id, tm.position into v_pick_mid, v_pick_pos
    from team_members tm
    where tm.team_id = p_team_id
      and tm.position = v_team.current_position
      and tm.is_active = true
      and tm.removed_at is null
    limit 1;
  end if;

  if v_pick_mid is null then
    v_anchor := coalesce(v_team.current_position, v_team.last_completed_position);

    if v_anchor is not null then
      select tm.id, tm.position into v_pick_mid, v_pick_pos
      from team_members tm
      where tm.team_id = p_team_id
        and tm.position > v_anchor
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;

    if v_pick_mid is null then
      select tm.id, tm.position into v_pick_mid, v_pick_pos
      from team_members tm
      where tm.team_id = p_team_id
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;
  end if;

  if v_pick_mid is null then
    raise exception 'لا يوجد أعضاء نشطون في الفريق';
  end if;

  insert into team_turns (team_id, member_id, turn_date, position, status)
  values (p_team_id, v_pick_mid, v_today, v_pick_pos, 'pending');

  return get_team_turn_state(p_session_token, p_team_id);
end;
$$;

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

  select tm.id, tm.position into v_next_mid, v_next_pos
  from team_members tm
  where tm.team_id = v_turn.team_id
    and tm.position > v_turn.position
    and tm.is_active = true
    and tm.removed_at is null
  order by tm.position
  limit 1;

  if v_next_mid is null then
    select tm.id, tm.position into v_next_mid, v_next_pos
    from team_members tm
    where tm.team_id = v_turn.team_id
      and tm.is_active = true
      and tm.removed_at is null
    order by tm.position
    limit 1;
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
  v_target_pos  int;
  v_next_pos    int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can deactivate members';
  end if;

  select role, position into v_target_role, v_target_pos
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

  if exists(select 1 from teams where id = p_team_id and current_position = v_target_pos) then
    select tm.position into v_next_pos
    from team_members tm
    where tm.team_id = p_team_id
      and tm.position > v_target_pos
      and tm.is_active = true
      and tm.removed_at is null
    order by tm.position
    limit 1;

    if v_next_pos is null then
      select tm.position into v_next_pos
      from team_members tm
      where tm.team_id = p_team_id
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;

    update teams
    set current_position = v_next_pos,
        updated_at = now()
    where id = p_team_id;
  end if;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

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
  v_target_pos  int;
  v_next_pos    int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can remove members';
  end if;

  select role, position into v_target_role, v_target_pos
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

  if exists(select 1 from teams where id = p_team_id and current_position = v_target_pos) then
    select tm.position into v_next_pos
    from team_members tm
    where tm.team_id = p_team_id
      and tm.position > v_target_pos
      and tm.is_active = true
      and tm.removed_at is null
    order by tm.position
    limit 1;

    if v_next_pos is null then
      select tm.position into v_next_pos
      from team_members tm
      where tm.team_id = p_team_id
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;

    update teams
    set current_position = v_next_pos,
        updated_at = now()
    where id = p_team_id;
  end if;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

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
  v_next_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

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

  if exists(select 1 from teams where id = p_team_id and current_position is null) then
    select tm.position into v_next_pos
    from team_members tm
    where tm.team_id = p_team_id
      and tm.is_active = true
      and tm.removed_at is null
    order by tm.position
    limit 1;

    update teams
    set current_position = v_next_pos,
        updated_at = now()
    where id = p_team_id and current_position is null;
  end if;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;
