-- Gate 51.1: Shopping Report to Personal Budget Backend
-- Backend-only, additive financial linkage for accepted shopping reports.
-- Do not apply historical backfill here: accepted reports that predate this
-- migration remain readable with null financial fields and are not charged.
--
-- Financial rules:
-- * expected_total = sum(price) for every active item; null prices count as 0.
-- * actual_total = sum(price) for active items whose occurrence status is bought.
-- * personal deduction = actual_total only, never expected_total.
-- * actual_total = 0 creates no zero-value expense row; financial application is
--   still marked complete with expense_id null.
-- * accepted reports are terminal in the normal review RPC. Future correction
--   should use a separate leader_reopen_accepted_report RPC that inserts an
--   offsetting adjustment expense instead of editing/deleting the original.

-- ─── A. Report financial fields ─────────────────────────────────────────────

alter table public.team_shopping_reports
  add column if not exists expected_total numeric(12,2) null,
  add column if not exists actual_total numeric(12,2) null,
  add column if not exists expense_id uuid null references public.expenses(id) on delete restrict,
  add column if not exists financial_applied_at timestamptz null,
  add column if not exists financial_applied_by uuid null references public.profiles(id) on delete set null;

alter table public.team_shopping_reports
  drop constraint if exists team_shopping_reports_expected_total_nonnegative_check,
  drop constraint if exists team_shopping_reports_actual_total_nonnegative_check,
  drop constraint if exists team_shopping_reports_financial_application_check;

alter table public.team_shopping_reports
  add constraint team_shopping_reports_expected_total_nonnegative_check
    check (expected_total is null or expected_total >= 0),
  add constraint team_shopping_reports_actual_total_nonnegative_check
    check (actual_total is null or actual_total >= 0),
  add constraint team_shopping_reports_financial_application_check
    check (
      (
        expected_total is null
        and actual_total is null
        and expense_id is null
        and financial_applied_at is null
        and financial_applied_by is null
      )
      or
      (
        leader_status = 'accepted'
        and expected_total is not null
        and actual_total is not null
        and financial_applied_at is not null
        and financial_applied_by is not null
        and (
          (actual_total = 0 and expense_id is null)
          or
          (actual_total > 0 and expense_id is not null)
        )
      )
    );

create index if not exists team_shopping_reports_expense_idx
  on public.team_shopping_reports(expense_id)
  where expense_id is not null;

-- Immutable per-item financial snapshot for accepted reports. This preserves
-- the price/status audit trail even if the checklist definition changes later.
create table if not exists public.team_shopping_report_financial_items (
  id                    uuid primary key default gen_random_uuid(),
  report_id             uuid not null references public.team_shopping_reports(id) on delete cascade,
  team_shopping_item_id  uuid null references public.team_shopping_items(id) on delete set null,
  item_name             text not null check (length(trim(item_name)) between 1 and 80),
  is_required           boolean not null,
  price_at_acceptance   numeric(12,2) null check (price_at_acceptance is null or price_at_acceptance >= 0),
  occurrence_status     text not null check (occurrence_status in ('bought', 'not_bought', 'untouched')),
  occurrence_reason     text null check (occurrence_reason is null or length(trim(occurrence_reason)) between 1 and 200),
  counted_in_expected   boolean not null default true,
  counted_in_actual     boolean not null default false,
  created_at            timestamptz not null default now(),
  unique(report_id, team_shopping_item_id)
);

create index if not exists team_shopping_report_financial_items_report_idx
  on public.team_shopping_report_financial_items(report_id);

alter table public.team_shopping_report_financial_items enable row level security;
revoke all on public.team_shopping_report_financial_items from anon, authenticated;

-- ─── B. Budget overview includes accepted shopping expenses ─────────────────

create or replace function public.get_budget_overview(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_plan budget_plans%rowtype;
  v_has_plan boolean := false;
  v_days_total int;
  v_days_remaining int;
  v_spent numeric;
  v_sub_total numeric;
  v_remaining numeric;
  v_safe_daily numeric;
  v_today_spending numeric;
  v_planned_recurring numeric := 0;
  v_actual_recurring numeric := 0;
  v_skipped_recurring numeric := 0;
  v_skipped_count int := 0;
  v_today_expected numeric := 0;
  v_today_purchased numeric := 0;
  v_today_skipped_count int := 0;
  v_summary jsonb;
  v_subs jsonb;
  v_recent jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_plan
  from public.budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;
  v_has_plan := found;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'name', s.name,
    'amount', s.amount,
    'start_date', s.start_date,
    'end_date', s.end_date,
    'notify_days_before', s.notify_days_before,
    'is_active', s.is_active
  ) order by s.name), '[]'::jsonb) into v_subs
  from public.subscriptions s
  where s.profile_id = v_profile_id and s.is_active = true;

  if not v_has_plan then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id,
      'item_name', e.item_name,
      'amount', e.amount,
      'category', e.category,
      'note', e.note,
      'expense_date', e.expense_date,
      'source', e.source
    ) order by expense_date desc, created_at desc), '[]'::jsonb) into v_recent
    from (
      select * from public.expenses
      where profile_id = v_profile_id
      order by expense_date desc, created_at desc
      limit 20
    ) e;

    return jsonb_build_object(
      'budget_plan', null,
      'summary', null,
      'active_subscriptions', v_subs,
      'recent_expenses', v_recent
    );
  end if;

  v_days_total := (v_plan.end_date - v_plan.start_date) + 1;

  if current_date < v_plan.start_date then
    v_days_remaining := v_days_total;
  elsif current_date > v_plan.end_date then
    v_days_remaining := 0;
  else
    v_days_remaining := (v_plan.end_date - current_date) + 1;
  end if;

  select coalesce(sum(amount), 0) into v_spent
  from public.expenses
  where profile_id = v_profile_id
    and budget_plan_id = v_plan.id
    and source in ('manual','recurring_purchase','team_shopping');

  select coalesce(sum(amount), 0) into v_actual_recurring
  from public.expenses
  where profile_id = v_profile_id
    and budget_plan_id = v_plan.id
    and source = 'recurring_purchase';

  select coalesce(sum(amount), 0) into v_sub_total
  from public.subscriptions
  where profile_id = v_profile_id
    and is_active = true
    and start_date <= v_plan.end_date
    and end_date >= v_plan.start_date;

  select coalesce(sum(x.price), 0) into v_planned_recurring
  from (
    select rp.price
    from public.recurring_purchases rp
    cross join lateral generate_series(
      greatest(rp.start_date, v_plan.start_date),
      least(rp.end_date, v_plan.end_date),
      interval '1 day'
    ) g(day)
    where rp.profile_id = v_profile_id
      and rp.is_active = true
      and rp.start_date <= v_plan.end_date
      and rp.end_date >= v_plan.start_date
      and public.recurring_purchase_matches_date(rp.frequency, rp.interval_days, rp.start_date, rp.end_date, g.day::date)
  ) x;

  select coalesce(sum(expected_price), 0), count(*) into v_skipped_recurring, v_skipped_count
  from public.recurring_purchase_occurrences
  where profile_id = v_profile_id
    and status = 'skipped'
    and occurrence_date between v_plan.start_date and v_plan.end_date;

  select coalesce(sum(rp.price), 0) into v_today_expected
  from public.recurring_purchases rp
  where rp.profile_id = v_profile_id
    and rp.is_active = true
    and public.recurring_purchase_matches_date(rp.frequency, rp.interval_days, rp.start_date, rp.end_date, current_date);

  select coalesce(sum(amount), 0) into v_today_purchased
  from public.expenses
  where profile_id = v_profile_id
    and source = 'recurring_purchase'
    and expense_date = current_date;

  select count(*) into v_today_skipped_count
  from public.recurring_purchase_occurrences
  where profile_id = v_profile_id
    and status = 'skipped'
    and occurrence_date = current_date;

  v_remaining := v_plan.total_money - v_spent - v_sub_total;
  v_safe_daily := v_remaining / greatest(v_days_remaining, 1);

  select coalesce(sum(amount), 0) into v_today_spending
  from public.expenses
  where profile_id = v_profile_id
    and budget_plan_id = v_plan.id
    and source in ('manual','recurring_purchase','team_shopping')
    and expense_date = current_date;

  v_summary := jsonb_build_object(
    'days_total', v_days_total,
    'days_remaining', v_days_remaining,
    'total_spent', v_spent,
    'subscription_total', v_sub_total,
    'remaining_money', v_remaining,
    'safe_daily_limit', v_safe_daily,
    'today_spending', v_today_spending,
    'is_over_daily_limit', v_today_spending > v_safe_daily and v_days_remaining > 0,
    'planned_recurring_total', v_planned_recurring,
    'actual_recurring_total', v_actual_recurring,
    'skipped_recurring_total', v_skipped_recurring,
    'skipped_recurring_count', v_skipped_count,
    'today_recurring_expected_total', v_today_expected,
    'today_recurring_purchased_total', v_today_purchased,
    'today_recurring_skipped_count', v_today_skipped_count
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'item_name', e.item_name,
    'amount', e.amount,
    'category', e.category,
    'note', e.note,
    'expense_date', e.expense_date,
    'source', e.source
  ) order by expense_date desc, created_at desc), '[]'::jsonb) into v_recent
  from (
    select * from public.expenses
    where profile_id = v_profile_id
      and budget_plan_id = v_plan.id
    order by expense_date desc, created_at desc
    limit 20
  ) e;

  return jsonb_build_object(
    'budget_plan', jsonb_build_object(
      'id', v_plan.id,
      'total_money', v_plan.total_money,
      'start_date', v_plan.start_date,
      'end_date', v_plan.end_date,
      'note', v_plan.note,
      'is_active', v_plan.is_active
    ),
    'summary', v_summary,
    'active_subscriptions', v_subs,
    'recent_expenses', v_recent
  );
end;
$$;

grant execute on function public.get_budget_overview(text) to anon;

-- ─── C. Shopping list report JSON exposes additive financial fields ─────────

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
  v_financial_applied_by_name text;
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
    select p.display_name into v_financial_applied_by_name
    from profiles p where p.id = v_report.financial_applied_by;

    v_report_json := jsonb_build_object(
      'submitted_at',            v_report.submitted_at,
      'submitted_by',            v_report.submitted_by,
      'submitted_by_name',       v_submitted_by_name,
      'leader_status',           v_report.leader_status,
      'leader_reviewed_at',      v_report.leader_reviewed_at,
      'leader_reviewed_by',      v_report.leader_reviewed_by,
      'leader_reviewed_by_name', v_reviewed_by_name,
      'leader_note',             v_report.leader_note,
      'expected_total',          v_report.expected_total,
      'actual_total',            v_report.actual_total,
      'expense_id',              v_report.expense_id,
      'financial_applied_at',    v_report.financial_applied_at,
      'financial_applied_by',    v_report.financial_applied_by,
      'financial_applied_by_name', v_financial_applied_by_name
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
      'leader_note',             null,
      'expected_total',          null,
      'actual_total',            null,
      'expense_id',              null,
      'financial_applied_at',    null,
      'financial_applied_by',    null,
      'financial_applied_by_name', null
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

grant execute on function public.get_team_shopping_list(text, uuid, date) to anon;

-- ─── D. Terminal, idempotent, financial leader review ───────────────────────

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
  v_profile_id          uuid;
  v_report              team_shopping_reports%rowtype;
  v_note                text;
  v_team_name           text;
  v_reviewed_at         timestamptz := now();
  v_expected_total      numeric(12,2) := 0;
  v_actual_total        numeric(12,2) := 0;
  v_expense_id          uuid := null;
  v_budget_plan_id      uuid := null;
  v_missing_optional    text := null;
  v_notification_body   text;
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
  where team_id = p_team_id and report_date = p_date
  for update;

  if not found or v_report.submitted_at is null then
    raise exception 'لم يتم إرسال القائمة بعد';
  end if;

  if v_report.leader_status <> 'pending' then
    raise exception 'تمت مراجعة القائمة بالفعل ولا يمكن مراجعتها مرة أخرى';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');
  if p_status = 'rejected' and v_note is null then
    raise exception 'يجب كتابة سبب الرفض';
  end if;
  if v_note is not null and length(v_note) > 300 then
    raise exception 'invalid note';
  end if;

  select name into v_team_name from teams where id = p_team_id and is_active = true;
  if v_team_name is null then
    raise exception 'team not found';
  end if;

  if p_status = 'accepted' then
    if not exists(
      select 1 from profiles
      where id = v_report.responsible_profile_id and is_active = true
    ) then
      raise exception 'responsible profile not found';
    end if;

    select coalesce(sum(coalesce(i.price, 0)), 0)::numeric(12,2)
      into v_expected_total
    from team_shopping_items i
    where i.team_id = p_team_id
      and i.is_active = true;

    select coalesce(sum(coalesce(i.price, 0)), 0)::numeric(12,2)
      into v_actual_total
    from team_shopping_items i
    join team_shopping_item_occurrences occ
      on occ.team_shopping_item_id = i.id
     and occ.occurrence_date = p_date
     and occ.status = 'bought'
    where i.team_id = p_team_id
      and i.is_active = true;

    select string_agg(i.name || coalesce(' (' || occ.reason || ')', ''), '، ' order by i.position)
      into v_missing_optional
    from team_shopping_items i
    join team_shopping_item_occurrences occ
      on occ.team_shopping_item_id = i.id
     and occ.occurrence_date = p_date
     and occ.status = 'not_bought'
    where i.team_id = p_team_id
      and i.is_active = true
      and i.is_required = false;

    if v_actual_total > 0 then
      select bp.id into v_budget_plan_id
      from budget_plans bp
      where bp.profile_id = v_report.responsible_profile_id
        and bp.is_active = true
        and p_date between bp.start_date and bp.end_date
      limit 1;

      if v_report.expense_id is null then
        insert into expenses (
          profile_id, budget_plan_id, source, item_name, amount, category, note, expense_date
        ) values (
          v_report.responsible_profile_id,
          v_budget_plan_id,
          'team_shopping',
          left('مصروف تسوق فريق ' || v_team_name, 80),
          v_actual_total,
          'تسوق فريق',
          left('مصروف تسوق فريق ' || v_team_name || ' بتاريخ ' || to_char(p_date, 'YYYY-MM-DD') || ' (تقرير: ' || v_report.id::text || ')', 300),
          p_date
        ) returning id into v_expense_id;
      else
        v_expense_id := v_report.expense_id;
      end if;
    end if;

    insert into team_shopping_report_financial_items (
      report_id,
      team_shopping_item_id,
      item_name,
      is_required,
      price_at_acceptance,
      occurrence_status,
      occurrence_reason,
      counted_in_expected,
      counted_in_actual
    )
    select
      v_report.id,
      i.id,
      i.name,
      i.is_required,
      i.price,
      coalesce(occ.status, 'untouched'),
      occ.reason,
      true,
      coalesce(occ.status = 'bought', false)
    from team_shopping_items i
    left join team_shopping_item_occurrences occ
      on occ.team_shopping_item_id = i.id
     and occ.occurrence_date = p_date
    where i.team_id = p_team_id
      and i.is_active = true
    on conflict (report_id, team_shopping_item_id) do nothing;

    update team_shopping_reports
    set leader_status        = 'accepted',
        leader_reviewed_at   = v_reviewed_at,
        leader_reviewed_by   = v_profile_id,
        leader_note          = v_note,
        expected_total       = v_expected_total,
        actual_total         = v_actual_total,
        expense_id           = v_expense_id,
        financial_applied_at = v_reviewed_at,
        financial_applied_by = v_profile_id,
        updated_at           = v_reviewed_at
    where id = v_report.id;

    v_notification_body := 'تم قبول تقرير تسوق فريق ' || v_team_name || chr(10) ||
      'المتوقع: ' || v_expected_total::text || ' MRU' || chr(10) ||
      'الفعلي: ' || v_actual_total::text || ' MRU';
    if v_missing_optional is not null then
      v_notification_body := v_notification_body || chr(10) || 'العناصر غير المشتراة: ' || v_missing_optional;
    end if;

    perform create_notification_internal(
      p_recipient_profile_id => v_report.responsible_profile_id,
      p_type                 => 'shopping_report_accepted',
      p_title                => 'تم قبول تقرير التسوق',
      p_body                 => v_notification_body,
      p_team_id              => p_team_id,
      p_shopping_report_id   => v_report.id,
      p_action_type          => 'open_team_shopping',
      p_action_payload       => jsonb_build_object(
        'team_id', p_team_id,
        'date', p_date,
        'expected_total', v_expected_total,
        'actual_total', v_actual_total,
        'expense_id', v_expense_id
      ),
      p_dedupe_key           => 'report_accept:' || v_report.id::text
    );
  else
    update team_shopping_reports
    set leader_status        = 'rejected',
        leader_reviewed_at   = v_reviewed_at,
        leader_reviewed_by   = v_profile_id,
        leader_note          = v_note,
        expected_total       = null,
        actual_total         = null,
        expense_id           = null,
        financial_applied_at = null,
        financial_applied_by = null,
        updated_at           = v_reviewed_at
    where id = v_report.id;

    if exists(
      select 1 from profiles where id = v_report.responsible_profile_id and is_active = true
    ) then
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

grant execute on function public.leader_review_shopping_report(text, uuid, date, text, text) to anon;

-- ─── E. Security posture ────────────────────────────────────────────────────
-- RLS remains enabled. Direct table grants remain revoked. Internal tables are
-- reachable only through SECURITY DEFINER RPCs. No Supabase Auth UID or
-- privileged-key dependency is introduced.

-- ─── F. Gate 51.1A live test plan (manual/remote, not run in this gate) ─────
-- 1. Accepted report calculates expected total correctly.
-- 2. Accepted report calculates actual total correctly.
-- 3. Only bought items count toward actual.
-- 4. Optional not-bought item does not count.
-- 5. Inactive item does not count.
-- 6. Item without price contributes zero.
-- 7. One expense row is created for responsible profile.
-- 8. Expense amount equals actual total.
-- 9. Expense source = team_shopping.
-- 10. Expense date links to report date.
-- 11. Report stores expense_id and financial metadata.
-- 12. Budget overview remaining balance decreases by actual only.
-- 13. Expected amount does not affect balance.
-- 14. Leader budget unchanged when leader is not responsible.
-- 15. Acceptance notification includes expected/actual values.
-- 16. Reject creates no expense.
-- 17. Rejected report can be corrected/resubmitted and then accepted.
-- 18. Accepting same report twice fails.
-- 19. Exactly one expense exists after duplicate accept attempt.
-- 20. Concurrent/near-concurrent acceptance cannot double-charge.
-- 21. Non-leader cannot review.
-- 22. Another team's leader cannot review.
-- 23. Historical accepted report remains unchanged.
-- 24. Disposable data cleanup returns zero.
