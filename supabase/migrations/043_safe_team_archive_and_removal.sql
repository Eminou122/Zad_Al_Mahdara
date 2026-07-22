-- Safe team lifecycle: archives retain all history; deletion is limited to
-- newly-created teams with no business, operational, or audit dependencies.

alter table public.teams
  add column if not exists archived_at timestamptz null,
  add column if not exists archived_by uuid null references public.profiles(id) on delete restrict,
  add column if not exists archive_reason text null;

alter table public.teams
  add constraint teams_archive_audit_check check (
    (archived_at is null and archived_by is null and archive_reason is null)
    or (archived_at is not null and archived_by is not null
        and (archive_reason is null or length(trim(archive_reason)) between 1 and 300))
  );

create index if not exists teams_archived_by_idx on public.teams(archived_by, archived_at desc)
  where archived_at is not null;

create or replace function public.get_my_teams(p_session_token text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_result jsonb;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'name', t.name, 'team_type', t.team_type, 'is_public', t.is_public,
    'status', t.status, 'leader_name', p.display_name,
    'member_count', (select count(*) from public.team_members tm2 where tm2.team_id=t.id and tm2.removed_at is null),
    'active_member_count', (select count(*) from public.team_members tm2 where tm2.team_id=t.id and tm2.is_active and tm2.removed_at is null),
    'inactive_member_count', (select count(*) from public.team_members tm2 where tm2.team_id=t.id and not tm2.is_active and tm2.removed_at is null),
    'my_role', tm.role, 'is_leader', tm.role='leader' and tm.is_active,
    'is_archived', t.archived_at is not null
  ) order by t.archived_at nulls first, t.created_at desc), '[]'::jsonb) into v_result
  from public.teams t
  join public.team_members tm on tm.team_id=t.id and tm.profile_id=v_profile_id and tm.removed_at is null
  join public.profiles p on p.id=t.leader_id
  where t.is_active or t.archived_at is not null;
  return v_result;
end;
$$;

create or replace function public.get_team_detail(p_session_token text, p_team_id uuid)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare
  v_profile_id uuid; v_team public.teams%rowtype; v_membership public.team_members%rowtype;
  v_is_member boolean := false; v_is_admin boolean := false; v_can_edit boolean := false;
  v_can_manage_lifecycle boolean := false; v_leader_name text; v_members jsonb;
  v_member_count bigint; v_active_member_count bigint; v_inactive_member_count bigint;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select * into v_team from public.teams where id=p_team_id;
  if not found then raise exception 'team not found'; end if;
  select * into v_membership from public.team_members
    where team_id=p_team_id and profile_id=v_profile_id and removed_at is null limit 1;
  v_is_member := found;
  select is_admin into v_is_admin from public.profiles where id=v_profile_id;
  if v_team.archived_at is not null and not (v_is_member or v_is_admin or v_team.leader_id=v_profile_id) then
    raise exception 'team not found or access denied';
  end if;
  if v_team.archived_at is null and not v_team.is_active then raise exception 'team not found'; end if;
  if v_team.archived_at is null and not v_team.is_public and not (v_is_member or v_is_admin) then
    raise exception 'team not found or access denied';
  end if;
  select display_name into v_leader_name from public.profiles where id=v_team.leader_id;
  select count(*), count(*) filter(where is_active), count(*) filter(where not is_active)
    into v_member_count,v_active_member_count,v_inactive_member_count
    from public.team_members where team_id=p_team_id and removed_at is null;
  v_can_edit := v_team.archived_at is null and v_is_member and v_membership.role='leader' and v_membership.is_active;
  v_can_manage_lifecycle := (v_is_admin or (v_is_member and v_membership.role='leader' and v_membership.is_active));
  if v_is_member or v_is_admin or v_team.leader_id=v_profile_id then
    select coalesce(jsonb_agg(jsonb_build_object(
      'member_id',tm.id,'profile_id',tm.profile_id,'external_student_id',tm.external_student_id,
      'display_name',coalesce(p.display_name,es.display_name),'phone_masked',coalesce(p.phone_masked,es.phone_masked),
      'member_kind',case when tm.external_student_id is null then 'account' else 'external' end,
      'has_account',tm.profile_id is not null,'role',tm.role,'position',tm.position,'is_active',tm.is_active,
      'deactivated_at',tm.deactivated_at,'joined_at',tm.joined_at
    ) order by tm.position),'[]'::jsonb) into v_members
    from public.team_members tm left join public.profiles p on p.id=tm.profile_id
      left join public.external_students es on es.id=tm.external_student_id
    where tm.team_id=p_team_id and tm.removed_at is null;
  else v_members := '[]'::jsonb; end if;
  return jsonb_build_object('team',jsonb_build_object(
    'id',v_team.id,'name',v_team.name,'team_type',v_team.team_type,'is_public',v_team.is_public,
    'status',v_team.status,'note',v_team.note,'leader_id',v_team.leader_id,'leader_name',v_leader_name,
    'member_count',v_member_count,'active_member_count',v_active_member_count,'inactive_member_count',v_inactive_member_count,
    'created_at',v_team.created_at,'is_archived',v_team.archived_at is not null
  ),'members',v_members,'can_edit',v_can_edit,'can_manage_lifecycle',v_can_manage_lifecycle,'is_member',v_is_member);
end;
$$;

create or replace function public.archive_team(p_session_token text, p_team_id uuid)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_is_admin boolean; v_team public.teams%rowtype;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select is_admin into v_is_admin from public.profiles where id=v_profile_id;
  select * into v_team from public.teams where id=p_team_id for update;
  if not found or not (v_is_admin or exists(select 1 from public.team_members tm where tm.team_id=p_team_id and tm.profile_id=v_profile_id and tm.role='leader' and tm.is_active and tm.removed_at is null)) then raise exception 'team not available'; end if;
  if v_team.archived_at is null then update public.teams set is_active=false, archived_at=now(), archived_by=v_profile_id, updated_at=now() where id=p_team_id; end if;
  return public.get_team_detail(p_session_token,p_team_id);
end;
$$;

create or replace function public.restore_team(p_session_token text, p_team_id uuid)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_is_admin boolean;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select is_admin into v_is_admin from public.profiles where id=v_profile_id;
  if not exists(select 1 from public.teams t where t.id=p_team_id and t.archived_at is not null)
    or not (v_is_admin or exists(select 1 from public.team_members tm where tm.team_id=p_team_id and tm.profile_id=v_profile_id and tm.role='leader' and tm.is_active and tm.removed_at is null)) then raise exception 'team not available'; end if;
  update public.teams set is_active=true, archived_at=null, archived_by=null, archive_reason=null, updated_at=now() where id=p_team_id;
  return public.get_team_detail(p_session_token,p_team_id);
end;
$$;

create or replace function public.remove_team_permanently(p_session_token text, p_team_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_is_admin boolean; v_team public.teams%rowtype; v_fk record; v_has_dependency boolean; v_reason text := nullif(trim(coalesce(p_reason,'')), '');
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  if v_reason is null or length(v_reason)>300 then raise exception 'invalid removal reason'; end if;
  select is_admin into v_is_admin from public.profiles where id=v_profile_id;
  select * into v_team from public.teams where id=p_team_id for update;
  if not found or not (v_is_admin or exists(select 1 from public.team_members tm where tm.team_id=p_team_id and tm.profile_id=v_profile_id and tm.role='leader' and tm.is_active and tm.removed_at is null)) then raise exception 'team not available'; end if;
  if v_team.archived_at is not null or exists(select 1 from public.team_members tm where tm.team_id=p_team_id and (tm.profile_id is distinct from v_team.leader_id or tm.external_student_id is not null)) then return jsonb_build_object('ok',true,'removed',false,'blocked',true); end if;
  for v_fk in select c.conrelid::regclass as relation, a.attname as column_name from pg_constraint c join unnest(c.conkey) with ordinality k(attnum,n) on true join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum where c.contype='f' and c.confrelid='public.teams'::regclass and c.conrelid <> 'public.team_members'::regclass loop
    execute format('select exists(select 1 from %s where %I=$1)',v_fk.relation,v_fk.column_name) into v_has_dependency using p_team_id;
    if v_has_dependency then return jsonb_build_object('ok',true,'removed',false,'blocked',true); end if;
  end loop;
  delete from public.teams where id=p_team_id;
  return jsonb_build_object('ok',true,'removed',true,'blocked',false);
end;
$$;

revoke all on function public.archive_team(text,uuid) from public, authenticated;
revoke all on function public.restore_team(text,uuid) from public, authenticated;
revoke all on function public.remove_team_permanently(text,uuid,text) from public, authenticated;
grant execute on function public.archive_team(text,uuid) to anon;
grant execute on function public.restore_team(text,uuid) to anon;
grant execute on function public.remove_team_permanently(text,uuid,text) to anon;
grant execute on function public.get_my_teams(text) to anon;
grant execute on function public.get_team_detail(text,uuid) to anon;
