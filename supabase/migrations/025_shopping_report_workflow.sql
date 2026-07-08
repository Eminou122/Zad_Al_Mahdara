-- Gate 48.1: Shopping Report Workflow (backend only)
-- Additive-only. Does NOT modify auth, budget, admin, PIN reset, account
-- settings, or team-membership migrations. Extends the Gate 37-40 shopping
-- checklist (019-022) and adds a single new gate onto complete_team_turn
-- (Gate 6, 004/011).
--
-- Adds: an explicit "not bought + reason" occurrence status (today only
-- "bought" existed, "not bought" was pure row absence), a per-day
-- team_shopping_reports table the responsible member submits and the
-- leader accepts/rejects, and a completion gate so a leader cannot mark
-- today's turn done until that team's shopping report for the turn date is
-- submitted AND accepted. Teams with no active shopping items are never
-- blocked (avoids breaking teams that don't use the shopping list).
--
-- Apply manually: Supabase Dashboard → SQL Editor → Run.
-- Safe to re-apply (if not exists / create or replace / drop-before-replace
-- where a signature gains a parameter, matching Gate 38/40 convention).

-- ─── A. team_shopping_item_occurrences: explicit not_bought + reason ────────
-- Row existence still means "the responsible member made a decision today";
-- absence still means "untouched". What changes is that a negative decision
-- is now itself a row (status='not_bought', reason required) instead of a
-- deleted/never-created row, so a reason can be attached and displayed.
-- Existing 'bought' rows are untouched by this migration (reason stays null).

alter table public.team_shopping_item_occurrences
  add column if not exists reason text null
    check (reason is null or length(trim(reason)) between 1 and 200);

alter table public.team_shopping_item_occurrences
  drop constraint if exists team_shopping_item_occurrences_status_check;

alter table public.team_shopping_item_occurrences
  add constraint team_shopping_item_occurrences_status_check
  check (status in ('bought', 'not_bought'));

alter table public.team_shopping_item_occurrences
  drop constraint if exists team_shopping_item_occurrences_reason_required_check;

alter table public.team_shopping_item_occurrences
  add constraint team_shopping_item_occurrences_reason_required_check
  check (status = 'bought' or reason is not null);

-- ─── B. team_shopping_reports ────────────────────────────────────────────────
-- One row per (team, report_date). Submission upserts this row; leader
-- review updates it in place. Rejection is not a dead end: leader_status
-- can return to 'pending' via a fresh submission (see submit_team_shopping_
-- report below), which is how a rejected report gets reopened for editing.

create table if not exists public.team_shopping_reports (
  id                     uuid        primary key default gen_random_uuid(),
  team_id                uuid        not null references public.teams(id) on delete cascade,
  report_date            date        not null,
  responsible_profile_id uuid        not null references public.profiles(id) on delete restrict,
  submitted_at           timestamptz null,
  submitted_by           uuid        null references public.profiles(id) on delete restrict,
  leader_status          text        not null default 'pending'
                                     check (leader_status in ('pending', 'accepted', 'rejected')),
  leader_reviewed_at     timestamptz null,
  leader_reviewed_by     uuid        null references public.profiles(id) on delete restrict,
  leader_note            text        null
                                     check (leader_note is null or length(trim(leader_note)) between 1 and 300),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (team_id, report_date),
  constraint team_shopping_reports_review_fields_check check (
    (leader_status = 'pending' and leader_reviewed_at is null and leader_reviewed_by is null)
    or
    (leader_status in ('accepted', 'rejected') and leader_reviewed_at is not null and leader_reviewed_by is not null)
  ),
  -- A rejection with no explanation isn't actionable for the responsible
  -- member, so this is a hard constraint, not just an RPC-level check.
  constraint team_shopping_reports_rejected_note_check check (
    leader_status <> 'rejected' or leader_note is not null
  )
);

create index if not exists team_shopping_reports_team_date_idx
  on public.team_shopping_reports(team_id, report_date desc);

alter table public.team_shopping_reports enable row level security;
revoke all on public.team_shopping_reports from anon, authenticated;

-- ─── C. mark_shopping_item_status ────────────────────────────────────────────
-- Gains p_reason (trailing, default null) and an explicit not_bought status.
-- p_date keeps its "default current_date" — the gate brief's listed
-- signature drops that default, but nearly every current Flutter call omits
-- p_date entirely (see team_shopping_service.dart: p_date is only sent "if
-- (date != null)"), so removing the default would break every plain "mark
-- today's item" call. Parameters are matched by name in every existing and
-- new Flutter call (Supabase RPC params are a named JSON map, never
-- positional), so keeping p_bought before p_date in the declared signature
-- is also safe — it does not affect any caller.
--
-- Gate 48.1R backward-compat patch: p_bought=false with a non-empty
-- p_reason is the new explicit "not bought, here's why" path. p_bought=
-- false with no reason is what every pre-Gate-48.2 Flutter build still
-- sends when a user unchecks an item — that case preserves the *old*
-- behavior (delete the occurrence row, i.e. "untouched") instead of
-- raising, so applying this migration cannot break the currently-deployed
-- checkbox UI before Gate 48.2 ships the reason input. This does not weaken
-- submit_team_shopping_report below: an untouched optional item (deleted
-- row) still has no occurrence row, which still blocks submission exactly
-- as before.
--
-- Once a report is submitted and still pending/accepted, marks are locked;
-- a rejected report reopens marking (Gate 48.1 decision).

drop function if exists public.mark_shopping_item_status(text, uuid, uuid, boolean, date);

create or replace function public.mark_shopping_item_status(
  p_session_token text,
  p_team_id       uuid,
  p_item_id       uuid,
  p_bought        boolean,
  p_date          date default current_date,
  p_reason        text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id     uuid;
  v_is_responsible boolean;
  v_report         team_shopping_reports%rowtype;
  v_reason         text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if p_date > current_date then
    raise exception 'لا يمكن التحديد لتاريخ مستقبلي';
  end if;

  if not exists(
    select 1 from team_shopping_items
    where id = p_item_id and team_id = p_team_id and is_active = true
  ) then
    raise exception 'item not found';
  end if;

  select exists(
    select 1
    from team_turns tt
    join team_members tm on tm.id = tt.member_id
    where tt.team_id = p_team_id and tt.turn_date = p_date
      and tm.profile_id = v_profile_id
  ) into v_is_responsible;

  if not v_is_responsible then
    raise exception 'not authorized to mark this item';
  end if;

  select * into v_report
  from team_shopping_reports
  where team_id = p_team_id and report_date = p_date;

  if found and v_report.leader_status in ('pending', 'accepted') then
    raise exception 'تم إرسال القائمة بالفعل، لا يمكن التعديل حتى يرفضها القائد';
  end if;

  if p_bought then
    insert into team_shopping_item_occurrences(
      team_shopping_item_id, occurrence_date, status, reason, marked_by
    ) values (
      p_item_id, p_date, 'bought', null, v_profile_id
    )
    on conflict (team_shopping_item_id, occurrence_date)
    do update set status = 'bought', reason = null,
                  marked_by = excluded.marked_by, marked_at = now();
  else
    v_reason := nullif(trim(coalesce(p_reason, '')), '');

    if v_reason is not null then
      if length(v_reason) > 200 then
        raise exception 'سبب عدم الشراء طويل جداً (الحد الأقصى ٢٠٠ حرف)';
      end if;

      insert into team_shopping_item_occurrences(
        team_shopping_item_id, occurrence_date, status, reason, marked_by
      ) values (
        p_item_id, p_date, 'not_bought', v_reason, v_profile_id
      )
      on conflict (team_shopping_item_id, occurrence_date)
      do update set status = 'not_bought', reason = excluded.reason,
                    marked_by = excluded.marked_by, marked_at = now();
    else
      -- Backward compatibility (Gate 48.1R): no reason supplied — the old
      -- frontend's "unmark" behavior. Delete the row instead of recording
      -- an explicit not_bought decision; this is "untouched", not a
      -- reasoned refusal, and still blocks submission the same way an
      -- untouched item always has.
      delete from team_shopping_item_occurrences
      where team_shopping_item_id = p_item_id and occurrence_date = p_date;
    end if;
  end if;

  return get_team_shopping_list(p_session_token, p_team_id, p_date);
end;
$$;

-- ─── D. submit_team_shopping_report ──────────────────────────────────────────
-- Responsible-member-only. Blocks unless every active required item is
-- bought and every active optional item has a definitive status (bought,
-- or not_bought with a reason — guaranteed non-empty by the table's own
-- check constraint, so only row-absence needs checking here). A prior
-- 'rejected' report is reopened: submitting again resets it to 'pending'
-- and clears the review fields, matching the Gate 48.1 rejection-reopens
-- decision.

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
    updated_at              = now();

  return get_team_shopping_list(p_session_token, p_team_id, p_date);
end;
$$;

-- ─── E. leader_review_shopping_report ────────────────────────────────────────
-- Leader-only. Requires an existing, submitted report. A note is required
-- for rejection (enforced here and, redundantly, by the table constraint
-- above), optional for acceptance.

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
  v_profile_id uuid;
  v_report     team_shopping_reports%rowtype;
  v_note       text;
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
      leader_reviewed_at = now(),
      leader_reviewed_by = v_profile_id,
      leader_note        = v_note,
      updated_at         = now()
  where team_id = p_team_id and report_date = p_date;

  return get_team_shopping_list(p_session_token, p_team_id, p_date);
end;
$$;

-- ─── F. get_team_shopping_list ───────────────────────────────────────────────
-- Same input signature as Gate 40.1. Adds a "report" object (submission/
-- review state + can_submit/can_review/can_edit_marks/
-- completion_blocking_reason) and, per item, "status" ('untouched' |
-- 'bought' | 'not_bought'), "reason", and "marked_by" (uuid). Existing
-- fields — bought, marked_by_name, can_mark, can_edit_list, quantity/price
-- fields — are all unchanged, so the current Flutter client (which reads
-- only the fields it knows) keeps working unmodified until Gate 48.2.

create or replace function public.get_team_shopping_list(
  p_session_token text,
  p_team_id       uuid,
  p_date          date default current_date
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id             uuid;
  v_team                   teams%rowtype;
  v_membership             team_members%rowtype;
  v_is_member              boolean := false;
  v_is_leader              boolean := false;
  v_responsible_profile_id uuid;
  v_responsible_name       text;
  v_responsible            jsonb := null;
  v_can_mark               boolean := false;
  v_items                  jsonb;
  v_report                 team_shopping_reports%rowtype;
  v_report_found           boolean := false;
  v_report_json            jsonb;
  v_submitted_by_name      text;
  v_reviewed_by_name       text;
  v_can_submit             boolean := false;
  v_can_review             boolean := false;
  v_can_edit_marks         boolean := false;
  v_completion_blocking    text := null;
  v_has_active_items       boolean := false;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_team from teams where id = p_team_id and is_active = true;
  if not found then
    raise exception 'team not found';
  end if;

  select * into v_membership
  from team_members
  where team_id = p_team_id and profile_id = v_profile_id
    and is_active = true and removed_at is null;
  v_is_member := found;
  v_is_leader := found and v_membership.role = 'leader';

  if not v_is_member then
    raise exception 'team not found or access denied';
  end if;

  select p.id, p.display_name
  into v_responsible_profile_id, v_responsible_name
  from team_turns tt
  join team_members tm on tm.id = tt.member_id
  join profiles p      on p.id  = tm.profile_id
  where tt.team_id = p_team_id and tt.turn_date = p_date
  limit 1;

  if v_responsible_profile_id is not null then
    v_responsible := jsonb_build_object(
      'id',           v_responsible_profile_id,
      'display_name', v_responsible_name
    );
  end if;

  v_can_mark := v_responsible_profile_id is not null
    and v_responsible_profile_id = v_profile_id;

  select * into v_report
  from team_shopping_reports
  where team_id = p_team_id and report_date = p_date;
  v_report_found := found;

  select exists(
    select 1 from team_shopping_items
    where team_id = p_team_id and is_active = true
  ) into v_has_active_items;

  if v_report_found then
    select p.display_name into v_submitted_by_name
    from profiles p where p.id = v_report.submitted_by;
    select p.display_name into v_reviewed_by_name
    from profiles p where p.id = v_report.leader_reviewed_by;

    v_report_json := jsonb_build_object(
      'submitted_at',            v_report.submitted_at,
      'submitted_by',            v_report.submitted_by,
      'submitted_by_name',       v_submitted_by_name,
      'leader_status',           v_report.leader_status,
      'leader_reviewed_at',      v_report.leader_reviewed_at,
      'leader_reviewed_by',      v_report.leader_reviewed_by,
      'leader_reviewed_by_name', v_reviewed_by_name,
      'leader_note',             v_report.leader_note
    );

    v_can_edit_marks := v_can_mark
      and (v_report.submitted_at is null or v_report.leader_status = 'rejected');
    v_can_submit := v_can_edit_marks;
    v_can_review := v_is_leader
      and v_report.submitted_at is not null and v_report.leader_status = 'pending';
  else
    v_report_json := jsonb_build_object(
      'submitted_at',            null,
      'submitted_by',            null,
      'submitted_by_name',       null,
      'leader_status',           null,
      'leader_reviewed_at',      null,
      'leader_reviewed_by',      null,
      'leader_reviewed_by_name', null,
      'leader_note',             null
    );
    v_can_edit_marks := v_can_mark;
    v_can_submit      := v_can_mark;
    v_can_review       := false;
  end if;

  if v_has_active_items
     and (v_report.submitted_at is null or v_report.leader_status is distinct from 'accepted') then
    v_completion_blocking := 'ينتظر إرسال قائمة التسوق وقبولها من القائد';
  end if;

  v_report_json := v_report_json || jsonb_build_object(
    'can_submit',                v_can_submit,
    'can_review',                v_can_review,
    'can_edit_marks',            v_can_edit_marks,
    'completion_blocking_reason', v_completion_blocking
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',             i.id,
      'name',           i.name,
      'quantity_note',  i.quantity_note,
      'quantity_value', i.quantity_value,
      'quantity_unit',  i.quantity_unit,
      'is_required',    i.is_required,
      'position',       i.position,
      'bought',         coalesce(occ.status = 'bought', false),
      'status',         coalesce(occ.status, 'untouched'),
      'reason',         occ.reason,
      'marked_by',      occ.marked_by,
      'marked_by_name', mp.display_name,
      'marked_at',      occ.marked_at,
      'price',          i.price
    ) order by i.position
  ), '[]'::jsonb)
  into v_items
  from team_shopping_items i
  left join team_shopping_item_occurrences occ
    on occ.team_shopping_item_id = i.id and occ.occurrence_date = p_date
  left join profiles mp on mp.id = occ.marked_by
  where i.team_id = p_team_id and i.is_active = true;

  return jsonb_build_object(
    'turn_date',          p_date,
    'responsible_member', v_responsible,
    'can_mark',           v_can_mark,
    'can_edit_list',      v_is_leader,
    'items',              v_items,
    'report',             v_report_json
  );
end;
$$;

-- ─── G. complete_team_turn ────────────────────────────────────────────────────
-- Same (text, uuid) signature as Gate 11's version. Only addition: if the
-- team has any active shopping item, completion now requires a submitted
-- AND accepted report for the turn's date. Teams with no active shopping
-- items are never blocked, so this cannot break a team that doesn't use
-- the shopping list.

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

  if exists(
    select 1 from team_shopping_items
    where team_id = v_turn.team_id and is_active = true
  ) and not exists(
    select 1 from team_shopping_reports
    where team_id = v_turn.team_id
      and report_date = v_turn.turn_date
      and submitted_at is not null
      and leader_status = 'accepted'
  ) then
    raise exception 'يجب إرسال قائمة التسوق وقبولها من القائد قبل إكمال الدور';
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

-- ─── H. Grants ────────────────────────────────────────────────────────────────
-- RPC-only access preserved: no table grants added anywhere (team_shopping_
-- reports gets RLS + revoke-all above, same as every other table). Re-grant
-- execute for every function touched in this migration.

grant execute on function public.get_team_shopping_list(text, uuid, date)                          to anon;
grant execute on function public.mark_shopping_item_status(text, uuid, uuid, boolean, date, text)   to anon;
grant execute on function public.submit_team_shopping_report(text, uuid, date)                      to anon;
grant execute on function public.leader_review_shopping_report(text, uuid, date, text, text)        to anon;
grant execute on function public.complete_team_turn(text, uuid)                                     to anon;
