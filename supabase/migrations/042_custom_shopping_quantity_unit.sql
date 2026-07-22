-- Clean team purchase units: replace the fixed unit enum with كغ/بكط/بطة/MRU
-- plus a required free-text "أخرى" (custom) unit. The previous hardcoded
-- allowlist ('kg','packet','can','piece','mru_value','other') cannot hold
-- arbitrary custom text, so this relaxes quantity_unit to any trimmed,
-- non-blank string (still paired with quantity_value, still length-capped).
-- Existing rows (including legacy 'piece' and bare 'other' values) already
-- satisfy the relaxed constraint and need no backfill.
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run.
-- Safe to re-apply (create or replace / constraint drop-then-add).

alter table public.team_shopping_items
  drop constraint if exists team_shopping_items_quantity_unit_check;

alter table public.team_shopping_items
  add constraint team_shopping_items_quantity_unit_check
  check (quantity_unit is null or length(trim(quantity_unit)) between 1 and 24);

create or replace function public.add_team_shopping_item(
  p_session_token   text,
  p_team_id         uuid,
  p_name            text,
  p_quantity_note   text default null,
  p_is_required     boolean default true,
  p_price           numeric default null,
  p_quantity_value  numeric default null,
  p_quantity_unit   text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_name       text;
  v_note       text;
  v_unit       text;
  v_next_pos   int;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'leader only';
  end if;

  v_name := trim(p_name);
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid item name';
  end if;

  v_note := nullif(trim(coalesce(p_quantity_note, '')), '');
  if v_note is not null and length(v_note) > 40 then
    raise exception 'invalid quantity note';
  end if;

  if p_price is not null and p_price < 0 then
    raise exception 'invalid price';
  end if;

  if p_quantity_value is not null and p_quantity_value < 0 then
    raise exception 'invalid quantity value';
  end if;

  v_unit := nullif(trim(coalesce(p_quantity_unit, '')), '');
  if v_unit is not null and length(v_unit) > 24 then
    raise exception 'invalid quantity unit';
  end if;

  if p_quantity_value is not null and v_unit is null then
    raise exception 'quantity unit required when quantity value is set';
  end if;

  if v_unit is not null and p_quantity_value is null then
    raise exception 'quantity value required when quantity unit is set';
  end if;

  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_shopping_items
  where team_id = p_team_id;

  insert into team_shopping_items(
    team_id, name, quantity_note, is_required, position, created_by, price,
    quantity_value, quantity_unit
  ) values (
    p_team_id, v_name, v_note, coalesce(p_is_required, true), v_next_pos, v_profile_id, p_price,
    p_quantity_value, v_unit
  );

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

create or replace function public.update_team_shopping_item(
  p_session_token   text,
  p_team_id         uuid,
  p_item_id         uuid,
  p_name            text,
  p_quantity_note   text default null,
  p_is_required     boolean default true,
  p_price           numeric default null,
  p_quantity_value  numeric default null,
  p_quantity_unit   text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_name       text;
  v_note       text;
  v_unit       text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) then
    raise exception 'leader only';
  end if;

  if not exists(
    select 1 from team_shopping_items
    where id = p_item_id and team_id = p_team_id and is_active = true
  ) then
    raise exception 'item not found';
  end if;

  v_name := trim(p_name);
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid item name';
  end if;

  v_note := nullif(trim(coalesce(p_quantity_note, '')), '');
  if v_note is not null and length(v_note) > 40 then
    raise exception 'invalid quantity note';
  end if;

  if p_price is not null and p_price < 0 then
    raise exception 'invalid price';
  end if;

  if p_quantity_value is not null and p_quantity_value < 0 then
    raise exception 'invalid quantity value';
  end if;

  v_unit := nullif(trim(coalesce(p_quantity_unit, '')), '');
  if v_unit is not null and length(v_unit) > 24 then
    raise exception 'invalid quantity unit';
  end if;

  if p_quantity_value is not null and v_unit is null then
    raise exception 'quantity unit required when quantity value is set';
  end if;

  if v_unit is not null and p_quantity_value is null then
    raise exception 'quantity value required when quantity unit is set';
  end if;

  update team_shopping_items
  set name           = v_name,
      quantity_note  = v_note,
      is_required    = coalesce(p_is_required, true),
      price          = p_price,
      quantity_value = p_quantity_value,
      quantity_unit  = v_unit,
      updated_at     = now()
  where id = p_item_id and team_id = p_team_id and is_active = true;

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

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
        and length(trim(coalesce(p_quantity_unit, ''))) between 1 and 24
      )
    );
$$;

grant execute on function public.add_team_shopping_item(text, uuid, text, text, boolean, numeric, numeric, text) to anon;
grant execute on function public.update_team_shopping_item(text, uuid, uuid, text, text, boolean, numeric, numeric, text) to anon;
