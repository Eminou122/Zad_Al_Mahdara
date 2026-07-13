-- Gate 50.1: Notifications Backend Foundation (backend only, RPC-only access)
-- Adds the notifications table, an internal creation helper, five
-- client-facing RPCs, and wires only the four "safe immediate" events that
-- have no unresolved product dependency (today's turn, turn skipped,
-- shopping report submitted/accepted/rejected). Scheduled notifications
-- (budget/subscription/cron-based) are intentionally deferred to a later
-- sub-gate that adds pg_cron — see the header note before each redefined
-- function below for exactly what changed and why.
--
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run. Not applied by
-- this gate; local-only until explicitly approved.

-- ─── A. notifications table ─────────────────────────────────────────────────

create table public.notifications (
  id                    uuid        primary key default gen_random_uuid(),
  recipient_profile_id  uuid        not null references public.profiles(id) on delete cascade,
  type                  text        not null,
  title                 text        not null,
  body                  text        not null,
  team_id               uuid        null references public.teams(id) on delete cascade,
  turn_id               uuid        null references public.team_turns(id) on delete cascade,
  shopping_report_id    uuid        null references public.team_shopping_reports(id) on delete cascade,
  action_type           text        null,
  action_payload        jsonb       null,
  dedupe_key            text        null,
  is_read               boolean     not null default false,
  read_at               timestamptz null,
  created_at            timestamptz not null default now(),
  archived_at           timestamptz null,
  constraint notifications_title_length_check
    check (length(trim(title)) between 1 and 120),
  constraint notifications_body_length_check
    check (length(trim(body)) between 1 and 500),
  constraint notifications_type_length_check
    check (length(trim(type)) between 1 and 80),
  constraint notifications_action_type_length_check
    check (action_type is null or length(trim(action_type)) between 1 and 80),
  constraint notifications_dedupe_key_length_check
    check (dedupe_key is null or length(trim(dedupe_key)) between 1 and 200),
  constraint notifications_read_consistency_check check (
    (is_read = false and read_at is null) or
    (is_read = true  and read_at is not null)
  )
);

create unique index notifications_dedupe_key_uidx
  on public.notifications(dedupe_key)
  where dedupe_key is not null;

create index notifications_recipient_created_idx
  on public.notifications(recipient_profile_id, created_at desc);

create index notifications_recipient_unread_created_idx
  on public.notifications(recipient_profile_id, is_read, created_at desc);

create index notifications_team_idx
  on public.notifications(team_id)
  where team_id is not null;

create index notifications_turn_idx
  on public.notifications(turn_id)
  where turn_id is not null;

create index notifications_shopping_report_idx
  on public.notifications(shopping_report_id)
  where shopping_report_id is not null;

alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;

-- ─── B. create_notification_internal ────────────────────────────────────────
-- Internal-only side-effect helper. Not callable from Flutter. Every writer
-- below goes through this so the dedupe/idempotency behavior lives in one
-- place instead of being reimplemented at each call site.

create or replace function public.create_notification_internal(
  p_recipient_profile_id uuid,
  p_type                 text,
  p_title                text,
  p_body                 text,
  p_team_id              uuid default null,
  p_turn_id              uuid default null,
  p_shopping_report_id   uuid default null,
  p_action_type          text default null,
  p_action_payload       jsonb default null,
  p_dedupe_key           text default null
) returns uuid
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_type        text;
  v_title       text;
  v_body        text;
  v_action_type text;
  v_dedupe_key  text;
  v_id          uuid;
begin
  if not exists(
    select 1 from profiles
    where id = p_recipient_profile_id and is_active = true
  ) then
    raise exception 'recipient not found';
  end if;

  v_type        := nullif(trim(coalesce(p_type, '')), '');
  v_title       := nullif(trim(coalesce(p_title, '')), '');
  v_body        := nullif(trim(coalesce(p_body, '')), '');
  v_action_type := nullif(trim(coalesce(p_action_type, '')), '');
  v_dedupe_key  := nullif(trim(coalesce(p_dedupe_key, '')), '');

  if v_type is null then raise exception 'type is required'; end if;
  if v_title is null then raise exception 'title is required'; end if;
  if v_body is null then raise exception 'body is required'; end if;

  insert into notifications(
    recipient_profile_id, type, title, body, team_id, turn_id, shopping_report_id,
    action_type, action_payload, dedupe_key
  ) values (
    p_recipient_profile_id, v_type, v_title, v_body, p_team_id, p_turn_id, p_shopping_report_id,
    v_action_type, p_action_payload, v_dedupe_key
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing
  returning id into v_id;

  if v_id is null and v_dedupe_key is not null then
    select id into v_id from notifications where dedupe_key = v_dedupe_key;
  end if;

  return v_id;
end;
$$;

-- Internal-only — not reachable from Flutter under any role.
revoke execute on function public.create_notification_internal(uuid, text, text, text, uuid, uuid, uuid, text, jsonb, text) from public;
revoke execute on function public.create_notification_internal(uuid, text, text, text, uuid, uuid, uuid, text, jsonb, text) from anon;
revoke execute on function public.create_notification_internal(uuid, text, text, text, uuid, uuid, uuid, text, jsonb, text) from authenticated;

-- ─── C. get_my_notifications ─────────────────────────────────────────────────
-- Fetches one extra row past the requested page (limit+1) to compute
-- has_more without a second count query; the (limit+1)th row is trimmed
-- back off before returning.

create or replace function public.get_my_notifications(
  p_session_token text,
  p_limit         integer default 50,
  p_before        timestamptz default null,
  p_unread_only   boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id   uuid;
  v_limit        int;
  v_items        jsonb;
  v_has_more     boolean;
  v_unread_count integer;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  v_limit := greatest(least(coalesce(p_limit, 50), 100), 1);

  select count(*) into v_unread_count
  from notifications
  where recipient_profile_id = v_profile_id
    and archived_at is null
    and is_read = false;

  select
    coalesce(jsonb_agg(t.item order by t.created_at desc) filter (where t.rn <= v_limit), '[]'::jsonb),
    coalesce(bool_or(t.rn > v_limit), false)
  into v_items, v_has_more
  from (
    select
      n.created_at,
      row_number() over (order by n.created_at desc, n.id desc) as rn,
      jsonb_build_object(
        'id',                 n.id,
        'type',               n.type,
        'title',              n.title,
        'body',               n.body,
        'team_id',            n.team_id,
        'turn_id',             n.turn_id,
        'shopping_report_id', n.shopping_report_id,
        'action_type',        n.action_type,
        'action_payload',     n.action_payload,
        'is_read',            n.is_read,
        'read_at',            n.read_at,
        'created_at',         n.created_at
      ) as item
    from notifications n
    where n.recipient_profile_id = v_profile_id
      and n.archived_at is null
      and (not p_unread_only or n.is_read = false)
      and (p_before is null or n.created_at < p_before)
    order by n.created_at desc, n.id desc
    limit v_limit + 1
  ) t;

  return jsonb_build_object(
    'items',        v_items,
    'unread_count', v_unread_count,
    'has_more',     v_has_more
  );
end;
$$;

-- ─── D. get_my_notification_unread_count ─────────────────────────────────────

create or replace function public.get_my_notification_unread_count(
  p_session_token text
) returns integer
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_count      integer;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select count(*) into v_count
  from notifications
  where recipient_profile_id = v_profile_id
    and archived_at is null
    and is_read = false;

  return v_count;
end;
$$;

-- ─── E. mark_notification_read ───────────────────────────────────────────────

create or replace function public.mark_notification_read(
  p_session_token   text,
  p_notification_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_notif      notifications%rowtype;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_notif
  from notifications
  where id = p_notification_id and recipient_profile_id = v_profile_id;

  if not found then
    raise exception 'notification not found';
  end if;

  if not v_notif.is_read then
    update notifications
    set is_read = true, read_at = now()
    where id = p_notification_id
    returning * into v_notif;
  end if;

  return jsonb_build_object(
    'id',          v_notif.id,
    'is_read',     v_notif.is_read,
    'read_at',     v_notif.read_at,
    'archived_at', v_notif.archived_at
  );
end;
$$;

-- ─── F. mark_all_notifications_read ──────────────────────────────────────────

create or replace function public.mark_all_notifications_read(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id    uuid;
  v_updated_count integer;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  with updated as (
    update notifications
    set is_read = true, read_at = now()
    where recipient_profile_id = v_profile_id
      and archived_at is null
      and is_read = false
    returning id
  )
  select count(*) into v_updated_count from updated;

  return jsonb_build_object(
    'updated_count', v_updated_count,
    'unread_count',  0
  );
end;
$$;

-- ─── G. archive_notification ─────────────────────────────────────────────────

create or replace function public.archive_notification(
  p_session_token   text,
  p_notification_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_notif      notifications%rowtype;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_notif
  from notifications
  where id = p_notification_id and recipient_profile_id = v_profile_id;

  if not found then
    raise exception 'notification not found';
  end if;

  if v_notif.archived_at is null then
    update notifications
    set archived_at = now()
    where id = p_notification_id
    returning * into v_notif;
  end if;

  return jsonb_build_object(
    'id',          v_notif.id,
    'archived_at', v_notif.archived_at
  );
end;
$$;

-- ─── H. ensure_today_turn ─────────────────────────────────────────────────────
-- Same (text, uuid) signature and return value as Gate 49.1 (026). Only
-- addition: when a *new* turn row is inserted, notify the responsible
-- member. The early-return branch (today's turn already exists) is
-- untouched, so a repeated call never re-notifies. External-student
-- members (no profile_id) have no account to notify, so they're skipped
-- rather than raising. The recipient's profile.is_active is checked here,
-- before calling the helper, so a deactivated member's rotation position
-- (team_members.is_active is independent of profiles.is_active) can never
-- turn a missing/inactive-recipient validation inside the helper into an
-- aborted turn-creation transaction — notification creation stays a
-- side effect only, never a gate on the core workflow.

create or replace function public.ensure_today_turn(
  p_session_token text,
  p_team_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id           uuid;
  v_team                 teams%rowtype;
  v_today                date := current_date;
  v_pick_mid             uuid;
  v_pick_pos             int;
  v_anchor               int;
  v_new_turn_id          uuid;
  v_recipient_profile_id uuid;
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

  insert into team_turns (
    team_id, member_id, turn_date, position, status, started_at, started_by
  ) values (
    p_team_id, v_pick_mid, v_today, v_pick_pos, 'pending', now(), v_profile_id
  )
  returning id into v_new_turn_id;

  select tm.profile_id into v_recipient_profile_id
  from team_members tm
  where tm.id = v_pick_mid;

  if v_recipient_profile_id is not null and exists(
    select 1 from profiles where id = v_recipient_profile_id and is_active = true
  ) then
    perform create_notification_internal(
      p_recipient_profile_id => v_recipient_profile_id,
      p_type                 => 'team_turn_today',
      p_title                => 'دورك اليوم',
      p_body                 => 'دورك اليوم في فريق ' || v_team.name,
      p_team_id              => p_team_id,
      p_turn_id              => v_new_turn_id,
      p_action_type          => 'open_team',
      p_action_payload       => jsonb_build_object('team_id', p_team_id),
      p_dedupe_key           => 'turn_today:' || v_new_turn_id::text
    );
  end if;

  return get_team_turn_state(p_session_token, p_team_id);
end;
$$;

-- ─── I. skip_missed_team_turn ─────────────────────────────────────────────────
-- Same (text, uuid, uuid, text) signature and behavior as Gate 49.5 (028),
-- including that a leader may skip their own missed turn. Only addition:
-- after a successful skip, notify the original turn-holder (the same
-- profile even when that is the leader). External-student turn-holders
-- (no profile_id) are skipped, same reasoning as ensure_today_turn above.

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
  v_profile_id           uuid;
  v_turn                 team_turns%rowtype;
  v_leader_member        team_members%rowtype;
  v_team_name            text;
  v_next_mid             uuid;
  v_next_pos             int;
  v_reason               text;
  v_recipient_profile_id uuid;
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

  select name into v_team_name from teams where id = p_team_id;

  select tm.profile_id into v_recipient_profile_id
  from team_members tm
  where tm.id = v_turn.member_id;

  if v_recipient_profile_id is not null and exists(
    select 1 from profiles where id = v_recipient_profile_id and is_active = true
  ) then
    perform create_notification_internal(
      p_recipient_profile_id => v_recipient_profile_id,
      p_type                 => 'team_turn_skipped',
      p_title                => 'تم تخطّي الدور',
      p_body                 => 'تم تخطي دورك بتاريخ ' || to_char(v_turn.turn_date, 'YYYY-MM-DD') || ' في فريق ' || v_team_name,
      p_team_id              => p_team_id,
      p_turn_id              => p_turn_id,
      p_action_type          => 'open_team',
      p_action_payload       => jsonb_build_object('team_id', p_team_id),
      p_dedupe_key           => 'turn_skipped:' || p_turn_id::text
    );
  end if;

  return get_team_turn_state(p_session_token, p_team_id);
end;
$$;

-- ─── J. submit_team_shopping_report ──────────────────────────────────────────
-- Same (text, uuid, date) signature and behavior as Gate 48.1 (025). Only
-- addition: after a successful submission, notify the team's active
-- leader. Gate 50.1R: the dedupe key is report_submit:{report_id}:
-- {submitted_at}, not just {report_id} — team_shopping_reports.id is
-- stable across a reject -> resubmit cycle (submission upserts the same
-- (team_id, report_date) row), so keying on id alone would make a
-- resubmission after rejection collide with the original submit
-- notification's key and never notify the leader again. submitted_at is
-- read back from the upsert's own "returning" clause (v_report), not a
-- fresh now() call, so the key always matches the exact value stored on
-- that row.

create or replace function public.submit_team_shopping_report(
  p_session_token text,
  p_team_id       uuid,
  p_date          date default current_date
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id       uuid;
  v_is_responsible   boolean;
  v_report           team_shopping_reports%rowtype;
  v_missing_required int;
  v_missing_optional int;
  v_team_name        text;
  v_submitter_name    text;
  v_leader_profile_id uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if p_date > current_date then
    raise exception 'لا يمكن الإرسال لتاريخ مستقبلي';
  end if;

  if not exists(select 1 from teams where id = p_team_id and is_active = true) then
    raise exception 'team not found';
  end if;

  select exists(
    select 1
    from team_turns tt
    join team_members tm on tm.id = tt.member_id
    where tt.team_id = p_team_id and tt.turn_date = p_date
      and tm.profile_id = v_profile_id
  ) into v_is_responsible;

  if not v_is_responsible then
    raise exception 'المسؤول عن هذا اليوم فقط يمكنه إرسال القائمة';
  end if;

  select * into v_report
  from team_shopping_reports
  where team_id = p_team_id and report_date = p_date;

  if found and v_report.leader_status in ('pending', 'accepted') then
    raise exception 'تم إرسال القائمة بالفعل';
  end if;

  select count(*) into v_missing_required
  from team_shopping_items i
  left join team_shopping_item_occurrences occ
    on occ.team_shopping_item_id = i.id and occ.occurrence_date = p_date
  where i.team_id = p_team_id and i.is_active = true and i.is_required = true
    and (occ.id is null or occ.status <> 'bought');

  if v_missing_required > 0 then
    raise exception 'يجب شراء كل العناصر الأساسية قبل الإرسال';
  end if;

  select count(*) into v_missing_optional
  from team_shopping_items i
  left join team_shopping_item_occurrences occ
    on occ.team_shopping_item_id = i.id and occ.occurrence_date = p_date
  where i.team_id = p_team_id and i.is_active = true and i.is_required = false
    and occ.id is null;

  if v_missing_optional > 0 then
    raise exception 'يجب تحديد حالة كل عنصر اختياري (تم الشراء أو سبب عدم الشراء)';
  end if;

  insert into team_shopping_reports(
    team_id, report_date, responsible_profile_id, submitted_at, submitted_by, leader_status
  ) values (
    p_team_id, p_date, v_profile_id, now(), v_profile_id, 'pending'
  )
  on conflict (team_id, report_date)
  do update set
    responsible_profile_id = excluded.responsible_profile_id,
    submitted_at            = now(),
    submitted_by            = v_profile_id,
    leader_status           = 'pending',
    leader_reviewed_at      = null,
    leader_reviewed_by      = null,
    leader_note             = null,
    updated_at              = now()
  returning * into v_report;

  select tm.profile_id into v_leader_profile_id
  from team_members tm
  where tm.team_id = p_team_id
    and tm.role = 'leader'
    and tm.is_active = true
    and tm.removed_at is null
  limit 1;

  if v_leader_profile_id is not null and exists(
    select 1 from profiles where id = v_leader_profile_id and is_active = true
  ) then
    select name into v_team_name from teams where id = p_team_id;
    select display_name into v_submitter_name from profiles where id = v_profile_id;

    perform create_notification_internal(
      p_recipient_profile_id => v_leader_profile_id,
      p_type                 => 'shopping_report_submitted',
      p_title                => 'تم إرسال تقرير التسوق',
      p_body                 => coalesce(v_submitter_name, 'أحد الأعضاء') || ' أرسل تقرير تسوق فريق ' || v_team_name,
      p_team_id              => p_team_id,
      p_shopping_report_id   => v_report.id,
      p_action_type          => 'open_team_shopping',
      p_action_payload       => jsonb_build_object('team_id', p_team_id, 'date', p_date),
      p_dedupe_key           => 'report_submit:' || v_report.id::text || ':' || v_report.submitted_at::text
    );
  end if;

  return get_team_shopping_list(p_session_token, p_team_id, p_date);
end;
$$;

-- ─── K. leader_review_shopping_report ────────────────────────────────────────
-- Same (text, uuid, date, text, text) signature and behavior as Gate 48.1
-- (025), including that rejection reopens marking (unchanged) and that
-- reviewing an already-accepted/rejected report is still not guarded here
-- (that guard belongs with the financial gate that makes acceptance create
-- a real expense row — see Gate 50.0 audit note). Only addition: notify the
-- responsible member on accept/reject. Accept uses dedupe key
-- report_accept:{report_id} (re-accepting the same report cannot
-- double-notify); reject uses report_reject:{report_id}:{reviewed_at} so
-- each distinct rejection produces its own notification.

create or replace function public.leader_review_shopping_report(
  p_session_token text,
  p_team_id       uuid,
  p_date          date,
  p_status        text,
  p_note          text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id    uuid;
  v_report        team_shopping_reports%rowtype;
  v_note          text;
  v_team_name     text;
  v_reviewed_at   timestamptz := now();
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه مراجعة القائمة';
  end if;

  if p_status not in ('accepted', 'rejected') then
    raise exception 'invalid status';
  end if;

  select * into v_report
  from team_shopping_reports
  where team_id = p_team_id and report_date = p_date;

  if not found or v_report.submitted_at is null then
    raise exception 'لم يتم إرسال القائمة بعد';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');
  if p_status = 'rejected' and v_note is null then
    raise exception 'يجب كتابة سبب الرفض';
  end if;
  if v_note is not null and length(v_note) > 300 then
    raise exception 'invalid note';
  end if;

  update team_shopping_reports
  set leader_status      = p_status,
      leader_reviewed_at = v_reviewed_at,
      leader_reviewed_by = v_profile_id,
      leader_note        = v_note,
      updated_at         = v_reviewed_at
  where team_id = p_team_id and report_date = p_date;

  if exists(
    select 1 from profiles where id = v_report.responsible_profile_id and is_active = true
  ) then
    select name into v_team_name from teams where id = p_team_id;

    if p_status = 'accepted' then
      perform create_notification_internal(
        p_recipient_profile_id => v_report.responsible_profile_id,
        p_type                 => 'shopping_report_accepted',
        p_title                => 'تم قبول تقرير التسوق',
        p_body                 => 'تم قبول تقرير تسوق فريق ' || v_team_name || ' بتاريخ ' || to_char(p_date, 'YYYY-MM-DD'),
        p_team_id              => p_team_id,
        p_shopping_report_id   => v_report.id,
        p_action_type          => 'open_team_shopping',
        p_action_payload       => jsonb_build_object('team_id', p_team_id, 'date', p_date),
        p_dedupe_key           => 'report_accept:' || v_report.id::text
      );
    else
      perform create_notification_internal(
        p_recipient_profile_id => v_report.responsible_profile_id,
        p_type                 => 'shopping_report_rejected',
        p_title                => 'تم رفض تقرير التسوق',
        p_body                 => 'تم رفض تقرير تسوق فريق ' || v_team_name || coalesce(': ' || v_note, ''),
        p_team_id              => p_team_id,
        p_shopping_report_id   => v_report.id,
        p_action_type          => 'open_team_shopping',
        p_action_payload       => jsonb_build_object('team_id', p_team_id, 'date', p_date),
        p_dedupe_key           => 'report_reject:' || v_report.id::text || ':' || v_reviewed_at::text
      );
    end if;
  end if;

  return get_team_shopping_list(p_session_token, p_team_id, p_date);
end;
$$;

-- ─── L. Grants ────────────────────────────────────────────────────────────────
-- Client-facing notification RPCs are granted to anon (RPC-only access,
-- same convention as every other client entry point). Redefined workflow
-- functions keep their existing grants; re-granted here since create or
-- replace does not change privileges but this matches the project's
-- convention of re-stating grants alongside every redefinition.

grant execute on function public.get_my_notifications(text, integer, timestamptz, boolean) to anon;
grant execute on function public.get_my_notification_unread_count(text) to anon;
grant execute on function public.mark_notification_read(text, uuid) to anon;
grant execute on function public.mark_all_notifications_read(text) to anon;
grant execute on function public.archive_notification(text, uuid) to anon;

grant execute on function public.ensure_today_turn(text, uuid) to anon;
grant execute on function public.skip_missed_team_turn(text, uuid, uuid, text) to anon;
grant execute on function public.submit_team_shopping_report(text, uuid, date) to anon;
grant execute on function public.leader_review_shopping_report(text, uuid, date, text, text) to anon;
