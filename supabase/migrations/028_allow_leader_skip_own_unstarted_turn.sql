-- Gate 49.5 backend hotfix: allow an active leader to explicitly skip
-- their own previous unstarted missed turn. This redefines only
-- get_team_turn_state and skip_missed_team_turn; no RLS/table grants or
-- shopping workflow are changed.

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
  v_blocking_turn jsonb := null;
  v_blocking_id uuid := null;
  v_blocking_name text := null;
  v_blocking_date date := null;
  v_blocking_status text := null;
  v_can_skip_previous boolean := false;
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
      'can_manage_turns',          false,
      'today_turn',                null,
      'next_member',               null,
      'last_completed_turn',       null,
      'history',                   '[]'::jsonb,
      'blocking_previous_turn',    false,
      'can_skip_previous_turn',    false,
      'blocking_reason',           null,
      'previous_turn_id',          null,
      'previous_turn_member_name', null,
      'previous_turn_date',        null,
      'previous_turn_status',      null
    );
  end if;

  select jsonb_build_object(
      'id',           tt.id,
      'turn_date',    tt.turn_date,
      'status',       tt.status,
      'member_id',    tt.member_id,
      'display_name', coalesce(p.display_name, es.display_name),
      'position',     tt.position,
      'completed_at', tt.completed_at,
      'started_at',   tt.started_at,
      'started_by',   tt.started_by,
      'skipped_at',   tt.skipped_at,
      'skipped_by',   tt.skipped_by,
      'skip_reason',  tt.skip_reason
    )
  into v_today_turn
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  where tt.team_id = p_team_id and tt.turn_date = v_today
  limit 1;

  select jsonb_build_object(
      'id',           tt.id,
      'turn_date',    tt.turn_date,
      'status',       tt.status,
      'member_id',    tt.member_id,
      'display_name', coalesce(p.display_name, es.display_name),
      'position',     tt.position,
      'completed_at', tt.completed_at,
      'started_at',   tt.started_at,
      'started_by',   tt.started_by,
      'skipped_at',   tt.skipped_at,
      'skipped_by',   tt.skipped_by,
      'skip_reason',  tt.skip_reason
    ), tt.id, coalesce(p.display_name, es.display_name), tt.turn_date, tt.status,
    (v_is_leader and tt.status = 'pending' and tt.started_at is null
      and tt.completed_at is null
      and not exists(
        select 1
        from team_shopping_item_occurrences occ
        join team_shopping_items i on i.id = occ.team_shopping_item_id
        where i.team_id = p_team_id
          and occ.occurrence_date = tt.turn_date
      )
      and not exists(
        select 1
        from team_shopping_reports r
        where r.team_id = p_team_id
          and r.report_date = tt.turn_date
          and (
            r.submitted_at is not null
            or r.leader_reviewed_at is not null
            or r.leader_status in ('accepted', 'rejected')
          )
      ))
  into v_blocking_turn, v_blocking_id, v_blocking_name, v_blocking_date,
       v_blocking_status, v_can_skip_previous
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  where tt.team_id = p_team_id
    and tt.turn_date < v_today
    and tt.status = 'pending'
  order by tt.turn_date asc, tt.created_at asc
  limit 1;

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
    select tm.id, coalesce(p.display_name, es.display_name), tm.position
    into v_next_mid, v_next_name, v_next_pos
    from team_members tm
    left join profiles p on p.id = tm.profile_id
    left join external_students es on es.id = tm.external_student_id
    where tm.team_id = p_team_id
      and tm.position = v_team.current_position
      and tm.is_active = true
      and tm.removed_at is null
    limit 1;
  end if;

  if v_next_mid is null then
    v_anchor := coalesce(v_team.last_completed_position, v_team.current_position);

    if v_anchor is not null then
      select tm.id, coalesce(p.display_name, es.display_name), tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      left join profiles p on p.id = tm.profile_id
      left join external_students es on es.id = tm.external_student_id
      where tm.team_id = p_team_id
        and tm.position > v_anchor
        and tm.is_active = true
        and tm.removed_at is null
      order by tm.position
      limit 1;
    end if;

    if v_next_mid is null then
      select tm.id, coalesce(p.display_name, es.display_name), tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      left join profiles p on p.id = tm.profile_id
      left join external_students es on es.id = tm.external_student_id
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
      'display_name', coalesce(p.display_name, es.display_name),
      'position',     tt.position,
      'completed_at', tt.completed_at,
      'started_at',   tt.started_at,
      'started_by',   tt.started_by,
      'skipped_at',   tt.skipped_at,
      'skipped_by',   tt.skipped_by,
      'skip_reason',  tt.skip_reason
    )
  into v_last_done
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  where tt.team_id = p_team_id and tt.status = 'completed'
  order by tt.turn_date desc
  limit 1;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',           sub.id,
      'turn_date',    sub.turn_date,
      'status',       sub.status,
      'member_id',    sub.member_id,
      'display_name', coalesce(p.display_name, es.display_name),
      'position',     sub.position,
      'completed_at', sub.completed_at,
      'started_at',   sub.started_at,
      'started_by',   sub.started_by,
      'skipped_at',   sub.skipped_at,
      'skipped_by',   sub.skipped_by,
      'skip_reason',  sub.skip_reason
    ) order by sub.turn_date desc
  ), '[]'::jsonb) into v_history
  from (
    select tt.id, tt.turn_date, tt.status, tt.member_id, tt.position,
           tt.completed_at, tt.started_at, tt.started_by, tt.skipped_at,
           tt.skipped_by, tt.skip_reason
    from team_turns tt
    where tt.team_id = p_team_id
    order by tt.turn_date desc
    limit 20
  ) sub
  join team_members tm on tm.id = sub.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id;

  return jsonb_build_object(
    'can_manage_turns',          v_is_leader,
    'today_turn',                v_today_turn,
    'next_member',               v_next_member,
    'last_completed_turn',       v_last_done,
    'history',                   v_history,
    'blocking_previous_turn',    v_blocking_turn is not null,
    'can_skip_previous_turn',    coalesce(v_can_skip_previous, false),
    'blocking_reason',           case when v_blocking_turn is null then null else 'أكمل الدور السابق أولاً' end,
    'previous_turn_id',          v_blocking_id,
    'previous_turn_member_name', v_blocking_name,
    'previous_turn_date',        v_blocking_date,
    'previous_turn_status',      v_blocking_status
  );
end;
$$;

create or replace function public.skip_missed_team_turn(
  p_session_token text,
  p_team_id       uuid,
  p_turn_id       uuid,
  p_reason        text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_turn       team_turns%rowtype;
  v_leader_member team_members%rowtype;
  v_next_mid   uuid;
  v_next_pos   int;
  v_reason     text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_leader_member
  from team_members
  where team_id = p_team_id
    and profile_id = v_profile_id
    and role = 'leader'
    and is_active = true
    and removed_at is null;
  if not found then
    raise exception 'القائد فقط يمكنه تخطي الدور';
  end if;

  select * into v_turn
  from team_turns
  where id = p_turn_id and team_id = p_team_id;
  if not found then
    raise exception 'turn not found';
  end if;

  if v_turn.status <> 'pending' then
    raise exception 'لا يمكن تخطي دور غير معلق';
  end if;

  if v_turn.started_at is not null then
    raise exception 'لا يمكن تخطي دور بدأ بالفعل';
  end if;

  if v_turn.completed_at is not null then
    raise exception 'لا يمكن تخطي دور مكتمل';
  end if;

  if v_turn.turn_date >= current_date then
    raise exception 'يمكن تخطي الأدوار السابقة فقط';
  end if;

  if exists(
    select 1
    from team_shopping_item_occurrences occ
    join team_shopping_items i on i.id = occ.team_shopping_item_id
    where i.team_id = p_team_id
      and occ.occurrence_date = v_turn.turn_date
  ) then
    raise exception 'لا يمكن تخطي دور له علامات تسوق';
  end if;

  if exists(
    select 1
    from team_shopping_reports r
    where r.team_id = p_team_id
      and r.report_date = v_turn.turn_date
      and (
        r.submitted_at is not null
        or r.leader_reviewed_at is not null
        or r.leader_status in ('accepted', 'rejected')
      )
  ) then
    raise exception 'لا يمكن تخطي دور له تقرير تسوق';
  end if;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');

  select tm.id, tm.position into v_next_mid, v_next_pos
  from team_members tm
  where tm.team_id = p_team_id
    and tm.position > v_turn.position
    and tm.is_active = true
    and tm.removed_at is null
  order by tm.position
  limit 1;

  if v_next_mid is null then
    select tm.id, tm.position into v_next_mid, v_next_pos
    from team_members tm
    where tm.team_id = p_team_id
      and tm.is_active = true
      and tm.removed_at is null
    order by tm.position
    limit 1;
  end if;

  update team_turns
  set status      = 'skipped',
      skipped_at  = now(),
      skipped_by  = v_profile_id,
      skip_reason = v_reason,
      updated_at  = now()
  where id = p_turn_id;

  update teams
  set current_position = v_next_pos,
      updated_at       = now()
  where id = p_team_id;

  return get_team_turn_state(p_session_token, p_team_id);
end;
$$;

-- Client access remains RPC-only through SECURITY DEFINER functions.
grant execute on function public.get_team_turn_state(text, uuid) to anon;
grant execute on function public.skip_missed_team_turn(text, uuid, uuid, text) to anon;
