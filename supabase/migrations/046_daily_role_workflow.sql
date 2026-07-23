-- Gate 3: daily role workflow, decoupled from the shopping list.
-- Extends team_turns (same rotation cursor/position picker as Gate ~26-28,
-- no new algorithm) with a two-step completion: the assigned member marks
-- their part done, then the leader finalizes. Adds a secure one-time public
-- link so a manual (no-account) member can confirm from a WhatsApp message
-- without logging in.

alter table public.team_turns add column if not exists meal_type text null;
alter table public.team_turns add column if not exists member_completed_at timestamptz null;
alter table public.team_turns add column if not exists member_completed_by uuid null references public.profiles(id) on delete set null;
alter table public.team_turns add column if not exists completion_source text null
  check (completion_source in ('account_member','manual_link','leader_fallback'));
alter table public.team_turns add column if not exists finalized_at timestamptz null;
alter table public.team_turns add column if not exists finalized_by uuid null references public.profiles(id) on delete set null;

-- ─── Secure one-time public confirmation link (manual members) ─────────────
create table public.team_role_confirmation_tokens (
  id          uuid primary key default gen_random_uuid(),
  turn_id     uuid not null references public.team_turns(id) on delete cascade,
  team_id     uuid not null references public.teams(id) on delete cascade,
  member_id   uuid not null references public.team_members(id) on delete cascade,
  token_hash  text not null unique,
  expires_at  timestamptz not null,
  used_at     timestamptz null,
  created_at  timestamptz not null default now(),
  created_by  uuid not null references public.profiles(id) on delete restrict
);
create index team_role_confirmation_tokens_turn_idx on public.team_role_confirmation_tokens(turn_id);
alter table public.team_role_confirmation_tokens enable row level security;
revoke all on public.team_role_confirmation_tokens from public, anon, authenticated;

-- Gate 37 coupled the shared turn row to shopping-list/report completion.
-- A turn now represents the daily meal role, so shopping remains optional and
-- its own report validation remains untouched.
create or replace function public.enforce_nonempty_shopping_turn()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
begin
  return new;
end;
$$;

-- ─── A. start_daily_role ─────────────────────────────────────────────────────
-- Wraps the existing, already shopping-list-agnostic ensure_today_turn (leader
-- auth, idempotency, and the current_position/last_completed_position picker
-- all reused unchanged) then snapshots meal_type and sends the richer,
-- meal-aware notification Gate 3 requires. Skipped for manual members (they
-- are notified via the WhatsApp link instead).
create or replace function public.start_daily_role(
  p_session_token text,
  p_team_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_team    teams%rowtype;
  v_turn    team_turns%rowtype;
  v_member  team_members%rowtype;
  v_meal    text;
begin
  perform ensure_today_turn(p_session_token, p_team_id);

  select * into v_team from teams where id = p_team_id;
  select * into v_turn from team_turns where team_id = p_team_id and turn_date = current_date;

  if v_turn.meal_type is null then
    update team_turns set meal_type = v_team.team_type, updated_at = now() where id = v_turn.id;
  end if;

  select * into v_member from team_members where id = v_turn.member_id;

  if v_member.profile_id is not null then
    v_meal := case v_team.team_type
      when 'breakfast' then 'إفطار'
      when 'lunch'     then 'غداء'
      when 'dinner'    then 'عشاء'
      else 'وجبة'
    end;

    perform create_notification_internal(
      p_recipient_profile_id => v_member.profile_id,
      p_type                 => 'daily_role_assigned',
      p_title                => 'دورك اليوم في فريق ' || v_team.name,
      p_body                 => 'دورك اليوم في تحضير ' || v_meal || ' فريق ' || v_team.name
                                 || ' بتاريخ ' || to_char(v_turn.turn_date, 'YYYY-MM-DD') || '.',
      p_team_id               => p_team_id,
      p_turn_id               => v_turn.id,
      p_action_type           => 'open_team',
      p_action_payload        => jsonb_build_object('team_id', p_team_id),
      p_dedupe_key            => 'daily_role_assigned:' || v_turn.id::text
    );
  end if;

  return get_team_turn_state(p_session_token, p_team_id);
end;
$$;

-- ─── B. member_complete_daily_role ──────────────────────────────────────────
create or replace function public.member_complete_daily_role(
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
  v_member     team_members%rowtype;
  v_team       teams%rowtype;
  v_leader_id  uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_turn from team_turns where id = p_turn_id for update;
  if not found then raise exception 'turn not found'; end if;

  select * into v_member from team_members where id = v_turn.member_id;
  if not found or v_member.profile_id is null or v_member.profile_id <> v_profile_id then
    raise exception 'العضو المكلف اليوم فقط يمكنه تأكيد الإكمال';
  end if;

  if v_turn.status <> 'pending' then raise exception 'الدور غير نشط'; end if;
  if v_turn.member_completed_at is not null then raise exception 'تم تسجيل الإكمال مسبقاً'; end if;

  update team_turns
  set member_completed_at = now(),
      member_completed_by = v_profile_id,
      completion_source   = 'account_member',
      updated_at          = now()
  where id = p_turn_id;

  select * into v_team from teams where id = v_turn.team_id;

  select tm.profile_id into v_leader_id
  from team_members tm
  where tm.team_id = v_turn.team_id and tm.role = 'leader' and tm.is_active and tm.removed_at is null
  limit 1;

  if v_leader_id is not null then
    perform create_notification_internal(
      p_recipient_profile_id => v_leader_id,
      p_type                 => 'daily_role_member_completed',
      p_title                => 'اكتمل تحضير ' || coalesce(v_team.name, ''),
      p_body                 => coalesce((select display_name from profiles where id = v_profile_id), 'العضو')
                                 || ' أكد إكمال دوره اليوم في فريق ' || coalesce(v_team.name, ''),
      p_team_id               => v_turn.team_id,
      p_turn_id               => v_turn.id,
      p_action_type           => 'open_team',
      p_action_payload        => jsonb_build_object('team_id', v_turn.team_id),
      p_dedupe_key            => 'daily_role_member_completed:' || v_turn.id::text
    );
  end if;

  return get_team_turn_state(p_session_token, v_turn.team_id);
end;
$$;

-- ─── C. leader_fallback_complete_daily_role ─────────────────────────────────
create or replace function public.leader_fallback_complete_daily_role(
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
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_turn from team_turns where id = p_turn_id for update;
  if not found then raise exception 'turn not found'; end if;

  if not exists(
    select 1 from team_members
    where team_id = v_turn.team_id and profile_id = v_profile_id
      and role = 'leader' and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه هذا الإجراء';
  end if;

  if v_turn.status <> 'pending' then raise exception 'الدور غير نشط'; end if;
  if v_turn.member_completed_at is not null then raise exception 'تم تسجيل الإكمال مسبقاً'; end if;
  if v_turn.started_at is null or now() < v_turn.started_at + interval '20 minutes' then
    raise exception 'لا يمكن التأكيد نيابةً عن العضو قبل مرور 20 دقيقة';
  end if;

  update team_turns
  set member_completed_at = now(),
      member_completed_by = v_profile_id,
      completion_source   = 'leader_fallback',
      updated_at          = now()
  where id = p_turn_id;

  return get_team_turn_state(p_session_token, v_turn.team_id);
end;
$$;

-- ─── D. leader_finalize_daily_role ──────────────────────────────────────────
-- Same rotation-advance as complete_team_turn (Gate ~34), minus the shopping-
-- report gate: the daily role never depends on a purchase list.
create or replace function public.leader_finalize_daily_role(
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

  select * into v_turn from team_turns where id = p_turn_id for update;
  if not found then raise exception 'turn not found'; end if;

  if not exists(
    select 1 from team_members
    where team_id = v_turn.team_id and profile_id = v_profile_id
      and role = 'leader' and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه إكمال الدور';
  end if;

  if v_turn.status <> 'pending' then raise exception 'turn is not pending'; end if;
  if v_turn.member_completed_at is null then
    raise exception 'يجب تأكيد العضو أولاً قبل الإكمال النهائي';
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
      finalized_at = now(),
      finalized_by = v_profile_id,
      completed_at = now(),
      completed_by = v_profile_id,
      updated_at   = now()
  where id = p_turn_id;

  update teams
  set last_completed_position = v_turn.position,
      current_position        = v_next_pos,
      updated_at               = now()
  where id = v_turn.team_id;

  return get_team_turn_state(p_session_token, v_turn.team_id);
end;
$$;

-- ─── E. get_daily_role_whatsapp_link (leader, manual member only) ──────────
create or replace function public.get_daily_role_whatsapp_link(
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
  v_team       teams%rowtype;
  v_member     team_members%rowtype;
  v_es         external_students%rowtype;
  v_token      text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_turn from team_turns where id = p_turn_id;
  if not found then raise exception 'turn not found'; end if;

  select * into v_team from teams where id = v_turn.team_id and is_active = true;
  if not found then raise exception 'team not found'; end if;

  if not exists(
    select 1 from team_members
    where team_id = v_turn.team_id and profile_id = v_profile_id
      and role = 'leader' and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه إرسال رابط التأكيد';
  end if;

  select * into v_member from team_members where id = v_turn.member_id;
  if not found or v_member.external_student_id is null then
    raise exception 'العضو المعني ليس عضواً يدوياً';
  end if;

  select * into v_es from external_students where id = v_member.external_student_id;
  if not found then raise exception 'member not found'; end if;

  if v_turn.status <> 'pending' then raise exception 'الدور غير نشط'; end if;

  -- Only one usable link per turn: drop any unused prior token first.
  delete from team_role_confirmation_tokens where turn_id = p_turn_id and used_at is null;

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into team_role_confirmation_tokens(turn_id, team_id, member_id, token_hash, expires_at, created_by)
  values (p_turn_id, v_turn.team_id, v_turn.member_id, encode(digest(v_token, 'sha256'), 'hex'),
          now() + interval '24 hours', v_profile_id);

  return jsonb_build_object(
    'token',        v_token,
    'expires_at',   now() + interval '24 hours',
    'phone_number', v_es.phone_number,
    'member_name',  v_es.display_name,
    'team_name',    v_team.name,
    'team_type',    v_team.team_type,
    'turn_date',    v_turn.turn_date
  );
end;
$$;

-- ─── F. get_daily_role_public_confirmation (anon, token only, read-only) ───
create or replace function public.get_daily_role_public_confirmation(
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_hash text;
  v_row  record;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return jsonb_build_object('status', 'invalid');
  end if;
  v_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  select t.used_at, t.expires_at, tt.status as turn_status, tt.member_completed_at,
         tt.turn_date, team.name as team_name, team.team_type, es.display_name as member_name
  into v_row
  from team_role_confirmation_tokens t
  join team_turns tt on tt.id = t.turn_id
  join team_members tm on tm.id = t.member_id
  join external_students es on es.id = tm.external_student_id
  join teams team on team.id = t.team_id
  where t.token_hash = v_hash;

  if not found then return jsonb_build_object('status', 'invalid'); end if;
  if v_row.used_at is not null or v_row.member_completed_at is not null then
    return jsonb_build_object('status', 'used');
  end if;
  if v_row.expires_at <= now() then return jsonb_build_object('status', 'expired'); end if;
  if v_row.turn_status <> 'pending' then return jsonb_build_object('status', 'invalid'); end if;

  return jsonb_build_object(
    'status',      'ready',
    'member_name', v_row.member_name,
    'team_name',   v_row.team_name,
    'team_type',   v_row.team_type,
    'turn_date',   v_row.turn_date
  );
end;
$$;

-- ─── G. complete_daily_role_public (anon, token only, one-time mutation) ───
create or replace function public.complete_daily_role_public(
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_hash        text;
  v_row         team_role_confirmation_tokens%rowtype;
  v_turn        team_turns%rowtype;
  v_team        teams%rowtype;
  v_member      team_members%rowtype;
  v_es          external_students%rowtype;
  v_leader_id   uuid;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return jsonb_build_object('status', 'invalid');
  end if;
  v_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  select * into v_row from team_role_confirmation_tokens where token_hash = v_hash for update;
  if not found then return jsonb_build_object('status', 'invalid'); end if;

  select * into v_turn from team_turns where id = v_row.turn_id for update;
  if not found then return jsonb_build_object('status', 'invalid'); end if;

  if v_row.used_at is not null or v_turn.member_completed_at is not null then
    return jsonb_build_object('status', 'used');
  end if;
  if v_row.expires_at <= now() then return jsonb_build_object('status', 'expired'); end if;
  if v_turn.status <> 'pending'
     or v_turn.team_id <> v_row.team_id
     or v_turn.member_id <> v_row.member_id then
    return jsonb_build_object('status', 'invalid');
  end if;

  update team_turns
  set member_completed_at = now(),
      completion_source   = 'manual_link',
      updated_at          = now()
  where id = v_turn.id;

  update team_role_confirmation_tokens set used_at = now() where id = v_row.id;

  select * into v_team from teams where id = v_turn.team_id;
  select * into v_member from team_members where id = v_turn.member_id;
  select * into v_es from external_students where id = v_member.external_student_id;

  select tm.profile_id into v_leader_id
  from team_members tm
  where tm.team_id = v_turn.team_id and tm.role = 'leader' and tm.is_active and tm.removed_at is null
  limit 1;

  if v_leader_id is not null then
    perform create_notification_internal(
      p_recipient_profile_id => v_leader_id,
      p_type                 => 'daily_role_member_completed',
      p_title                => 'اكتمل تحضير ' || coalesce(v_team.name, ''),
      p_body                 => coalesce(v_es.display_name, 'العضو')
                                 || ' أكد إكمال دوره اليوم في فريق ' || coalesce(v_team.name, ''),
      p_team_id               => v_turn.team_id,
      p_turn_id               => v_turn.id,
      p_action_type           => 'open_team',
      p_action_payload        => jsonb_build_object('team_id', v_turn.team_id),
      p_dedupe_key            => 'daily_role_member_completed:' || v_turn.id::text
    );
  end if;

  return jsonb_build_object(
    'status',      'completed',
    'member_name', v_es.display_name,
    'team_name',   v_team.name,
    'team_type',   v_team.team_type,
    'turn_date',   v_turn.turn_date
  );
end;
$$;

-- ─── H. get_team_turn_state — add Gate 3 fields (additive; existing keys
-- unchanged, so Gate 1/2 callers are unaffected) ─────────────────────────────
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
      'id',                     tt.id,
      'turn_date',               tt.turn_date,
      'status',                  tt.status,
      'member_id',                tt.member_id,
      'display_name',             coalesce(p.display_name, es.display_name),
      'position',                 tt.position,
      'completed_at',             tt.completed_at,
      'started_at',                tt.started_at,
      'started_by',                tt.started_by,
      'skipped_at',                tt.skipped_at,
      'skipped_by',                tt.skipped_by,
      'skip_reason',               tt.skip_reason,
      'meal_type',                 tt.meal_type,
      'member_kind',               case when tm.external_student_id is null then 'account' else 'external' end,
      'has_account',               tm.profile_id is not null,
      'member_completed_at',       tt.member_completed_at,
      'completion_source',         tt.completion_source,
      'member_completed_by_name',  cp.display_name,
      'finalized_at',              tt.finalized_at,
      'finalized_by_name',         fp.display_name
    )
  into v_today_turn
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  left join profiles cp on cp.id = tt.member_completed_by
  left join profiles fp on fp.id = tt.finalized_by
  where tt.team_id = p_team_id and tt.turn_date = v_today
  limit 1;

  select jsonb_build_object(
      'id',           tt.id, 'turn_date', tt.turn_date, 'status', tt.status
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
      'id',                       tt.id,
      'turn_date',                 tt.turn_date,
      'status',                    tt.status,
      'member_id',                 tt.member_id,
      'display_name',              coalesce(p.display_name, es.display_name),
      'position',                  tt.position,
      'completed_at',              tt.completed_at,
      'started_at',                 tt.started_at,
      'started_by',                 tt.started_by,
      'skipped_at',                 tt.skipped_at,
      'skipped_by',                 tt.skipped_by,
      'skip_reason',                tt.skip_reason,
      'meal_type',                  tt.meal_type,
      'member_kind',                case when tm.external_student_id is null then 'account' else 'external' end,
      'has_account',                tm.profile_id is not null,
      'member_completed_at',        tt.member_completed_at,
      'completion_source',          tt.completion_source,
      'member_completed_by_name',   cp.display_name,
      'finalized_at',               tt.finalized_at,
      'finalized_by_name',          fp.display_name
    )
  into v_last_done
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  left join profiles cp on cp.id = tt.member_completed_by
  left join profiles fp on fp.id = tt.finalized_by
  where tt.team_id = p_team_id and tt.status = 'completed'
  order by tt.turn_date desc
  limit 1;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',                       sub.id,
      'turn_date',                 sub.turn_date,
      'status',                    sub.status,
      'member_id',                 sub.member_id,
      'display_name',              coalesce(p.display_name, es.display_name),
      'position',                  sub.position,
      'completed_at',              sub.completed_at,
      'started_at',                 sub.started_at,
      'started_by',                 sub.started_by,
      'skipped_at',                 sub.skipped_at,
      'skipped_by',                 sub.skipped_by,
      'skip_reason',                sub.skip_reason,
      'meal_type',                  sub.meal_type,
      'member_kind',                case when tm.external_student_id is null then 'account' else 'external' end,
      'has_account',                tm.profile_id is not null,
      'member_completed_at',        sub.member_completed_at,
      'completion_source',          sub.completion_source,
      'member_completed_by_name',   cp.display_name,
      'finalized_at',               sub.finalized_at,
      'finalized_by_name',          fp.display_name
    ) order by sub.turn_date desc
  ), '[]'::jsonb) into v_history
  from (
    select tt.id, tt.turn_date, tt.status, tt.member_id, tt.position,
           tt.completed_at, tt.started_at, tt.started_by, tt.skipped_at,
           tt.skipped_by, tt.skip_reason, tt.meal_type, tt.member_completed_at,
           tt.completion_source, tt.member_completed_by, tt.finalized_at, tt.finalized_by
    from team_turns tt
    where tt.team_id = p_team_id
    order by tt.turn_date desc
    limit 20
  ) sub
  join team_members tm on tm.id = sub.member_id
  left join profiles p on p.id = tm.profile_id
  left join external_students es on es.id = tm.external_student_id
  left join profiles cp on cp.id = sub.member_completed_by
  left join profiles fp on fp.id = sub.finalized_by;

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

-- ─── Grants: RPC-only, anon-only (matches every RPC in this project) ───────
revoke all on function public.start_daily_role(text,uuid) from public, authenticated;
grant execute on function public.start_daily_role(text,uuid) to anon;

revoke all on function public.member_complete_daily_role(text,uuid) from public, authenticated;
grant execute on function public.member_complete_daily_role(text,uuid) to anon;

revoke all on function public.leader_fallback_complete_daily_role(text,uuid) from public, authenticated;
grant execute on function public.leader_fallback_complete_daily_role(text,uuid) to anon;

revoke all on function public.leader_finalize_daily_role(text,uuid) from public, authenticated;
grant execute on function public.leader_finalize_daily_role(text,uuid) to anon;

revoke all on function public.get_daily_role_whatsapp_link(text,uuid) from public, authenticated;
grant execute on function public.get_daily_role_whatsapp_link(text,uuid) to anon;

revoke all on function public.get_daily_role_public_confirmation(text) from public, authenticated;
grant execute on function public.get_daily_role_public_confirmation(text) to anon;

revoke all on function public.complete_daily_role_public(text) from public, authenticated;
grant execute on function public.complete_daily_role_public(text) to anon;
