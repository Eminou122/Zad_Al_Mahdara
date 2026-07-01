-- Gate 7: Recurring Purchases / Daily Costs Foundation
-- Additive-only. Does NOT edit migrations 001-009.
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run.

alter table public.expenses drop constraint if exists expenses_source_check;
alter table public.expenses add constraint expenses_source_check
  check (source in ('manual','subscription','team_shopping','team_tax','adjustment','recurring_purchase'));

create table if not exists public.recurring_purchases (
  id            uuid          primary key default gen_random_uuid(),
  profile_id    uuid          not null references public.profiles(id) on delete cascade,
  name          text          not null check (length(trim(name)) between 1 and 80),
  price         numeric(12,2) not null check (price >= 0),
  frequency     text          not null check (frequency in ('daily','every_n_days','weekly')),
  interval_days int           null check (interval_days between 2 and 365),
  start_date    date          not null,
  end_date      date          not null,
  reminder_time time          null,
  note          text          null check (note is null or length(note) <= 300),
  is_active     boolean       not null default true,
  created_at    timestamptz   not null default now(),
  updated_at    timestamptz   not null default now(),
  constraint recurring_purchases_dates check (end_date >= start_date),
  constraint recurring_purchases_frequency_interval check (
    (frequency = 'every_n_days' and interval_days is not null)
    or
    (frequency <> 'every_n_days' and interval_days is null)
  )
);

create index if not exists recurring_purchases_profile_active_idx
  on public.recurring_purchases(profile_id, is_active, start_date, end_date);

create table if not exists public.recurring_purchase_occurrences (
  id                    uuid          primary key default gen_random_uuid(),
  recurring_purchase_id uuid          not null references public.recurring_purchases(id) on delete cascade,
  profile_id            uuid          not null references public.profiles(id) on delete cascade,
  occurrence_date       date          not null,
  status                text          not null check (status in ('purchased','skipped')),
  expected_name         text          not null,
  expected_price        numeric(12,2) not null,
  expense_id            uuid          null references public.expenses(id) on delete set null,
  note                  text          null check (note is null or length(note) <= 300),
  created_at            timestamptz   not null default now(),
  updated_at            timestamptz   not null default now(),
  marked_at             timestamptz   not null default now(),
  unique(recurring_purchase_id, occurrence_date)
);

create index if not exists recurring_purchase_occurrences_profile_date_idx
  on public.recurring_purchase_occurrences(profile_id, occurrence_date desc);

alter table public.recurring_purchases enable row level security;
alter table public.recurring_purchase_occurrences enable row level security;

revoke all on public.recurring_purchases from anon, authenticated;
revoke all on public.recurring_purchase_occurrences from anon, authenticated;

create or replace function public.recurring_purchase_matches_date(
  p_frequency text,
  p_interval_days int,
  p_start_date date,
  p_end_date date,
  p_date date
) returns boolean
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select p_date between p_start_date and p_end_date
    and case
      when p_frequency = 'daily' then true
      when p_frequency = 'every_n_days' then ((p_date - p_start_date) % p_interval_days) = 0
      when p_frequency = 'weekly' then extract(dow from p_date) = extract(dow from p_start_date)
      else false
    end;
$$;

revoke execute on function public.recurring_purchase_matches_date(text, int, date, date, date) from public;
revoke execute on function public.recurring_purchase_matches_date(text, int, date, date, date) from anon;
revoke execute on function public.recurring_purchase_matches_date(text, int, date, date, date) from authenticated;

create or replace function public.get_recurring_purchases(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_items jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rp.id,
    'name', rp.name,
    'price', rp.price,
    'frequency', rp.frequency,
    'interval_days', rp.interval_days,
    'start_date', rp.start_date,
    'end_date', rp.end_date,
    'reminder_time', case when rp.reminder_time is null then null else to_char(rp.reminder_time, 'HH24:MI') end,
    'note', rp.note,
    'is_active', rp.is_active
  ) order by rp.start_date desc, rp.name), '[]'::jsonb) into v_items
  from public.recurring_purchases rp
  where rp.profile_id = v_profile_id
    and rp.is_active = true;

  return jsonb_build_object('items', v_items);
end;
$$;

create or replace function public.get_today_recurring_purchases(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_today date := current_date;
  v_items jsonb;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select coalesce(jsonb_agg(jsonb_build_object(
    'recurring_purchase_id', rp.id,
    'occurrence_id', rpo.id,
    'name', coalesce(rpo.expected_name, rp.name),
    'price', coalesce(rpo.expected_price, rp.price),
    'frequency', rp.frequency,
    'interval_days', rp.interval_days,
    'reminder_time', case when rp.reminder_time is null then null else to_char(rp.reminder_time, 'HH24:MI') end,
    'note', rp.note,
    'occurrence_date', v_today,
    'status', coalesce(rpo.status, 'unmarked'),
    'expense_id', rpo.expense_id
  ) order by rp.reminder_time nulls last, rp.name), '[]'::jsonb) into v_items
  from public.recurring_purchases rp
  left join public.recurring_purchase_occurrences rpo
    on rpo.recurring_purchase_id = rp.id
   and rpo.occurrence_date = v_today
   and rpo.profile_id = v_profile_id
  where rp.profile_id = v_profile_id
    and rp.is_active = true
    and public.recurring_purchase_matches_date(rp.frequency, rp.interval_days, rp.start_date, rp.end_date, v_today);

  return jsonb_build_object('items', v_items);
end;
$$;

create or replace function public.get_recurring_purchase_overview(
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
  v_today date := current_date;
  v_active_count int;
  v_today_expected numeric;
  v_today_purchased numeric;
  v_today_skipped_count int;
  v_planned_total numeric := 0;
  v_actual_total numeric := 0;
  v_skipped_total numeric := 0;
  v_skipped_count int := 0;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select count(*) into v_active_count
  from public.recurring_purchases
  where profile_id = v_profile_id and is_active = true;

  select coalesce(sum(rp.price), 0) into v_today_expected
  from public.recurring_purchases rp
  where rp.profile_id = v_profile_id
    and rp.is_active = true
    and public.recurring_purchase_matches_date(rp.frequency, rp.interval_days, rp.start_date, rp.end_date, v_today);

  select coalesce(sum(e.amount), 0) into v_today_purchased
  from public.expenses e
  where e.profile_id = v_profile_id
    and e.source = 'recurring_purchase'
    and e.expense_date = v_today;

  select count(*) into v_today_skipped_count
  from public.recurring_purchase_occurrences rpo
  where rpo.profile_id = v_profile_id
    and rpo.occurrence_date = v_today
    and rpo.status = 'skipped';

  select * into v_plan
  from public.budget_plans
  where profile_id = v_profile_id and is_active = true
  limit 1;
  v_has_plan := found;

  if v_has_plan then
    select coalesce(sum(x.price), 0) into v_planned_total
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

    select coalesce(sum(e.amount), 0) into v_actual_total
    from public.expenses e
    where e.profile_id = v_profile_id
      and e.source = 'recurring_purchase'
      and e.expense_date between v_plan.start_date and v_plan.end_date;

    select coalesce(sum(rpo.expected_price), 0), count(*) into v_skipped_total, v_skipped_count
    from public.recurring_purchase_occurrences rpo
    where rpo.profile_id = v_profile_id
      and rpo.status = 'skipped'
      and rpo.occurrence_date between v_plan.start_date and v_plan.end_date;
  end if;

  return jsonb_build_object(
    'active_recurring_count', v_active_count,
    'today_expected_total', v_today_expected,
    'today_purchased_total', v_today_purchased,
    'today_skipped_count', v_today_skipped_count,
    'planned_total', v_planned_total,
    'actual_purchased_total', v_actual_total,
    'skipped_total', v_skipped_total,
    'skipped_count', v_skipped_count
  );
end;
$$;

create or replace function public.create_recurring_purchase(
  p_session_token text,
  p_name text,
  p_price numeric,
  p_frequency text,
  p_interval_days int,
  p_start_date date,
  p_end_date date,
  p_reminder_time time,
  p_note text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_name)) not between 1 and 80 then raise exception 'name invalid'; end if;
  if p_price < 0 then raise exception 'price must be >= 0'; end if;
  if p_frequency not in ('daily','every_n_days','weekly') then raise exception 'frequency invalid'; end if;
  if p_frequency = 'every_n_days' and p_interval_days is null then raise exception 'interval_days required'; end if;
  if p_frequency <> 'every_n_days' and p_interval_days is not null then raise exception 'interval_days must be null'; end if;
  if p_interval_days is not null and p_interval_days not between 2 and 365 then raise exception 'interval_days invalid'; end if;
  if p_end_date < p_start_date then raise exception 'end_date must be >= start_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note too long'; end if;

  insert into public.recurring_purchases (
    profile_id, name, price, frequency, interval_days, start_date, end_date, reminder_time, note
  ) values (
    v_profile_id, trim(p_name), p_price, p_frequency, p_interval_days, p_start_date, p_end_date, p_reminder_time, p_note
  );

  return public.get_recurring_purchases(p_session_token);
end;
$$;

create or replace function public.update_recurring_purchase(
  p_session_token text,
  p_recurring_purchase_id uuid,
  p_name text,
  p_price numeric,
  p_frequency text,
  p_interval_days int,
  p_start_date date,
  p_end_date date,
  p_reminder_time time,
  p_note text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_rows int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if length(trim(p_name)) not between 1 and 80 then raise exception 'name invalid'; end if;
  if p_price < 0 then raise exception 'price must be >= 0'; end if;
  if p_frequency not in ('daily','every_n_days','weekly') then raise exception 'frequency invalid'; end if;
  if p_frequency = 'every_n_days' and p_interval_days is null then raise exception 'interval_days required'; end if;
  if p_frequency <> 'every_n_days' and p_interval_days is not null then raise exception 'interval_days must be null'; end if;
  if p_interval_days is not null and p_interval_days not between 2 and 365 then raise exception 'interval_days invalid'; end if;
  if p_end_date < p_start_date then raise exception 'end_date must be >= start_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note too long'; end if;

  update public.recurring_purchases
  set name = trim(p_name),
      price = p_price,
      frequency = p_frequency,
      interval_days = p_interval_days,
      start_date = p_start_date,
      end_date = p_end_date,
      reminder_time = p_reminder_time,
      note = p_note,
      updated_at = now()
  where id = p_recurring_purchase_id
    and profile_id = v_profile_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'recurring purchase not found'; end if;

  return public.get_recurring_purchases(p_session_token);
end;
$$;

create or replace function public.deactivate_recurring_purchase(
  p_session_token text,
  p_recurring_purchase_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_rows int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  update public.recurring_purchases
  set is_active = false,
      updated_at = now()
  where id = p_recurring_purchase_id
    and profile_id = v_profile_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'recurring purchase not found'; end if;

  return public.get_recurring_purchases(p_session_token);
end;
$$;

create or replace function public.mark_recurring_purchase_occurrence(
  p_session_token text,
  p_recurring_purchase_id uuid,
  p_occurrence_date date,
  p_status text,
  p_note text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_purchase recurring_purchases%rowtype;
  v_occurrence recurring_purchase_occurrences%rowtype;
  v_plan budget_plans%rowtype;
  v_plan_id uuid := null;
  v_expense_id uuid := null;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if p_status not in ('purchased','skipped') then raise exception 'status invalid'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note too long'; end if;

  select * into v_purchase
  from public.recurring_purchases
  where id = p_recurring_purchase_id
    and profile_id = v_profile_id
    and is_active = true;

  if not found then raise exception 'recurring purchase not found'; end if;

  if not public.recurring_purchase_matches_date(
    v_purchase.frequency, v_purchase.interval_days, v_purchase.start_date, v_purchase.end_date, p_occurrence_date
  ) then
    raise exception 'occurrence_date does not match frequency';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_recurring_purchase_id::text || ':' || p_occurrence_date::text, 0)
  );

  insert into public.recurring_purchase_occurrences (
    recurring_purchase_id, profile_id, occurrence_date, status, expected_name, expected_price, expense_id, note
  ) values (
    p_recurring_purchase_id, v_profile_id, p_occurrence_date, p_status, v_purchase.name, v_purchase.price, null, p_note
  )
  on conflict (recurring_purchase_id, occurrence_date) do nothing;

  select * into v_occurrence
  from public.recurring_purchase_occurrences
  where recurring_purchase_id = p_recurring_purchase_id
    and occurrence_date = p_occurrence_date
    and profile_id = v_profile_id
  for update;

  if not found then
    raise exception 'recurring purchase occurrence not found';
  end if;

  v_expense_id := v_occurrence.expense_id;

  if v_expense_id is not null and not exists (
    select 1
    from public.expenses
    where id = v_expense_id
      and profile_id = v_profile_id
      and source = 'recurring_purchase'
  ) then
    v_expense_id := null;
  end if;

  if p_status = 'skipped' and v_expense_id is not null then
    delete from public.expenses
    where id = v_expense_id
      and profile_id = v_profile_id
      and source = 'recurring_purchase';
    v_expense_id := null;
  end if;

  if p_status = 'purchased' and v_expense_id is null then
    select * into v_plan
    from public.budget_plans
    where profile_id = v_profile_id
      and is_active = true
      and p_occurrence_date between start_date and end_date
    limit 1;
    if found then v_plan_id := v_plan.id; end if;

    insert into public.expenses (
      profile_id, budget_plan_id, source, item_name, amount, category, note, expense_date
    ) values (
      v_profile_id,
      v_plan_id,
      'recurring_purchase',
      v_purchase.name,
      v_purchase.price,
      'متكرر',
      coalesce(p_note, v_purchase.note),
      p_occurrence_date
    ) returning id into v_expense_id;
  end if;

  update public.recurring_purchase_occurrences
  set status = p_status,
      expense_id = v_expense_id,
      note = p_note,
      updated_at = now(),
      marked_at = now()
  where id = v_occurrence.id
    and profile_id = v_profile_id;

  return public.get_today_recurring_purchases(p_session_token);
end;
$$;

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
    and source in ('manual','recurring_purchase');

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
    and source in ('manual','recurring_purchase')
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

grant execute on function public.get_recurring_purchases(text) to anon;
grant execute on function public.get_today_recurring_purchases(text) to anon;
grant execute on function public.get_recurring_purchase_overview(text) to anon;
grant execute on function public.create_recurring_purchase(text, text, numeric, text, int, date, date, time, text) to anon;
grant execute on function public.update_recurring_purchase(text, uuid, text, numeric, text, int, date, date, time, text) to anon;
grant execute on function public.deactivate_recurring_purchase(text, uuid) to anon;
grant execute on function public.mark_recurring_purchase_occurrence(text, uuid, date, text, text) to anon;
grant execute on function public.get_budget_overview(text) to anon;
