-- Gate 039: public, open teams for the custom-session client.
-- Availability is exactly active + public + open. Member count is display-only
-- and never changes eligibility.

create or replace function public.get_available_public_teams(
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_items jsonb;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'team_id', t.id,
        'name', t.name,
        'team_type', t.team_type,
        'note', t.note,
        'leader_display_name', leader.display_name,
        'member_count', (
          select count(*)
          from public.team_members tm
          where tm.team_id = t.id
            and tm.is_active = true
            and tm.removed_at is null
        ),
        'is_current_member', exists (
          select 1
          from public.team_members tm
          where tm.team_id = t.id
            and tm.profile_id = v_profile_id
            and tm.is_active = true
            and tm.removed_at is null
        )
      )
      order by t.name, t.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.teams t
  left join lateral (
    select public.current_team_leader_profile_id(t.id) as profile_id
  ) live_leader on true
  left join public.profiles leader
    on leader.id = live_leader.profile_id
   and leader.is_active = true
  where t.is_active = true
    and t.is_public = true
    and t.status = 'open';

  return jsonb_build_object('items', v_items);
end;
$$;

-- One-way pre-membership contact. It creates only a leader notification.
create or replace function public.contact_available_team_leader(
  p_session_token text,
  p_team_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_team public.teams%rowtype;
  v_body text;
  v_caller_display_name text;
  v_leader_id uuid;
  v_dedupe_key text;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  v_body := btrim(coalesce(p_body, ''));

  if p_team_id is null then
    raise exception 'team unavailable for contact';
  end if;

  if char_length(v_body) < 1 or char_length(v_body) > 500 then
    raise exception 'invalid contact message';
  end if;

  select t.*
  into v_team
  from public.teams t
  where t.id = p_team_id
    and t.is_active = true
    and t.is_public = true
    and t.status = 'open'
  for update;

  if not found then
    raise exception 'team unavailable for contact';
  end if;

  if exists (
    select 1
    from public.team_members tm
    where tm.team_id = v_team.id
      and tm.profile_id = v_profile_id
      and tm.is_active = true
      and tm.removed_at is null
  ) then
    raise exception 'team unavailable for contact';
  end if;

  v_leader_id := public.current_team_leader_profile_id(v_team.id);

  if v_leader_id is null
     or v_leader_id = v_profile_id
     or not exists (
       select 1
       from public.profiles p
       where p.id = v_leader_id
         and p.is_active = true
     ) then
    raise exception 'team unavailable for contact';
  end if;

  select p.display_name
  into v_caller_display_name
  from public.profiles p
  where p.id = v_profile_id;

  -- ponytail: hourly dedupe only; add a dedicated abuse policy if product needs more.
  v_dedupe_key := 'available-team-contact:'
    || v_team.id::text || ':' || v_profile_id::text || ':'
    || to_char(date_trunc('hour', now() at time zone 'utc'), 'YYYYMMDDHH24');

  perform public.create_notification_internal(
    p_recipient_profile_id => v_leader_id,
    p_type => 'available_team_contact',
    p_title => 'رسالة من ' || v_caller_display_name,
    p_body => v_body,
    p_team_id => v_team.id,
    p_dedupe_key => v_dedupe_key
  );

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.get_available_public_teams(text) is
  'Custom-session RPC for active, public, open teams. Member count is display-only.';
comment on function public.contact_available_team_leader(text, uuid, text) is
  'Custom-session RPC for one-way pre-membership contact through a leader notification.';

revoke all on function public.get_available_public_teams(text) from public;
revoke all on function public.get_available_public_teams(text) from authenticated;
grant execute on function public.get_available_public_teams(text) to anon;

revoke all on function public.contact_available_team_leader(text, uuid, text) from public;
revoke all on function public.contact_available_team_leader(text, uuid, text) from authenticated;
grant execute on function public.contact_available_team_leader(text, uuid, text) to anon;
