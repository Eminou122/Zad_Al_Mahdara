-- Gate 6.5: Member Counts + Reactivation Turn Recompute Fix
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run
-- Additive-only replacement functions. Does NOT modify 001-008.
-- Never hard-deletes team_members rows.

create or replace function public.get_team_detail(
  p_session_token text,
  p_team_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id            uuid;
  v_team                  teams%rowtype;
  v_membership            team_members%rowtype;
  v_is_member             boolean := false;
  v_can_edit              boolean := false;
  v_leader_name           text;
  v_member_count          bigint;
  v_active_member_count   bigint;
  v_inactive_member_count bigint;
  v_members               jsonb;
  v_team_json             jsonb;
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

  if not v_team.is_public and not v_is_member then
    raise exception 'team not found or access denied';
  end if;

  select display_name into v_leader_name from profiles where id = v_team.leader_id;

  select
    count(*),
    count(*) filter (where is_active = true),
    count(*) filter (where is_active = false)
  into v_member_count, v_active_member_count, v_inactive_member_count
  from team_members
  where team_id = p_team_id and removed_at is null;

  v_team_json := jsonb_build_object(
    'id',                    v_team.id,
    'name',                  v_team.name,
    'team_type',             v_team.team_type,
    'is_public',             v_team.is_public,
    'status',                v_team.status,
    'note',                  v_team.note,
    'leader_id',             v_team.leader_id,
    'leader_name',           v_leader_name,
    'member_count',          v_member_count,
    'active_member_count',   v_active_member_count,
    'inactive_member_count', v_inactive_member_count,
    'created_at',            v_team.created_at
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
      'id',                    t.id,
      'name',                  t.name,
      'team_type',             t.team_type,
      'is_public',             t.is_public,
      'status',                t.status,
      'leader_name',           p.display_name,
      'member_count',          (select count(*) from team_members tm2
                                where tm2.team_id = t.id and tm2.removed_at is null),
      'active_member_count',   (select count(*) from team_members tm2
                                where tm2.team_id = t.id and tm2.is_active = true and tm2.removed_at is null),
      'inactive_member_count', (select count(*) from team_members tm2
                                where tm2.team_id = t.id and tm2.is_active = false and tm2.removed_at is null),
      'my_role',               tm.role,
      'is_leader',             tm.role = 'leader' and tm.is_active = true
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
      'status',                t.status
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

  -- If current_position was only kept on last_completed while everyone else was
  -- inactive, prefer the first active member after last_completed when one exists.
  if v_team.current_position is not null
     and (v_team.last_completed_position is null
          or v_team.current_position <> v_team.last_completed_position
          or not exists (
            select 1 from team_members tm
            where tm.team_id = p_team_id
              and tm.position > v_team.last_completed_position
              and tm.is_active = true
              and tm.removed_at is null
          )) then
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
    v_anchor := coalesce(v_team.last_completed_position, v_team.current_position);

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
  v_team       teams%rowtype;
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

  select * into v_team from teams where id = p_team_id and is_active = true;

  if v_team.current_position is null
     or v_team.current_position = v_team.last_completed_position
     or not exists (
       select 1 from team_members tm
       where tm.team_id = p_team_id
         and tm.position = v_team.current_position
         and tm.is_active = true
         and tm.removed_at is null
     ) then
    if v_team.last_completed_position is not null then
      select tm.position into v_next_pos
      from team_members tm
      where tm.team_id = p_team_id
        and tm.position > v_team.last_completed_position
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;

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

grant execute on function public.get_team_detail(text, uuid) to anon;
grant execute on function public.get_my_teams(text) to anon;
grant execute on function public.get_public_teams(text) to anon;
grant execute on function public.get_team_turn_state(text, uuid) to anon;
grant execute on function public.reactivate_team_member(text, uuid, uuid) to anon;
