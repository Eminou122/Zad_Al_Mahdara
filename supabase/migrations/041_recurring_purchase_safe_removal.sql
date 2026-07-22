-- Gate 53.3D1: retain recurring history; void financial effects instead of deleting them.
alter table public.recurring_purchase_occurrences
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references public.profiles(id) on delete restrict,
  add column if not exists void_reason text;
alter table public.recurring_purchase_occurrences add constraint recurring_occurrences_void_audit_check check (
  (voided_at is null and voided_by is null and void_reason is null) or
  (voided_at is not null and voided_by is not null and length(trim(void_reason)) between 1 and 300)
);

alter table public.recurring_purchases
  add column if not exists removed_at timestamptz,
  add column if not exists removed_by uuid references public.profiles(id) on delete restrict,
  add column if not exists removal_reason text;
alter table public.recurring_purchases add constraint recurring_purchases_removal_audit_check check (
  (removed_at is null and removed_by is null and removal_reason is null) or
  (removed_at is not null and removed_by is not null and length(trim(removal_reason)) between 1 and 300 and is_active = false)
);

-- There was no application audit-event relation before this gate.  This narrow,
-- append-only relation records only the transitions introduced here.
create table public.recurring_purchase_audit_events (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  recurring_purchase_id uuid not null references public.recurring_purchases(id) on delete restrict,
  occurrence_id uuid references public.recurring_purchase_occurrences(id) on delete restrict,
  event_type text not null check (event_type in ('occurrence_removed','definition_removed','purchased_skipped','skipped_purchased')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.recurring_purchase_audit_events enable row level security;
revoke all on public.recurring_purchase_audit_events from public, anon, authenticated;

create or replace function public.get_recurring_purchases(p_session_token text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_items jsonb;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select coalesce(jsonb_agg(jsonb_build_object('id',rp.id,'name',rp.name,'price',rp.price,'frequency',rp.frequency,'interval_days',rp.interval_days,'start_date',rp.start_date,'end_date',rp.end_date,'reminder_time',case when rp.reminder_time is null then null else to_char(rp.reminder_time,'HH24:MI') end,'note',rp.note,'is_active',rp.is_active) order by rp.start_date desc,rp.name),'[]'::jsonb) into v_items
  from public.recurring_purchases rp where rp.profile_id=v_profile_id and rp.is_active and rp.removed_at is null;
  return jsonb_build_object('items',v_items);
end $$;

create or replace function public.get_today_recurring_purchases(p_session_token text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_items jsonb;
begin
  v_profile_id := public.current_profile_id_from_session(p_session_token);
  select coalesce(jsonb_agg(jsonb_build_object('recurring_purchase_id',rp.id,'occurrence_id',o.id,'name',coalesce(o.expected_name,rp.name),'price',coalesce(o.expected_price,rp.price),'frequency',rp.frequency,'interval_days',rp.interval_days,'reminder_time',case when rp.reminder_time is null then null else to_char(rp.reminder_time,'HH24:MI') end,'note',coalesce(o.note,rp.note),'occurrence_date',current_date,'status',coalesce(o.status,'unmarked'),'is_voided',o.voided_at is not null,'voided_at',o.voided_at,'void_reason',o.void_reason,'expense_id',o.expense_id) order by rp.reminder_time nulls last,rp.name),'[]'::jsonb) into v_items
  from public.recurring_purchases rp
  left join public.recurring_purchase_occurrences o on o.recurring_purchase_id=rp.id and o.profile_id=v_profile_id and o.occurrence_date=current_date
  where rp.profile_id=v_profile_id and rp.is_active and rp.removed_at is null
    and public.recurring_purchase_matches_date(rp.frequency,rp.interval_days,rp.start_date,rp.end_date,current_date);
  return jsonb_build_object('items',v_items);
end $$;

create or replace function public.get_recurring_purchase_overview(p_session_token text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_plan public.budget_plans%rowtype; v_active_count int; v_today_expected numeric:=0; v_today_purchased numeric:=0; v_today_skipped_count int:=0; v_planned_total numeric:=0; v_actual_total numeric:=0; v_skipped_total numeric:=0; v_skipped_count int:=0; v_voided_count int:=0;
begin
  v_profile_id:=public.current_profile_id_from_session(p_session_token);
  select count(*) into v_active_count from public.recurring_purchases where profile_id=v_profile_id and is_active and removed_at is null;
  select coalesce(sum(price),0) into v_today_expected from public.recurring_purchases rp where rp.profile_id=v_profile_id and rp.is_active and rp.removed_at is null and public.recurring_purchase_matches_date(rp.frequency,rp.interval_days,rp.start_date,rp.end_date,current_date);
  select coalesce(sum(e.amount),0) into v_today_purchased from public.expenses e where e.profile_id=v_profile_id and e.source='recurring_purchase' and e.expense_date=current_date and e.voided_at is null;
  select count(*) into v_today_skipped_count from public.recurring_purchase_occurrences o where o.profile_id=v_profile_id and o.occurrence_date=current_date and o.status='skipped' and o.voided_at is null;
  select * into v_plan from public.budget_plans where profile_id=v_profile_id and is_active limit 1;
  if found then
    select coalesce(sum(x.price),0) into v_planned_total from (select rp.price from public.recurring_purchases rp cross join lateral generate_series(greatest(rp.start_date,v_plan.start_date),least(rp.end_date,v_plan.end_date),interval '1 day') g(day) where rp.profile_id=v_profile_id and rp.is_active and rp.removed_at is null and public.recurring_purchase_matches_date(rp.frequency,rp.interval_days,rp.start_date,rp.end_date,g.day::date)) x;
    select coalesce(sum(amount),0) into v_actual_total from public.expenses where profile_id=v_profile_id and source='recurring_purchase' and voided_at is null and expense_date between v_plan.start_date and v_plan.end_date;
    select coalesce(sum(expected_price),0),count(*) into v_skipped_total,v_skipped_count from public.recurring_purchase_occurrences where profile_id=v_profile_id and status='skipped' and voided_at is null and occurrence_date between v_plan.start_date and v_plan.end_date;
    select count(*) into v_voided_count from public.recurring_purchase_occurrences where profile_id=v_profile_id and voided_at is not null and occurrence_date between v_plan.start_date and v_plan.end_date;
  end if;
  return jsonb_build_object('active_recurring_count',v_active_count,'today_expected_total',v_today_expected,'today_purchased_total',v_today_purchased,'today_skipped_count',v_today_skipped_count,'planned_total',v_planned_total,'actual_purchased_total',v_actual_total,'skipped_total',v_skipped_total,'skipped_count',v_skipped_count,'voided_count',v_voided_count);
end $$;

create or replace function public.get_recurring_purchase_history(p_session_token text,p_recurring_purchase_id uuid default null,p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_limit int:=greatest(1,least(coalesce(p_limit,50),100)); v_offset int:=greatest(0,coalesce(p_offset,0)); v_items jsonb; v_total int;
begin
  v_profile_id:=public.current_profile_id_from_session(p_session_token);
  if p_recurring_purchase_id is not null and not exists(select 1 from public.recurring_purchases where id=p_recurring_purchase_id and profile_id=v_profile_id) then raise exception 'recurring purchase not found'; end if;
  select count(*) into v_total from public.recurring_purchase_occurrences o where o.profile_id=v_profile_id and (p_recurring_purchase_id is null or o.recurring_purchase_id=p_recurring_purchase_id);
  select coalesce(jsonb_agg(jsonb_build_object('occurrence_id',o.id,'recurring_purchase_id',o.recurring_purchase_id,'name',o.expected_name,'price',o.expected_price,'occurrence_date',o.occurrence_date,'status',o.status,'is_voided',o.voided_at is not null,'void_reason',o.void_reason,'voided_at',o.voided_at,'expense_id',o.expense_id,'definition_removed',rp.removed_at is not null) order by o.occurrence_date desc,o.created_at desc),'[]'::jsonb) into v_items from (select * from public.recurring_purchase_occurrences where profile_id=v_profile_id and (p_recurring_purchase_id is null or recurring_purchase_id=p_recurring_purchase_id) order by occurrence_date desc,created_at desc limit v_limit offset v_offset) o join public.recurring_purchases rp on rp.id=o.recurring_purchase_id;
  return jsonb_build_object('items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset);
end $$;

create or replace function public.mark_recurring_purchase_occurrence(p_session_token text,p_recurring_purchase_id uuid,p_occurrence_date date,p_status text,p_note text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_purchase public.recurring_purchases%rowtype; v_occurrence public.recurring_purchase_occurrences%rowtype; v_expense public.expenses%rowtype; v_plan_id uuid; v_expense_id uuid; v_changed boolean:=false;
begin
  v_profile_id:=public.current_profile_id_from_session(p_session_token);
  if p_status not in ('purchased','skipped') then raise exception 'status invalid'; end if;
  if p_note is not null and length(p_note)>300 then raise exception 'note too long'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_recurring_purchase_id::text||':'||p_occurrence_date::text,0));
  select * into v_purchase from public.recurring_purchases where id=p_recurring_purchase_id and profile_id=v_profile_id and is_active and removed_at is null for update;
  if not found then raise exception 'recurring purchase not found'; end if;
  if not public.recurring_purchase_matches_date(v_purchase.frequency,v_purchase.interval_days,v_purchase.start_date,v_purchase.end_date,p_occurrence_date) then raise exception 'occurrence_date does not match frequency'; end if;
  insert into public.recurring_purchase_occurrences(recurring_purchase_id,profile_id,occurrence_date,status,expected_name,expected_price,note) values(p_recurring_purchase_id,v_profile_id,p_occurrence_date,p_status,v_purchase.name,v_purchase.price,p_note) on conflict(recurring_purchase_id,occurrence_date) do nothing;
  select * into v_occurrence from public.recurring_purchase_occurrences where recurring_purchase_id=p_recurring_purchase_id and profile_id=v_profile_id and occurrence_date=p_occurrence_date for update;
  if v_occurrence.voided_at is not null then raise exception 'removed history cannot be restored through ordinary mark'; end if;
  if v_occurrence.expense_id is not null then select * into v_expense from public.expenses where id=v_occurrence.expense_id and profile_id=v_profile_id and source='recurring_purchase' for update; if not found then raise exception 'linked expense unavailable'; end if; end if;
  if p_status='skipped' and v_occurrence.status='purchased' then
    if v_occurrence.expense_id is null or v_expense.voided_at is not null then raise exception 'linked expense unavailable'; end if;
    update public.expenses set voided_at=now(),voided_by=v_profile_id,void_reason='recurring purchase skipped',updated_at=now() where id=v_expense.id;
    update public.recurring_purchase_occurrences set status='skipped',note=p_note,updated_at=now(),marked_at=now() where id=v_occurrence.id;
    insert into public.recurring_purchase_audit_events(profile_id,recurring_purchase_id,occurrence_id,event_type,payload) values(v_profile_id,p_recurring_purchase_id,v_occurrence.id,'purchased_skipped',jsonb_build_object('expense_id',v_expense.id,'before','purchased','after','skipped'));
  elsif p_status='purchased' and v_occurrence.status='skipped' then
    if v_occurrence.expense_id is not null then
      if v_expense.voided_at is null then raise exception 'linked expense unavailable'; end if;
      update public.expenses set voided_at=null,voided_by=null,void_reason=null,updated_at=now() where id=v_expense.id;
      v_expense_id:=v_expense.id;
    else
      select id into v_plan_id from public.budget_plans where profile_id=v_profile_id and is_active and p_occurrence_date between start_date and end_date limit 1;
      insert into public.expenses(profile_id,budget_plan_id,source,item_name,amount,category,note,expense_date) values(v_profile_id,v_plan_id,'recurring_purchase',v_purchase.name,v_purchase.price,'متكرر',coalesce(p_note,v_purchase.note),p_occurrence_date) returning id into v_expense_id;
      update public.recurring_purchase_occurrences set expense_id=v_expense_id where id=v_occurrence.id;
    end if;
    update public.recurring_purchase_occurrences set status='purchased',note=p_note,updated_at=now(),marked_at=now() where id=v_occurrence.id;
    insert into public.recurring_purchase_audit_events(profile_id,recurring_purchase_id,occurrence_id,event_type,payload) values(v_profile_id,p_recurring_purchase_id,v_occurrence.id,'skipped_purchased',jsonb_build_object('expense_id',v_expense_id,'before','skipped','after','purchased'));
  elsif p_status='purchased' and v_occurrence.status='purchased' then
    if v_occurrence.expense_id is null then
      select id into v_plan_id from public.budget_plans where profile_id=v_profile_id and is_active and p_occurrence_date between start_date and end_date limit 1;
      insert into public.expenses(profile_id,budget_plan_id,source,item_name,amount,category,note,expense_date) values(v_profile_id,v_plan_id,'recurring_purchase',v_purchase.name,v_purchase.price,'متكرر',coalesce(p_note,v_purchase.note),p_occurrence_date) returning id into v_expense_id;
      update public.recurring_purchase_occurrences set expense_id=v_expense_id,updated_at=now(),marked_at=now() where id=v_occurrence.id;
    elsif v_expense.voided_at is not null then raise exception 'linked expense unavailable'; end if;
  end if;
  return public.get_today_recurring_purchases(p_session_token);
end $$;

create or replace function public.remove_recurring_purchase_occurrence(p_session_token text,p_recurring_purchase_id uuid,p_occurrence_date date,p_reason text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_reason text:=nullif(trim(coalesce(p_reason,'')), ''); v_occurrence public.recurring_purchase_occurrences%rowtype; v_expense public.expenses%rowtype; v_removed boolean:=false;
begin
  v_profile_id:=public.current_profile_id_from_session(p_session_token); if v_reason is null or length(v_reason)>300 then raise exception 'invalid removal reason'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_recurring_purchase_id::text||':'||p_occurrence_date::text,0));
  perform 1 from public.recurring_purchases where id=p_recurring_purchase_id and profile_id=v_profile_id for update; if not found then raise exception 'recurring purchase not found'; end if;
  select * into v_occurrence from public.recurring_purchase_occurrences where recurring_purchase_id=p_recurring_purchase_id and profile_id=v_profile_id and occurrence_date=p_occurrence_date for update;
  if not found or v_occurrence.status<>'purchased' then raise exception 'purchased occurrence not available'; end if;
  if v_occurrence.voided_at is null then
    if v_occurrence.expense_id is null then raise exception 'linked expense unavailable'; end if;
    select * into v_expense from public.expenses where id=v_occurrence.expense_id and profile_id=v_profile_id and source='recurring_purchase' and expense_date=p_occurrence_date for update;
    if not found or v_expense.voided_at is not null then raise exception 'linked expense unavailable'; end if;
    update public.recurring_purchase_occurrences set voided_at=now(),voided_by=v_profile_id,void_reason=v_reason,updated_at=now() where id=v_occurrence.id;
    update public.expenses set voided_at=now(),voided_by=v_profile_id,void_reason=v_reason,updated_at=now() where id=v_expense.id;
    insert into public.recurring_purchase_audit_events(profile_id,recurring_purchase_id,occurrence_id,event_type,payload) values(v_profile_id,p_recurring_purchase_id,v_occurrence.id,'occurrence_removed',jsonb_build_object('expense_id',v_expense.id,'reason',v_reason)); v_removed:=true;
  end if;
  return jsonb_build_object('ok',true,'removed',v_removed,'today_items',public.get_today_recurring_purchases(p_session_token)->'items','history',public.get_recurring_purchase_history(p_session_token,p_recurring_purchase_id,50,0),'budget_overview',public.get_budget_overview(p_session_token),'recurring_statistics',public.get_recurring_purchase_overview(p_session_token));
end $$;

create or replace function public.remove_recurring_purchase(p_session_token text,p_recurring_purchase_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = 'public', 'extensions' as $$
declare v_profile_id uuid; v_reason text:=nullif(trim(coalesce(p_reason,'')), ''); v_purchase public.recurring_purchases%rowtype; v_removed boolean:=false;
begin
  v_profile_id:=public.current_profile_id_from_session(p_session_token); if v_reason is null or length(v_reason)>300 then raise exception 'invalid removal reason'; end if;
  select * into v_purchase from public.recurring_purchases where id=p_recurring_purchase_id and profile_id=v_profile_id for update; if not found then raise exception 'recurring purchase not found'; end if;
  if v_purchase.removed_at is null then update public.recurring_purchases set is_active=false,removed_at=now(),removed_by=v_profile_id,removal_reason=v_reason,updated_at=now() where id=v_purchase.id; insert into public.recurring_purchase_audit_events(profile_id,recurring_purchase_id,event_type,payload) values(v_profile_id,v_purchase.id,'definition_removed',jsonb_build_object('reason',v_reason)); v_removed:=true; end if;
  return jsonb_build_object('ok',true,'removed',v_removed,'recurring_purchases',public.get_recurring_purchases(p_session_token)->'items','recurring_statistics',public.get_recurring_purchase_overview(p_session_token));
end $$;

revoke all on function public.get_recurring_purchases(text), public.get_today_recurring_purchases(text), public.get_recurring_purchase_overview(text), public.get_recurring_purchase_history(text,uuid,integer,integer), public.mark_recurring_purchase_occurrence(text,uuid,date,text,text), public.remove_recurring_purchase_occurrence(text,uuid,date,text), public.remove_recurring_purchase(text,uuid,text) from public, authenticated;
grant execute on function public.get_recurring_purchases(text), public.get_today_recurring_purchases(text), public.get_recurring_purchase_overview(text), public.get_recurring_purchase_history(text,uuid,integer,integer), public.mark_recurring_purchase_occurrence(text,uuid,date,text,text), public.remove_recurring_purchase_occurrence(text,uuid,date,text), public.remove_recurring_purchase(text,uuid,text) to anon;
