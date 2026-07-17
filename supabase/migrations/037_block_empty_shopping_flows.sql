-- Gate 53.3B5: reject empty shopping dispatch, reports, and completion.
-- Existing RPC signatures and valid zero-cost item behavior remain unchanged.

create or replace function public.team_shopping_item_is_valid(
  p_name text,
  p_quantity_value numeric,
  p_quantity_unit text
) returns boolean
language sql
immutable
set search_path = 'public', 'extensions'
as $$
  select
    length(trim(coalesce(p_name, ''))) between 1 and 80
    and (
      (p_quantity_value is null and p_quantity_unit is null)
      or (
        p_quantity_value is not null
        and p_quantity_value <> 'NaN'::numeric
        and p_quantity_value >= 0
        and p_quantity_unit in (
          'kg', 'packet', 'can', 'piece', 'mru_value', 'other'
        )
      )
    );
$$;

-- Lock every current item row before counting. FOR SHARE makes a concurrent
-- deactivate/update finish first or wait until the guarded transition commits.
create or replace function public.lock_valid_team_shopping_item_count(
  p_team_id uuid,
  p_exclude_item_id uuid default null
) returns integer
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_item team_shopping_items%rowtype;
  v_count integer := 0;
begin
  for v_item in
    select *
    from team_shopping_items
    where team_id = p_team_id
      and is_active = true
      and (p_exclude_item_id is null or id <> p_exclude_item_id)
    order by id
    for share
  loop
    if team_shopping_item_is_valid(
      v_item.name,
      v_item.quantity_value,
      v_item.quantity_unit
    ) then
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

create or replace function public.enforce_nonempty_shopping_turn()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_valid_item_count integer;
begin
  if tg_op = 'INSERT'
     or (new.status = 'completed' and old.status is distinct from 'completed') then
    v_valid_item_count :=
      lock_valid_team_shopping_item_count(new.team_id);

    if v_valid_item_count < 1 then
      raise exception 'أضف عنصرًا واحدًا على الأقل قبل مشاركة القائمة';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and new.status = 'completed'
     and old.status is distinct from 'completed'
     and not exists (
       select 1
       from team_shopping_reports r
       where r.team_id = new.team_id
         and r.report_date = new.turn_date
         and r.submitted_at is not null
         and r.leader_status = 'accepted'
     ) then
    raise exception 'يجب إرسال قائمة التسوق وقبولها من القائد قبل إكمال الدور';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_nonempty_shopping_turn_trigger
  on public.team_turns;
create trigger enforce_nonempty_shopping_turn_trigger
before insert or update of status on public.team_turns
for each row execute function public.enforce_nonempty_shopping_turn();

create or replace function public.enforce_nonempty_shopping_report()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_valid_item_count integer;
begin
  -- New submission and reject -> resubmit both enter pending. Acceptance is
  -- checked independently so stale or concurrently changed lists cannot be
  -- financially applied merely because an earlier submission passed.
  if new.submitted_at is not null
     and (
       tg_op = 'INSERT'
       or new.leader_status = 'pending'
       or new.leader_status = 'accepted'
     ) then
    v_valid_item_count :=
      lock_valid_team_shopping_item_count(new.team_id);

    if v_valid_item_count < 1 then
      raise exception 'لا يمكن إرسال تقرير فارغ';
    end if;

    if exists (
      select 1
      from team_shopping_items i
      left join team_shopping_item_occurrences occ
        on occ.team_shopping_item_id = i.id
       and occ.occurrence_date = new.report_date
      where i.team_id = new.team_id
        and i.is_active = true
        and team_shopping_item_is_valid(
          i.name,
          i.quantity_value,
          i.quantity_unit
        )
        and (
          (i.is_required and (occ.id is null or occ.status <> 'bought'))
          or (
            not i.is_required
            and (
              occ.id is null
              or occ.status not in ('bought', 'not_bought')
            )
          )
        )
    ) then
      raise exception 'لا يمكن إرسال تقرير غير مكتمل';
    end if;

    if not exists (
      select 1
      from team_shopping_items i
      join team_shopping_item_occurrences occ
        on occ.team_shopping_item_id = i.id
       and occ.occurrence_date = new.report_date
       and occ.status in ('bought', 'not_bought')
      where i.team_id = new.team_id
        and i.is_active = true
        and team_shopping_item_is_valid(
          i.name,
          i.quantity_value,
          i.quantity_unit
        )
    ) then
      raise exception 'لا يمكن إرسال تقرير فارغ';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_nonempty_shopping_report_trigger
  on public.team_shopping_reports;
create trigger enforce_nonempty_shopping_report_trigger
before insert or update of submitted_at, leader_status
on public.team_shopping_reports
for each row execute function public.enforce_nonempty_shopping_report();

-- A final valid item may be removed while no shopping flow is active. Once a
-- turn or pending report depends on the list, removing that final item fails.
create or replace function public.protect_last_active_shopping_item()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_old_valid boolean;
  v_new_valid boolean;
  v_remaining integer;
begin
  v_old_valid := old.is_active and team_shopping_item_is_valid(
    old.name,
    old.quantity_value,
    old.quantity_unit
  );
  v_new_valid := new.team_id = old.team_id
    and new.is_active
    and team_shopping_item_is_valid(
      new.name,
      new.quantity_value,
      new.quantity_unit
    );

  if v_old_valid and not v_new_valid then
    v_remaining :=
      lock_valid_team_shopping_item_count(old.team_id, old.id);

    if v_remaining < 1 and (
      exists (
        select 1
        from team_turns tt
        where tt.team_id = old.team_id
          and tt.status = 'pending'
      )
      or exists (
        select 1
        from team_shopping_reports r
        where r.team_id = old.team_id
          and r.submitted_at is not null
          and r.leader_status = 'pending'
      )
    ) then
      raise exception 'لا يمكن إزالة آخر عنصر أثناء وجود مهمة تسوق نشطة';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists protect_last_active_shopping_item_trigger
  on public.team_shopping_items;
create trigger protect_last_active_shopping_item_trigger
before update of team_id, name, quantity_value, quantity_unit, is_active
on public.team_shopping_items
for each row execute function public.protect_last_active_shopping_item();

revoke all on function public.team_shopping_item_is_valid(text, numeric, text)
  from public, anon, authenticated;
revoke all on function public.lock_valid_team_shopping_item_count(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.enforce_nonempty_shopping_turn()
  from public, anon, authenticated;
revoke all on function public.enforce_nonempty_shopping_report()
  from public, anon, authenticated;
revoke all on function public.protect_last_active_shopping_item()
  from public, anon, authenticated;
