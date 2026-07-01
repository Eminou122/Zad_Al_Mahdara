-- Gate 8: External Students / Accountless Team Members
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run
-- Additive-only. Does NOT modify migrations 001-010.
-- No invitations, linking, service role, or direct table access.

create table if not exists public.external_students (
  id                uuid        primary key default gen_random_uuid(),
  display_name      text        not null check (length(trim(display_name)) between 1 and 80),
  phone_number      text        not null unique check (phone_number ~ '^[0-9]{8}$'),
  phone_masked      text        not null,
  created_by        uuid        not null references public.profiles(id) on delete restrict,
  linked_profile_id uuid        null unique references public.profiles(id) on delete set null,
  is_active         boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table public.external_students enable row level security;
revoke all on public.external_students from anon, authenticated;

alter table public.team_members
  add column if not exists external_student_id uuid null references public.external_students(id) on delete restrict;

alter table public.team_members
  alter column profile_id drop not null;

alter table public.team_members
  drop constraint if exists team_members_one_member_kind;

alter table public.team_members
  add constraint team_members_one_member_kind check (
    (profile_id is not null and external_student_id is null)
    or
    (profile_id is null and external_student_id is not null)
  );

create unique index if not exists external_students_phone_number_idx
  on public.external_students(phone_number);

create index if not exists team_members_external_student_idx
  on public.team_members(external_student_id)
  where removed_at is null;

create unique index if not exists team_members_active_external_student
  on public.team_members(team_id, external_student_id)
  where external_student_id is not null and removed_at is null;

create or replace function public.team_phone_conflicts_same_type(
  p_team_id uuid,
  p_team_type text,
  p_phone_number text
) returns boolean
language sql
security definer
set search_path = 'public', 'extensions'
as $$
  select exists(
    select 1
    from public.teams t
    join public.team_members tm on tm.team_id = t.id
    left join public.profiles p on p.id = tm.profile_id
    left join public.external_students es on es.id = tm.external_student_id
    where (p_team_id is null or t.id <> p_team_id)
      and t.is_active = true
      and t.team_type = p_team_type
      and tm.is_active = true
      and tm.removed_at is null
      and coalesce(p.phone_number, es.phone_number) = p_phone_number
  );
$$;

revoke execute on function public.team_phone_conflicts_same_type(uuid, text, text) from public;
revoke execute on function public.team_phone_conflicts_same_type(uuid, text, text) from anon;
revoke execute on function public.team_phone_conflicts_same_type(uuid, text, text) from authenticated;

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
  v_phone      text;
  v_team_id    uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select phone_number into v_phone
  from profiles
  where id = v_profile_id and is_active = true;
  if not found then
    raise exception 'profile not found';
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

  if public.team_phone_conflicts_same_type(null, p_team_type, v_phone) then
    raise exception 'هذا الطالب موجود في فريق من نفس النوع';
  end if;

  insert into teams (name, team_type, leader_id, is_public, status, note)
  values (trim(p_name), p_team_type, v_profile_id, coalesce(p_is_public, true), p_status, p_note)
  returning id into v_team_id;

  insert into team_members (team_id, profile_id, external_student_id, position, role, is_active, removed_at)
  values (v_team_id, v_profile_id, null, 1, 'leader', true, null);

  return get_team_detail(p_session_token, v_team_id);
end;
$$;

create or replace function public.upsert_external_student_and_add_to_team(
  p_session_token text,
  p_team_id uuid,
  p_display_name text,
  p_phone_number text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_team       teams%rowtype;
  v_external_id uuid;
  v_next_pos   int;
  v_name       text := trim(p_display_name);
  v_phone_masked text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can add members';
  end if;

  if length(v_name) not between 1 and 80 then
    raise exception 'invalid display_name';
  end if;
  if p_phone_number !~ '^[0-9]{8}$' then
    raise exception 'رقم الهاتف يجب أن يكون 8 أرقام';
  end if;
  if exists(select 1 from profiles where phone_number = p_phone_number) then
    raise exception 'هذا الرقم لديه حساب، ابحث عنه وأضفه من نتائج البحث';
  end if;

  if public.team_phone_conflicts_same_type(p_team_id, v_team.team_type, p_phone_number) then
    raise exception 'هذا الطالب موجود في فريق من نفس النوع';
  end if;

  select id into v_external_id
  from external_students
  where phone_number = p_phone_number;

  if v_external_id is null then
    v_phone_masked := substr(p_phone_number, 1, 2) || '****' || substr(p_phone_number, 7, 2);
    insert into external_students (display_name, phone_number, phone_masked, created_by)
    values (v_name, p_phone_number, v_phone_masked, v_profile_id)
    returning id into v_external_id;
  end if;

  if exists(
    select 1
    from team_members tm
    left join profiles p on p.id = tm.profile_id
    left join external_students es on es.id = tm.external_student_id
    where tm.team_id = p_team_id
      and tm.removed_at is null
      and coalesce(p.phone_number, es.phone_number) = p_phone_number
  ) then
    raise exception 'student is already a member of this team';
  end if;

  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_members
  where team_id = p_team_id and removed_at is null;

  insert into team_members (team_id, profile_id, external_student_id, position, role, is_active)
  values (p_team_id, null, v_external_id, v_next_pos, 'member', true);

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

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
        'member_id',           tm.id,
        'profile_id',          tm.profile_id,
        'external_student_id', tm.external_student_id,
        'display_name',        coalesce(p.display_name, es.display_name),
        'phone_masked',        coalesce(p.phone_masked, es.phone_masked),
        'member_kind',         case when tm.external_student_id is null then 'account' else 'external' end,
        'has_account',         tm.profile_id is not null,
        'role',                tm.role,
        'position',            tm.position,
        'is_active',           tm.is_active,
        'deactivated_at',      tm.deactivated_at,
        'joined_at',           tm.joined_at
      ) order by tm.position
    ), '[]'::jsonb) into v_members
    from team_members tm
    left join profiles p on p.id = tm.profile_id
    left join external_students es on es.id = tm.external_student_id
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
  v_team       teams%rowtype;
  v_target     profiles%rowtype;
  v_next_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can add members';
  end if;

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
  end if;

  select * into v_target from profiles where id = p_user_id and is_active = true;
  if not found then
    raise exception 'student not found';
  end if;

  if exists(
    select 1
    from team_members tm
    left join profiles p on p.id = tm.profile_id
    left join external_students es on es.id = tm.external_student_id
    where tm.team_id = p_team_id
      and tm.removed_at is null
      and coalesce(p.phone_number, es.phone_number) = v_target.phone_number
  ) then
    raise exception 'student is already a member of this team';
  end if;

  if public.team_phone_conflicts_same_type(p_team_id, v_team.team_type, v_target.phone_number) then
    raise exception 'هذا الطالب موجود في فريق من نفس النوع';
  end if;

  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_members
  where team_id = p_team_id and removed_at is null;

  insert into team_members (team_id, profile_id, external_student_id, position, role, is_active)
  values (p_team_id, p_user_id, null, v_next_pos, 'member', true);

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

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
  v_team       teams%rowtype;
  v_rows       int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'only team leader can update settings';
  end if;

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
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

  if p_team_type <> v_team.team_type and exists(
    select 1
    from team_members mine
    left join profiles mp on mp.id = mine.profile_id
    left join external_students mes on mes.id = mine.external_student_id
    join teams other_t on other_t.id <> p_team_id
      and other_t.is_active = true
      and other_t.team_type = p_team_type
    join team_members other_tm on other_tm.team_id = other_t.id
      and other_tm.is_active = true
      and other_tm.removed_at is null
    left join profiles op on op.id = other_tm.profile_id
    left join external_students oes on oes.id = other_tm.external_student_id
    where mine.team_id = p_team_id
      and mine.is_active = true
      and mine.removed_at is null
      and coalesce(mp.phone_number, mes.phone_number) = coalesce(op.phone_number, oes.phone_number)
  ) then
    raise exception 'هذا الطالب موجود في فريق من نفس النوع';
  end if;

  update teams
  set name       = trim(p_name),
      team_type  = p_team_type,
      is_public  = coalesce(p_is_public, is_public),
      status     = p_status,
      note       = p_note,
      updated_at = now()
  where id = p_team_id and is_active = true;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'team not found';
  end if;

  return get_team_detail(p_session_token, p_team_id);
end;
$$;

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
      'phone_masked', p.phone_masked,
      'member_kind',  'account',
      'source',       'account'
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
      'display_name', coalesce(p.display_name, es.display_name),
      'position',     tt.position
    )
  into v_today_turn
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  where tt.team_id = p_team_id and tt.turn_date = v_today
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
      'completed_at', tt.completed_at
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
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id;

  return jsonb_build_object(
    'can_manage_turns',    v_is_leader,
    'today_turn',          v_today_turn,
    'next_member',         v_next_member,
    'last_completed_turn', v_last_done,
    'history',             v_history
  );
end;
$$;

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
      'display_name', coalesce(p.display_name, es.display_name),
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
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id;

  return v_result;
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
  v_member     team_members%rowtype;
  v_phone      text;
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

  select * into v_member
  from team_members
  where id = p_member_id and team_id = p_team_id and removed_at is null;
  if not found then
    raise exception 'member not found';
  end if;

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
  end if;

  select coalesce(p.phone_number, es.phone_number) into v_phone
  from team_members tm
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  where tm.id = p_member_id;

  if public.team_phone_conflicts_same_type(p_team_id, v_team.team_type, v_phone) then
    raise exception 'هذا الطالب موجود في فريق من نفس النوع';
  end if;

  update team_members
  set is_active      = true,
      deactivated_at = null,
      updated_at     = now()
  where id = p_member_id and team_id = p_team_id and removed_at is null;

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

grant execute on function public.upsert_external_student_and_add_to_team(text, uuid, text, text) to anon;
grant execute on function public.create_team(text, text, text, boolean, text, text) to anon;
grant execute on function public.get_team_detail(text, uuid) to anon;
grant execute on function public.get_public_teams(text) to anon;
grant execute on function public.add_team_member(text, uuid, uuid) to anon;
grant execute on function public.update_team_settings(text, uuid, text, text, boolean, text, text) to anon;
grant execute on function public.search_students_for_team(text, text) to anon;
grant execute on function public.get_team_turn_state(text, uuid) to anon;
grant execute on function public.get_team_turn_history(text, uuid) to anon;
grant execute on function public.ensure_today_turn(text, uuid) to anon;
grant execute on function public.complete_team_turn(text, uuid) to anon;
grant execute on function public.reactivate_team_member(text, uuid, uuid) to anon;
