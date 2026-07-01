-- Gate 8 Fix 4: final live-safe reactivation conflict fix.
-- Apply manually after 013_reactivation_conflict_fix.sql.
-- The conflict query intentionally ignores every row in the current team.

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

  select * into v_team
  from teams
  where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
  end if;

  if not exists(
    select 1
    from team_members
    where team_id = p_team_id
      and profile_id = v_profile_id
      and role = 'leader'
      and is_active = true
      and removed_at is null
  ) then
    raise exception 'only team leader can reactivate members';
  end if;

  select * into v_member
  from team_members
  where id = p_member_id
    and team_id = p_team_id
    and removed_at is null;
  if not found then
    raise exception 'member not found';
  end if;

  if v_member.profile_id is not null then
    select phone_number into v_phone
    from profiles
    where id = v_member.profile_id;
  else
    select phone_number into v_phone
    from external_students
    where id = v_member.external_student_id;
  end if;

  if v_phone is null then
    raise exception 'member phone not found';
  end if;

  if exists(
    select 1
    from teams t
    join team_members tm on tm.team_id = t.id
    left join profiles p on p.id = tm.profile_id
    left join external_students es on es.id = tm.external_student_id
    where t.id <> v_member.team_id
      and tm.id <> v_member.id
      and t.is_active = true
      and t.team_type = v_team.team_type
      and tm.is_active = true
      and tm.removed_at is null
      and coalesce(p.phone_number, es.phone_number) = v_phone
  ) then
    raise exception 'هذا الطالب موجود في فريق من نفس النوع';
  end if;

  update team_members
  set is_active      = true,
      deactivated_at = null,
      updated_at     = now()
  where id = p_member_id
    and team_id = p_team_id
    and removed_at is null;

  if v_team.current_position is null
     or v_team.current_position = v_team.last_completed_position
     or not exists (
       select 1
       from team_members tm
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

grant execute on function public.reactivate_team_member(text, uuid, uuid) to anon;
