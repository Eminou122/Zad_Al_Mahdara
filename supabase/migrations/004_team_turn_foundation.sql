-- Gate 6: Team Turn Foundation
-- Apply manually: Supabase Dashboard → SQL Editor → Run
-- Additive-only. Does NOT modify 001, 002, or 003 migrations.
-- Safe to re-apply (if not exists / create or replace).

-- ─── 1. Turn state columns on teams ─────────────────────────────────────────

alter table public.teams
  add column if not exists last_completed_position int null,
  add column if not exists current_position        int null;

-- ─── 2. team_turns table ─────────────────────────────────────────────────────

create table if not exists public.team_turns (
  id           uuid        primary key default gen_random_uuid(),
  team_id      uuid        not null references public.teams(id)        on delete cascade,
  member_id    uuid        not null references public.team_members(id) on delete restrict,
  turn_date    date        not null default current_date,
  position     int         not null check (position > 0),
  status       text        not null default 'pending'
                           check (status in ('pending','completed','cancelled')),
  completed_by uuid        null references public.profiles(id)         on delete set null,
  completed_at timestamptz null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index if not exists team_turns_one_per_team_date
  on public.team_turns(team_id, turn_date);

create index if not exists team_turns_team_date_idx
  on public.team_turns(team_id, turn_date desc);

create index if not exists team_turns_member_idx
  on public.team_turns(member_id);

alter table public.team_turns enable row level security;
revoke all on public.team_turns from anon, authenticated;

-- ─── 3. get_team_turn_state ──────────────────────────────────────────────────
-- Active member: full state. Public non-member: empty shell. Private non-member: denied.

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
  where team_id = p_team_id and profile_id = v_profile_id and is_active = true;
  v_is_member := found;
  v_is_leader := found and v_membership.role = 'leader';

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
        where tm.team_id = p_team_id and tm.is_active = true
          and tm.position = v_team.current_position
        limit 1;
      end if;
    else
      -- Pending: next active after today's position
      select tm.id, p.display_name, tm.position
      into v_next_mid, v_next_name, v_next_pos
      from team_members tm
      join profiles p on p.id = tm.profile_id
      where tm.team_id = p_team_id and tm.is_active = true
        and tm.position > v_turn_pos
      order by tm.position limit 1;
      -- Wrap
      if v_next_mid is null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true
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
      where tm.team_id = p_team_id and tm.is_active = true
        and tm.position = v_team.current_position
      limit 1;
    end if;
    if v_next_mid is null then
      if v_team.last_completed_position is not null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true
          and tm.position > v_team.last_completed_position
        order by tm.position limit 1;
      end if;
      if v_next_mid is null then
        select tm.id, p.display_name, tm.position
        into v_next_mid, v_next_name, v_next_pos
        from team_members tm
        join profiles p on p.id = tm.profile_id
        where tm.team_id = p_team_id and tm.is_active = true
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

  -- History (last 20)
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

-- ─── 4. ensure_today_turn ────────────────────────────────────────────────────
-- Leader only. Creates today's pending turn or returns existing one.

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
      and role = 'leader' and is_active = true
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
    where tm.team_id = p_team_id and tm.is_active = true
      and tm.position = v_team.current_position
    limit 1;
  end if;

  -- Step 2: next active after last_completed_position
  if v_pick_mid is null and v_team.last_completed_position is not null then
    select tm.id, tm.position into v_pick_mid, v_pick_pos
    from team_members tm
    where tm.team_id = p_team_id and tm.is_active = true
      and tm.position > v_team.last_completed_position
    order by tm.position limit 1;
    -- Wrap
    if v_pick_mid is null then
      select tm.id, tm.position into v_pick_mid, v_pick_pos
      from team_members tm
      where tm.team_id = p_team_id and tm.is_active = true
      order by tm.position limit 1;
    end if;
  end if;

  -- Step 3: first active (also handles last_completed_position is null)
  if v_pick_mid is null then
    select tm.id, tm.position into v_pick_mid, v_pick_pos
    from team_members tm
    where tm.team_id = p_team_id and tm.is_active = true
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
-- Leader only. Marks pending turn completed and advances rotation.

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
      and role = 'leader' and is_active = true
  ) then
    raise exception 'القائد فقط يمكنه إكمال الدور';
  end if;

  -- Next active after completed position
  select tm.id, tm.position into v_next_mid, v_next_pos
  from team_members tm
  where tm.team_id = v_turn.team_id and tm.is_active = true
    and tm.position > v_turn.position
  order by tm.position limit 1;
  -- Wrap
  if v_next_mid is null then
    select tm.id, tm.position into v_next_mid, v_next_pos
    from team_members tm
    where tm.team_id = v_turn.team_id and tm.is_active = true
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

-- ─── 6. get_team_turn_history ────────────────────────────────────────────────
-- Active members only. Last 20 turns.

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
    where team_id = p_team_id and profile_id = v_profile_id and is_active = true
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

-- ─── Grants ──────────────────────────────────────────────────────────────────

grant execute on function public.get_team_turn_state(text, uuid)  to anon;
grant execute on function public.ensure_today_turn(text, uuid)     to anon;
grant execute on function public.complete_team_turn(text, uuid)    to anon;
grant execute on function public.get_team_turn_history(text, uuid) to anon;
