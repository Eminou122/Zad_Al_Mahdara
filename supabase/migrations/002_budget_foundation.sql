-- Gate 4: Personal Budget Foundation
-- Apply manually: Supabase Dashboard → SQL Editor → Run
-- Re-runnable on a fresh dev DB (drops only budget tables, never auth tables).
-- WARNING: Destroys budget data. Only run on dev DB before real user data exists.

-- ─── Drop budget tables safely ───────────────────────────────────────────────
drop table if exists public.subscriptions cascade;
drop table if exists public.expenses      cascade;
drop table if exists public.budget_plans  cascade;

-- ─── budget_plans ────────────────────────────────────────────────────────────
create table public.budget_plans (
  id          uuid          primary key default gen_random_uuid(),
  profile_id  uuid          not null references public.profiles(id) on delete cascade,
  total_money numeric(12,2) not null check (total_money >= 0),
  start_date  date          not null,
  end_date    date          not null,
  note        text          null check (note is null or length(note) <= 300),
  is_active   boolean       not null default true,
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now(),
  constraint budget_plans_dates check (end_date >= start_date)
);

create unique index budget_plans_one_active_per_profile
  on public.budget_plans(profile_id)
  where is_active = true;

-- ─── expenses ─────────────────────────────────────────────────────────────────
create table public.expenses (
  id             uuid          primary key default gen_random_uuid(),
  profile_id     uuid          not null references public.profiles(id) on delete cascade,
  budget_plan_id uuid          null references public.budget_plans(id) on delete set null,
  source         text          not null default 'manual'
                   check (source in ('manual','subscription','team_shopping','team_tax','adjustment')),
  item_name      text          not null check (length(trim(item_name)) between 1 and 80),
  amount         numeric(12,2) not null check (amount >= 0),
  category       text          null check (category is null or length(category) <= 40),
  note           text          null check (note is null or length(note) <= 300),
  expense_date   date          not null,
  created_at     timestamptz   not null default now(),
  updated_at     timestamptz   not null default now()
);

create index expenses_profile_date_idx on public.expenses(profile_id, expense_date desc);
create index expenses_budget_plan_idx  on public.expenses(budget_plan_id);

-- ─── subscriptions ────────────────────────────────────────────────────────────
create table public.subscriptions (
  id                 uuid          primary key default gen_random_uuid(),
  profile_id         uuid          not null references public.profiles(id) on delete cascade,
  budget_plan_id     uuid          null references public.budget_plans(id) on delete set null,
  name               text          not null check (length(trim(name)) between 1 and 80),
  amount             numeric(12,2) not null check (amount >= 0),
  start_date         date          not null,
  end_date           date          not null,
  notify_days_before int           not null default 3 check (notify_days_before between 0 and 30),
  is_active          boolean       not null default true,
  created_at         timestamptz   not null default now(),
  updated_at         timestamptz   not null default now(),
  constraint subscriptions_dates check (end_date >= start_date)
);

create index subscriptions_profile_active_idx on public.subscriptions(profile_id, is_active, end_date);
create index subscriptions_budget_plan_idx    on public.subscriptions(budget_plan_id);

-- ─── RLS: no direct table access — all goes through SECURITY DEFINER RPCs ────
alter table public.budget_plans  enable row level security;
alter table public.expenses      enable row level security;
alter table public.subscriptions enable row level security;

revoke all on public.budget_plans  from anon, authenticated;
revoke all on public.expenses      from anon, authenticated;
revoke all on public.subscriptions from anon, authenticated;

-- ─── Helper: session token → profile_id (internal, not granted to anon) ───────
drop function if exists public.current_profile_id_from_session(text);

create or replace function public.current_profile_id_from_session(
  p_session_token text
) returns uuid
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_token_hash text;
  v_session    app_sessions%rowtype;
  v_profile    profiles%rowtype;
begin
  v_token_hash := encode(digest(p_session_token, 'sha256'), 'hex');

  select * into v_session
  from app_sessions
  where token_hash = v_token_hash
    and revoked_at is null
    and expires_at > now();

  if not found then
    raise exception 'invalid session';
  end if;

  select * into v_profile
  from profiles
  where id = v_session.profile_id and is_active = true;

  if not found then
    raise exception 'invalid session';
  end if;

  update app_sessions set last_seen_at = now() where id = v_session.id;

  return v_profile.id;
end;
$$;

-- Helper is internal — revoke direct invocation from all non-owner roles
revoke execute on function public.current_profile_id_from_session(text) from public;
revoke execute on function public.current_profile_id_from_session(text) from anon;
revoke execute on function public.current_profile_id_from_session(text) from authenticated;

-- ─── get_budget_overview ─────────────────────────────────────────────────────
create or replace function public.get_budget_overview(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id     uuid;
  v_plan           budget_plans%rowtype;
  v_has_plan       boolean := false;
  v_days_total     int;
  v_days_remaining int;
  v_manual_spent   numeric;
  v_sub_total      numeric;
  v_remaining      numeric;
  v_safe_daily     numeric;
  v_today_spending numeric;
  v_summary        jsonb;
  v_subs           jsonb;
  v_recent         jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_plan
  from budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;
  v_has_plan := found;

  -- Active subscriptions (always the same regardless of plan)
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',                 s.id,
      'name',               s.name,
      'amount',             s.amount,
      'start_date',         s.start_date,
      'end_date',           s.end_date,
      'notify_days_before', s.notify_days_before,
      'is_active',          s.is_active
    ) order by s.name
  ), '[]'::jsonb) into v_subs
  from subscriptions s
  where s.profile_id = v_profile_id and s.is_active = true;

  if not v_has_plan then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id',           e.id,
        'item_name',    e.item_name,
        'amount',       e.amount,
        'category',     e.category,
        'note',         e.note,
        'expense_date', e.expense_date,
        'source',       e.source
      ) order by expense_date desc, created_at desc
    ), '[]'::jsonb) into v_recent
    from (
      select * from expenses
      where profile_id = v_profile_id
      order by expense_date desc, created_at desc
      limit 20
    ) e;

    return jsonb_build_object(
      'budget_plan',          null,
      'summary',              null,
      'active_subscriptions', v_subs,
      'recent_expenses',      v_recent
    );
  end if;

  -- Date calculations
  v_days_total := (v_plan.end_date - v_plan.start_date) + 1;

  if current_date < v_plan.start_date then
    v_days_remaining := v_days_total;
  elsif current_date > v_plan.end_date then
    v_days_remaining := 0;
  else
    v_days_remaining := (v_plan.end_date - current_date) + 1;
  end if;

  -- Manual spending from expenses linked to this plan
  select coalesce(sum(amount), 0) into v_manual_spent
  from expenses
  where profile_id     = v_profile_id
    and budget_plan_id = v_plan.id
    and source         = 'manual';

  -- Subscription total: active subs whose period overlaps the budget period
  select coalesce(sum(amount), 0) into v_sub_total
  from subscriptions
  where profile_id = v_profile_id
    and is_active  = true
    and start_date <= v_plan.end_date
    and end_date   >= v_plan.start_date;

  v_remaining  := v_plan.total_money - v_manual_spent - v_sub_total;
  v_safe_daily := v_remaining / greatest(v_days_remaining, 1);

  select coalesce(sum(amount), 0) into v_today_spending
  from expenses
  where profile_id     = v_profile_id
    and budget_plan_id = v_plan.id
    and source         = 'manual'
    and expense_date   = current_date;

  v_summary := jsonb_build_object(
    'days_total',          v_days_total,
    'days_remaining',      v_days_remaining,
    'total_spent',         v_manual_spent,
    'subscription_total',  v_sub_total,
    'remaining_money',     v_remaining,
    'safe_daily_limit',    v_safe_daily,
    'today_spending',      v_today_spending,
    'is_over_daily_limit', v_today_spending > v_safe_daily and v_days_remaining > 0
  );

  -- Recent expenses for the current plan
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',           e.id,
      'item_name',    e.item_name,
      'amount',       e.amount,
      'category',     e.category,
      'note',         e.note,
      'expense_date', e.expense_date,
      'source',       e.source
    ) order by expense_date desc, created_at desc
  ), '[]'::jsonb) into v_recent
  from (
    select * from expenses
    where profile_id     = v_profile_id
      and budget_plan_id = v_plan.id
    order by expense_date desc, created_at desc
    limit 20
  ) e;

  return jsonb_build_object(
    'budget_plan', jsonb_build_object(
      'id',          v_plan.id,
      'total_money', v_plan.total_money,
      'start_date',  v_plan.start_date,
      'end_date',    v_plan.end_date,
      'note',        v_plan.note,
      'is_active',   v_plan.is_active
    ),
    'summary',              v_summary,
    'active_subscriptions', v_subs,
    'recent_expenses',      v_recent
  );
end;
$$;

-- ─── upsert_budget_plan ───────────────────────────────────────────────────────
create or replace function public.upsert_budget_plan(
  p_session_token text,
  p_total_money   numeric,
  p_start_date    date,
  p_end_date      date,
  p_note          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_plan_id    uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if p_total_money < 0 then
    raise exception 'total_money must be >= 0';
  end if;
  if p_end_date < p_start_date then
    raise exception 'end_date must be >= start_date';
  end if;
  if p_note is not null and length(p_note) > 300 then
    raise exception 'note too long';
  end if;

  select id into v_plan_id
  from budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;

  if found then
    update budget_plans
    set total_money = p_total_money,
        start_date  = p_start_date,
        end_date    = p_end_date,
        note        = p_note,
        updated_at  = now()
    where id = v_plan_id;
  else
    insert into budget_plans (profile_id, total_money, start_date, end_date, note, is_active)
    values (v_profile_id, p_total_money, p_start_date, p_end_date, p_note, true);
  end if;

  return get_budget_overview(p_session_token);
end;
$$;

-- ─── add_expense ──────────────────────────────────────────────────────────────
create or replace function public.add_expense(
  p_session_token text,
  p_item_name     text,
  p_amount        numeric,
  p_category      text,
  p_note          text,
  p_expense_date  date
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_plan       budget_plans%rowtype;
  v_has_plan   boolean := false;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_item_name)) not between 1 and 80 then
    raise exception 'item_name invalid';
  end if;
  if p_amount < 0 then
    raise exception 'amount must be >= 0';
  end if;
  if p_category is not null and length(p_category) > 40 then
    raise exception 'category too long';
  end if;
  if p_note is not null and length(p_note) > 300 then
    raise exception 'note too long';
  end if;

  select * into v_plan
  from budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;
  v_has_plan := found;

  if v_has_plan and (p_expense_date < v_plan.start_date or p_expense_date > v_plan.end_date) then
    raise exception 'expense_date outside budget period';
  end if;

  insert into expenses (profile_id, budget_plan_id, source, item_name, amount, category, note, expense_date)
  values (
    v_profile_id,
    case when v_has_plan then v_plan.id else null end,
    'manual',
    trim(p_item_name),
    p_amount,
    p_category,
    p_note,
    p_expense_date
  );

  return get_budget_overview(p_session_token);
end;
$$;

-- ─── update_expense ───────────────────────────────────────────────────────────
create or replace function public.update_expense(
  p_session_token text,
  p_expense_id    uuid,
  p_item_name     text,
  p_amount        numeric,
  p_category      text,
  p_note          text,
  p_expense_date  date
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_plan       budget_plans%rowtype;
  v_rows       int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_item_name)) not between 1 and 80 then
    raise exception 'item_name invalid';
  end if;
  if p_amount < 0 then
    raise exception 'amount must be >= 0';
  end if;
  if p_category is not null and length(p_category) > 40 then
    raise exception 'category too long';
  end if;
  if p_note is not null and length(p_note) > 300 then
    raise exception 'note too long';
  end if;

  select * into v_plan
  from budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;

  if found and (p_expense_date < v_plan.start_date or p_expense_date > v_plan.end_date) then
    raise exception 'expense_date outside budget period';
  end if;

  update expenses
  set item_name    = trim(p_item_name),
      amount       = p_amount,
      category     = p_category,
      note         = p_note,
      expense_date = p_expense_date,
      updated_at   = now()
  where id         = p_expense_id
    and profile_id = v_profile_id
    and source     = 'manual';

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'expense not found or not editable';
  end if;

  return get_budget_overview(p_session_token);
end;
$$;

-- ─── delete_expense ───────────────────────────────────────────────────────────
create or replace function public.delete_expense(
  p_session_token text,
  p_expense_id    uuid
) returns void
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_rows       int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  delete from expenses
  where id         = p_expense_id
    and profile_id = v_profile_id
    and source     = 'manual';

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'expense not found or not deletable';
  end if;
end;
$$;

-- ─── add_subscription ────────────────────────────────────────────────────────
create or replace function public.add_subscription(
  p_session_token      text,
  p_name               text,
  p_amount             numeric,
  p_start_date         date,
  p_end_date           date,
  p_notify_days_before int
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_plan_id    uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_name)) not between 1 and 80 then
    raise exception 'name invalid';
  end if;
  if p_amount < 0 then
    raise exception 'amount must be >= 0';
  end if;
  if p_end_date < p_start_date then
    raise exception 'end_date must be >= start_date';
  end if;
  if p_notify_days_before not between 0 and 30 then
    raise exception 'notify_days_before must be between 0 and 30';
  end if;

  -- v_plan_id stays NULL if no active plan — budget_plan_id is nullable
  select id into v_plan_id
  from budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;

  insert into subscriptions (profile_id, budget_plan_id, name, amount, start_date, end_date, notify_days_before, is_active)
  values (v_profile_id, v_plan_id, trim(p_name), p_amount, p_start_date, p_end_date, p_notify_days_before, true);

  return get_budget_overview(p_session_token);
end;
$$;

-- ─── update_subscription ─────────────────────────────────────────────────────
create or replace function public.update_subscription(
  p_session_token      text,
  p_subscription_id    uuid,
  p_name               text,
  p_amount             numeric,
  p_start_date         date,
  p_end_date           date,
  p_notify_days_before int,
  p_is_active          boolean
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_rows       int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_name)) not between 1 and 80 then
    raise exception 'name invalid';
  end if;
  if p_amount < 0 then
    raise exception 'amount must be >= 0';
  end if;
  if p_end_date < p_start_date then
    raise exception 'end_date must be >= start_date';
  end if;
  if p_notify_days_before not between 0 and 30 then
    raise exception 'notify_days_before must be between 0 and 30';
  end if;

  update subscriptions
  set name               = trim(p_name),
      amount             = p_amount,
      start_date         = p_start_date,
      end_date           = p_end_date,
      notify_days_before = p_notify_days_before,
      is_active          = p_is_active,
      updated_at         = now()
  where id         = p_subscription_id
    and profile_id = v_profile_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'subscription not found';
  end if;

  return get_budget_overview(p_session_token);
end;
$$;

-- ─── delete_or_deactivate_subscription ───────────────────────────────────────
create or replace function public.delete_or_deactivate_subscription(
  p_session_token   text,
  p_subscription_id uuid
) returns void
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_rows       int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  update subscriptions
  set is_active  = false,
      updated_at = now()
  where id         = p_subscription_id
    and profile_id = v_profile_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'subscription not found';
  end if;
end;
$$;

-- ─── Grants: only public-facing RPCs granted to anon ────────────────────────
grant execute on function public.get_budget_overview(text)                                             to anon;
grant execute on function public.upsert_budget_plan(text, numeric, date, date, text)                   to anon;
grant execute on function public.add_expense(text, text, numeric, text, text, date)                    to anon;
grant execute on function public.update_expense(text, uuid, text, numeric, text, text, date)           to anon;
grant execute on function public.delete_expense(text, uuid)                                            to anon;
grant execute on function public.add_subscription(text, text, numeric, date, date, int)                to anon;
grant execute on function public.update_subscription(text, uuid, text, numeric, date, date, int, boolean) to anon;
grant execute on function public.delete_or_deactivate_subscription(text, uuid)                         to anon;
