-- Gate 53.3B1: retain manual financial history and make member removal auditable.

alter table public.expenses
  add column if not exists voided_at timestamptz null,
  add column if not exists voided_by uuid null references public.profiles(id) on delete restrict,
  add column if not exists void_reason text null;

alter table public.expenses
  add constraint expenses_void_audit_check check (
    (voided_at is null and voided_by is null and void_reason is null)
    or (
      voided_at is not null
      and voided_by is not null
      and length(trim(void_reason)) between 1 and 300
    )
  );

create index if not exists expenses_active_profile_plan_idx
  on public.expenses(profile_id, budget_plan_id, expense_date desc)
  where voided_at is null;

alter table public.team_members
  add column if not exists removed_by uuid null references public.profiles(id) on delete restrict,
  add column if not exists removal_reason text null;

-- NOT VALID retains legacy removed rows while enforcing the invariant for new writes.
alter table public.team_members
  add constraint team_members_removal_audit_check check (
    (removed_at is null and removed_by is null and removal_reason is null)
    or (
      removed_at is not null
      and (
        (removed_by is null and removal_reason is null)
        or (removed_by is not null and length(trim(removal_reason)) between 1 and 300)
      )
    )
  ) not valid;

create or replace function public.void_expense(
  p_session_token text,
  p_expense_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_expense public.expenses%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);

  if v_reason is null or length(v_reason) > 300 then
    raise exception 'invalid void reason';
  end if;

  select * into v_expense
  from public.expenses
  where id = p_expense_id
  for update;

  if not found or v_expense.profile_id <> v_profile_id or v_expense.source <> 'manual' then
    raise exception 'expense not available';
  end if;

  if v_expense.voided_at is not null then
    return jsonb_build_object('ok', true, 'voided', false);
  end if;

  update public.expenses
  set voided_at = now(),
      voided_by = v_profile_id,
      void_reason = v_reason,
      updated_at = now()
  where id = v_expense.id;

  return jsonb_build_object('ok', true, 'voided', true);
end;
$$;

-- Keep the old signature only as a non-destructive compatibility failure.
create or replace function public.delete_expense(
  p_session_token text,
  p_expense_id uuid
) returns void
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
begin
  raise exception 'expense deletion is unavailable; use void_expense';
end;
$$;

create or replace function public.update_expense(
  p_session_token text,
  p_expense_id uuid,
  p_item_name text,
  p_amount numeric,
  p_category text,
  p_note text,
  p_expense_date date
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_plan public.budget_plans%rowtype;
  v_rows int;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  if length(trim(p_item_name)) not between 1 and 80 then raise exception 'item_name invalid'; end if;
  if p_amount < 0 then raise exception 'amount must be >= 0'; end if;
  if p_category is not null and length(p_category) > 40 then raise exception 'category too long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note too long'; end if;
  select * into v_plan from public.budget_plans where profile_id = v_profile_id and is_active = true limit 1;
  if found and (p_expense_date < v_plan.start_date or p_expense_date > v_plan.end_date) then raise exception 'expense_date outside budget period'; end if;
  update public.expenses set item_name = trim(p_item_name), amount = p_amount, category = p_category,
    note = p_note, expense_date = p_expense_date, updated_at = now()
  where id = p_expense_id and profile_id = v_profile_id and source = 'manual' and voided_at is null;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'expense not found or not editable'; end if;
  return public.get_budget_overview(p_session_token);
end;
$$;

create or replace function public.get_budget_overview(p_session_token text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare
  v_profile_id uuid; v_plan public.budget_plans%rowtype; v_has_plan boolean := false;
  v_days_total int; v_days_remaining int; v_spent numeric; v_sub_total numeric; v_remaining numeric;
  v_safe_daily numeric; v_today_spending numeric; v_planned_recurring numeric := 0;
  v_actual_recurring numeric := 0; v_skipped_recurring numeric := 0; v_skipped_count int := 0;
  v_today_expected numeric := 0; v_today_purchased numeric := 0; v_today_skipped_count int := 0;
  v_summary jsonb; v_subs jsonb; v_recent jsonb;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select * into v_plan from public.budget_plans where profile_id = v_profile_id and is_active = true limit 1;
  v_has_plan := found;
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'amount',s.amount,'start_date',s.start_date,'end_date',s.end_date,'notify_days_before',s.notify_days_before,'is_active',s.is_active) order by s.name),'[]'::jsonb) into v_subs from public.subscriptions s where s.profile_id = v_profile_id and s.is_active;
  if not v_has_plan then
    select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'item_name',e.item_name,'amount',e.amount,'category',e.category,'note',e.note,'expense_date',e.expense_date,'source',e.source) order by expense_date desc,created_at desc),'[]'::jsonb) into v_recent from (select * from public.expenses where profile_id = v_profile_id and voided_at is null order by expense_date desc,created_at desc limit 20) e;
    return jsonb_build_object('budget_plan',null,'summary',null,'active_subscriptions',v_subs,'recent_expenses',v_recent);
  end if;
  v_days_total := (v_plan.end_date-v_plan.start_date)+1;
  if current_date < v_plan.start_date then v_days_remaining := v_days_total; elsif current_date > v_plan.end_date then v_days_remaining := 0; else v_days_remaining := (v_plan.end_date-current_date)+1; end if;
  select coalesce(sum(amount),0) into v_spent from public.expenses where profile_id=v_profile_id and budget_plan_id=v_plan.id and source in ('manual','recurring_purchase','team_shopping') and voided_at is null;
  select coalesce(sum(amount),0) into v_actual_recurring from public.expenses where profile_id=v_profile_id and budget_plan_id=v_plan.id and source='recurring_purchase' and voided_at is null;
  select coalesce(sum(amount),0) into v_sub_total from public.subscriptions where profile_id=v_profile_id and is_active and start_date<=v_plan.end_date and end_date>=v_plan.start_date;
  select coalesce(sum(x.price),0) into v_planned_recurring from (select rp.price from public.recurring_purchases rp cross join lateral generate_series(greatest(rp.start_date,v_plan.start_date),least(rp.end_date,v_plan.end_date),interval '1 day') g(day) where rp.profile_id=v_profile_id and rp.is_active and rp.start_date<=v_plan.end_date and rp.end_date>=v_plan.start_date and public.recurring_purchase_matches_date(rp.frequency,rp.interval_days,rp.start_date,rp.end_date,g.day::date)) x;
  select coalesce(sum(expected_price),0),count(*) into v_skipped_recurring,v_skipped_count from public.recurring_purchase_occurrences where profile_id=v_profile_id and status='skipped' and occurrence_date between v_plan.start_date and v_plan.end_date;
  select coalesce(sum(rp.price),0) into v_today_expected from public.recurring_purchases rp where rp.profile_id=v_profile_id and rp.is_active and public.recurring_purchase_matches_date(rp.frequency,rp.interval_days,rp.start_date,rp.end_date,current_date);
  select coalesce(sum(amount),0) into v_today_purchased from public.expenses where profile_id=v_profile_id and source='recurring_purchase' and expense_date=current_date and voided_at is null;
  select count(*) into v_today_skipped_count from public.recurring_purchase_occurrences where profile_id=v_profile_id and status='skipped' and occurrence_date=current_date;
  v_remaining:=v_plan.total_money-v_spent-v_sub_total; v_safe_daily:=v_remaining/greatest(v_days_remaining,1);
  select coalesce(sum(amount),0) into v_today_spending from public.expenses where profile_id=v_profile_id and budget_plan_id=v_plan.id and source in ('manual','recurring_purchase','team_shopping') and expense_date=current_date and voided_at is null;
  v_summary:=jsonb_build_object('days_total',v_days_total,'days_remaining',v_days_remaining,'total_spent',v_spent,'subscription_total',v_sub_total,'remaining_money',v_remaining,'safe_daily_limit',v_safe_daily,'today_spending',v_today_spending,'is_over_daily_limit',v_today_spending>v_safe_daily and v_days_remaining>0,'planned_recurring_total',v_planned_recurring,'actual_recurring_total',v_actual_recurring,'skipped_recurring_total',v_skipped_recurring,'skipped_recurring_count',v_skipped_count,'today_recurring_expected_total',v_today_expected,'today_recurring_purchased_total',v_today_purchased,'today_recurring_skipped_count',v_today_skipped_count);
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'item_name',e.item_name,'amount',e.amount,'category',e.category,'note',e.note,'expense_date',e.expense_date,'source',e.source) order by expense_date desc,created_at desc),'[]'::jsonb) into v_recent from (select * from public.expenses where profile_id=v_profile_id and budget_plan_id=v_plan.id and voided_at is null order by expense_date desc,created_at desc limit 20) e;
  return jsonb_build_object('budget_plan',jsonb_build_object('id',v_plan.id,'total_money',v_plan.total_money,'start_date',v_plan.start_date,'end_date',v_plan.end_date,'note',v_plan.note,'is_active',v_plan.is_active),'summary',v_summary,'active_subscriptions',v_subs,'recent_expenses',v_recent);
end;
$$;

create or replace function public.remove_team_member(
  p_session_token text,
  p_membership_id uuid,
  p_reason text
) returns jsonb
language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare
  v_profile_id uuid; v_member public.team_members%rowtype; v_team public.teams%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason,'')), ''); v_next_pos int;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  if v_reason is null or length(v_reason)>300 then raise exception 'invalid removal reason'; end if;
  select * into v_member from public.team_members where id=p_membership_id for update;
  if not found then raise exception 'member not available'; end if;
  select * into v_team from public.teams where id=v_member.team_id for update;
  if not found or not exists (select 1 from public.team_members where team_id=v_member.team_id and profile_id=v_profile_id and role='leader' and is_active and removed_at is null) then raise exception 'member not available'; end if;
  if v_member.role='leader' then raise exception 'leader cannot be removed'; end if;
  if v_member.removed_at is not null then return jsonb_build_object('ok',true,'removed',false,'team',public.get_team_detail(p_session_token,v_member.team_id)); end if;
  update public.team_members set is_active=false,deactivated_at=coalesce(deactivated_at,now()),removed_at=now(),removed_by=v_profile_id,removal_reason=v_reason,updated_at=now() where id=v_member.id;
  if v_team.current_position=v_member.position then
    select position into v_next_pos from public.team_members where team_id=v_member.team_id and position>v_member.position and is_active and removed_at is null order by position limit 1;
    if v_next_pos is null then select position into v_next_pos from public.team_members where team_id=v_member.team_id and is_active and removed_at is null order by position limit 1; end if;
    update public.teams set current_position=v_next_pos,updated_at=now() where id=v_member.team_id;
  end if;
  return jsonb_build_object('ok',true,'removed',true,'team',public.get_team_detail(p_session_token,v_member.team_id));
end;
$$;

revoke all on function public.delete_expense(text,uuid) from public, anon, authenticated;
revoke all on function public.void_expense(text,uuid,text) from public, authenticated;
grant execute on function public.void_expense(text,uuid,text) to anon;
revoke all on function public.remove_team_member(text,uuid,uuid) from public, anon, authenticated;
revoke all on function public.remove_team_member(text,uuid,text) from public, authenticated;
grant execute on function public.remove_team_member(text,uuid,text) to anon;
revoke all on function public.update_expense(text,uuid,text,numeric,text,text,date) from public, authenticated;
grant execute on function public.update_expense(text,uuid,text,numeric,text,text,date) to anon;
revoke all on function public.get_budget_overview(text) from public, authenticated;
grant execute on function public.get_budget_overview(text) to anon;
