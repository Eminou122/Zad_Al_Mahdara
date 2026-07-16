-- Gate 53.1: Student Directory Backend Foundation
-- Backend-only, local until explicitly applied. Adds one privacy-safe read RPC.
-- The directory exposes active registered profiles and public memberships only.
-- It does not expand messaging: contact targets are only teams where the
-- existing send_team_leader_message contract would authorize the caller.

create or replace function public.get_student_directory(
  p_session_token      text,
  p_query              text default null,
  p_after_sort_name    text default null,
  p_after_profile_id   uuid default null,
  p_limit              integer default 30
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id         uuid;
  v_query              text;
  v_escaped_query      text;
  v_after_sort_name    text;
  v_limit              int;
  v_items              jsonb;
  v_has_more           boolean;
  v_last_sort_name     text;
  v_last_profile_id    uuid;
  v_next_cursor        jsonb := null;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);

  if (p_after_sort_name is null) <> (p_after_profile_id is null) then
    raise exception 'invalid directory cursor';
  end if;
  if p_after_sort_name is not null and nullif(trim(p_after_sort_name), '') is null then
    raise exception 'invalid directory cursor';
  end if;

  v_query := nullif(trim(coalesce(p_query, '')), '');
  if v_query is not null and length(v_query) > 100 then
    raise exception 'directory query too long';
  end if;

  if v_query is not null then
    v_escaped_query := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
  end if;

  v_after_sort_name := case
    when p_after_sort_name is null then null
    else lower(p_after_sort_name)
  end;

  v_limit := greatest(least(coalesce(p_limit, 30), 50), 1);

  with page_profiles as (
    select
      p.id,
      p.display_name,
      lower(p.display_name) as sort_name,
      row_number() over (order by lower(p.display_name), p.id) as rn
    from public.profiles p
    where p.is_active = true
      and p.id <> v_profile_id
      and (
        v_query is null
        or p.display_name ilike '%' || v_escaped_query || '%' escape '\'
      )
      and (
        v_after_sort_name is null
        or (lower(p.display_name), p.id) > (v_after_sort_name, p_after_profile_id)
      )
    order by lower(p.display_name), p.id
    limit v_limit + 1
  ),
  enriched as (
    select
      pp.id,
      pp.display_name,
      pp.sort_name,
      pp.rn,
      coalesce(public_teams.items, '[]'::jsonb) as public_teams,
      coalesce(contact_targets.items, '[]'::jsonb) as contact_targets
    from page_profiles pp
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'team_id',           t.id,
          'team_name',         t.name,
          'team_type',         t.team_type,
          'is_current_leader', live.current_leader_id = pp.id,
          'role',              case
                                 when live.current_leader_id = pp.id then 'leader'
                                 else 'member'
                               end
        )
        order by t.name, t.id
      ) as items
      from public.team_members tm
      join public.teams t on t.id = tm.team_id
      cross join lateral (
        select public.current_team_leader_profile_id(t.id) as current_leader_id
      ) live
      where tm.profile_id = pp.id
        and tm.is_active = true
        and tm.removed_at is null
        and t.is_active = true
        and t.is_public = true
    ) public_teams on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'team_id',   t.id,
          'team_name', t.name,
          'team_type', t.team_type,
          'label',     'مراسلة قائد الفريق'
        )
        order by t.name, t.id
      ) as items
      from public.team_members leader_tm
      join public.teams t on t.id = leader_tm.team_id
      join public.team_members caller_tm on caller_tm.team_id = t.id
      cross join lateral (
        select public.current_team_leader_profile_id(t.id) as current_leader_id
      ) live
      where leader_tm.profile_id = pp.id
        and leader_tm.is_active = true
        and leader_tm.removed_at is null
        and live.current_leader_id = pp.id
        and t.is_active = true
        and t.is_public = true
        and caller_tm.profile_id = v_profile_id
        and caller_tm.is_active = true
        and caller_tm.removed_at is null
        and live.current_leader_id <> v_profile_id
    ) contact_targets on true
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'profile_id',      e.id,
        'display_name',    e.display_name,
        'public_teams',    e.public_teams,
        'contact_targets', e.contact_targets
      )
      order by e.sort_name, e.id
    ) filter (where e.rn <= v_limit), '[]'::jsonb),
    coalesce(bool_or(e.rn > v_limit), false),
    max(e.sort_name) filter (where e.rn = v_limit),
    (array_agg(e.id order by e.sort_name, e.id) filter (where e.rn = v_limit))[1]
  into v_items, v_has_more, v_last_sort_name, v_last_profile_id
  from enriched e;

  if v_has_more and v_last_sort_name is not null and v_last_profile_id is not null then
    v_next_cursor := jsonb_build_object(
      'sort_name',  v_last_sort_name,
      'profile_id', v_last_profile_id
    );
  end if;

  return jsonb_build_object(
    'items',       v_items,
    'has_more',    v_has_more,
    'next_cursor', v_next_cursor
  );
end;
$$;

revoke all on function public.get_student_directory(text, text, text, uuid, integer) from public;
revoke all on function public.get_student_directory(text, text, text, uuid, integer) from authenticated;
grant execute on function public.get_student_directory(text, text, text, uuid, integer) to anon;
