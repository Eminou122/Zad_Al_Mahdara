-- Gate 43.1: Team Member Candidates RPC
-- Apply manually: Supabase Dashboard → SQL Editor → Run
-- Additive-only. Does NOT modify add_team_member, team_phone_conflicts_same_type,
-- search_students_for_team, external-student flow, or any other existing RPC.
--
-- Purpose: let the Add Member screen show every active app account up front
-- (not just search results) with a precomputed status, so a leader sees
-- "already in this team" / "conflicts with another team of the same type"
-- before tapping add, instead of discovering it from a rejected add_team_member
-- call. add_team_member remains the sole enforcement point — this RPC is
-- read-only and must never be the only thing standing between a conflict and
-- an insert.
--
-- Conflict computation intentionally mirrors add_team_member's existing rules
-- byte-for-byte in shape (see 011_external_students_foundation.sql):
--   already_in_current_team: team_id = p_team_id and removed_at is null
--     (no is_active filter — matches add_team_member's own duplicate check,
--     so a deactivated-but-not-removed member still shows as "already added"
--     rather than "available").
--   conflict_same_category: team_id <> p_team_id and same team_type and
--     is_active = true and removed_at is null (matches
--     team_phone_conflicts_same_type exactly — only a currently-active
--     membership elsewhere counts as a conflict).
--   Both match by phone number (coalesce(profiles.phone_number,
--     external_students.phone_number)), not profile_id, so a registered
--     profile and an external_student representing the same person are
--     treated as one identity, exactly like the existing RPCs.

create or replace function public.get_team_member_candidates(
  p_session_token text,
  p_team_id       uuid,
  p_query         text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_team       teams%rowtype;
  v_query      text;
  v_result     jsonb;
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
    raise exception 'only team leader can view member candidates';
  end if;

  v_query := nullif(trim(coalesce(p_query, '')), '');

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'profile_id',              c.id,
      'display_name',            c.display_name,
      'phone_masked',            c.phone_masked,
      'is_active',               c.is_active,
      'already_in_current_team', c.already_in_current_team,
      'conflicting_team_id',     c.conflicting_team_id,
      'conflicting_team_name',   c.conflicting_team_name,
      'conflicting_team_type',   c.conflicting_team_type,
      'can_add',                 c.can_add,
      'status',                  c.status
    ) order by c.display_name, c.id
  ), '[]'::jsonb) into v_result
  from (
    select
      base.*,
      (not base.already_in_current_team and base.conflicting_team_id is null) as can_add,
      case
        when base.already_in_current_team then 'already_added'
        when base.conflicting_team_id is not null then 'conflict_same_category'
        else 'available'
      end as status
    from (
      select
        p.id,
        p.display_name,
        p.phone_masked,
        p.is_active,
        exists(
          select 1
          from team_members tm
          left join profiles p2 on p2.id = tm.profile_id
          left join external_students es on es.id = tm.external_student_id
          where tm.team_id = p_team_id
            and tm.removed_at is null
            and coalesce(p2.phone_number, es.phone_number) = p.phone_number
        ) as already_in_current_team,
        cf.team_id   as conflicting_team_id,
        cf.team_name as conflicting_team_name,
        cf.team_type as conflicting_team_type
      from profiles p
      left join lateral (
        select t.id as team_id, t.name as team_name, t.team_type as team_type
        from teams t
        join team_members tm on tm.team_id = t.id
        left join profiles p2 on p2.id = tm.profile_id
        left join external_students es on es.id = tm.external_student_id
        where t.id <> p_team_id
          and t.is_active = true
          and t.team_type = v_team.team_type
          and tm.is_active = true
          and tm.removed_at is null
          and coalesce(p2.phone_number, es.phone_number) = p.phone_number
        limit 1
      ) cf on true
      where p.is_active = true
        and (v_query is null
             or p.display_name ilike '%' || v_query || '%'
             or p.phone_masked  ilike '%' || v_query || '%')
      order by p.display_name, p.id
      limit 200
    ) base
  ) c;

  return v_result;
end;
$$;

grant execute on function public.get_team_member_candidates(text, uuid, text) to anon;
