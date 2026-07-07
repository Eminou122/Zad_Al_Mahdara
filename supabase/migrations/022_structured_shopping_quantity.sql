-- Gate 40.1: Structured Shopping Quantity (backend only)
-- Adds an optional structured quantity (value + Hassaniya unit) alongside
-- the existing free-text quantity_note, which is never removed, backfilled,
-- or parsed. quantity_unit = 'mru_value' means "buy this many MRU worth of
-- the item" (a requested amount, e.g. "10 MRU زيت"), NOT a currency total
-- and NOT auto-linked to the existing price column (Gate 38) even though
-- the two may coincidentally match for loose/bulk items. No budget
-- integration, no expense creation, no totals in this gate.
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run.
-- Safe to re-apply (if not exists / create or replace).

-- ─── 1. team_shopping_items structured quantity columns ────────────────────
-- Both nullable and independent of each other except for the paired
-- check below: either both null (no structured quantity — quantity_note,
-- if any, remains the only quantity info) or both present together. A
-- bare number with no unit, or a bare unit with no number, is meaningless
-- and rejected at the RPC layer (see add/update below) as well as here.

alter table public.team_shopping_items
  add column if not exists quantity_value numeric(12,2) null
    check (quantity_value is null or quantity_value >= 0),
  add column if not exists quantity_unit text null
    check (quantity_unit is null or quantity_unit in ('kg', 'packet', 'can', 'piece', 'mru_value', 'other'));

alter table public.team_shopping_items
  drop constraint if exists team_shopping_items_quantity_pair_check;

alter table public.team_shopping_items
  add constraint team_shopping_items_quantity_pair_check
  check (
    (quantity_value is null and quantity_unit is null)
    or (quantity_value is not null and quantity_unit is not null)
  );

-- ─── 2. get_team_shopping_list ─────────────────────────────────────────────
-- Read-only. Same input signature as Gate 37.1 — item JSON gains
-- "quantity_value" and "quantity_unit". Old clients that ignore unknown
-- JSON keys are unaffected. can_mark (Gate 39, responsible-only),
-- can_edit_list (leader-based), responsible_member output, and price
-- (Gate 38) are all unchanged below.

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

  -- Today's (or p_date's) responsible member — read-only lookup against
  -- the existing turn system, whatever its status.
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

  -- Gate 39: responsible-only, no leader override.
  v_can_mark := v_responsible_profile_id is not null
    and v_responsible_profile_id = v_profile_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',             i.id,
      'name',           i.name,
      'quantity_note',  i.quantity_note,
      'quantity_value', i.quantity_value,
      'quantity_unit',  i.quantity_unit,
      'is_required',    i.is_required,
      'position',       i.position,
      'bought',         occ.id is not null,
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
    'items',              v_items
  );
end;
$$;

-- ─── 3. add_team_shopping_item ─────────────────────────────────────────────
-- Leader only. Trailing p_quantity_value/p_quantity_unit params keep old
-- (6-arg, post-Gate-38) calls working unchanged.
--
-- Postgres note: CREATE OR REPLACE FUNCTION only replaces a function whose
-- argument-type list matches exactly. Adding trailing parameters changes
-- that list, so without an explicit drop first, Postgres would keep the old
-- 6-arg function as a separate overload instead of retiring it. Dropping the
-- old signature first ensures every caller — old (6-arg, still deployed in
-- production) and new (8-arg) alike — resolves to this single function,
-- with the new params defaulting to null when omitted.

drop function if exists public.add_team_shopping_item(text, uuid, text, text, boolean, numeric);

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

  if p_quantity_unit is not null
     and p_quantity_unit not in ('kg', 'packet', 'can', 'piece', 'mru_value', 'other') then
    raise exception 'invalid quantity unit';
  end if;

  if p_quantity_value is not null and p_quantity_unit is null then
    raise exception 'quantity unit required when quantity value is set';
  end if;

  if p_quantity_unit is not null and p_quantity_value is null then
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
    p_quantity_value, p_quantity_unit
  );

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 4. update_team_shopping_item ──────────────────────────────────────────
-- Leader only. Trailing p_quantity_value/p_quantity_unit params keep old
-- (7-arg, post-Gate-38) calls working unchanged. Item must belong to the
-- team and still be active. Same drop-before-replace reasoning as
-- add_team_shopping_item above.

drop function if exists public.update_team_shopping_item(text, uuid, uuid, text, text, boolean, numeric);

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

  if p_quantity_unit is not null
     and p_quantity_unit not in ('kg', 'packet', 'can', 'piece', 'mru_value', 'other') then
    raise exception 'invalid quantity unit';
  end if;

  if p_quantity_value is not null and p_quantity_unit is null then
    raise exception 'quantity unit required when quantity value is set';
  end if;

  if p_quantity_unit is not null and p_quantity_value is null then
    raise exception 'quantity value required when quantity unit is set';
  end if;

  update team_shopping_items
  set name           = v_name,
      quantity_note  = v_note,
      is_required    = coalesce(p_is_required, true),
      price          = p_price,
      quantity_value = p_quantity_value,
      quantity_unit  = p_quantity_unit,
      updated_at     = now()
  where id = p_item_id and team_id = p_team_id and is_active = true;

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 5. Grants ──────────────────────────────────────────────────────────────
-- RPC-only access preserved: no table grants added. Re-grant execute for
-- the two changed (now 8-arg) function signatures; get_team_shopping_list's
-- signature is unchanged but its grant is re-confirmed here for completeness.

grant execute on function public.get_team_shopping_list(text, uuid, date)                                        to anon;
grant execute on function public.add_team_shopping_item(text, uuid, text, text, boolean, numeric, numeric, text) to anon;
grant execute on function public.update_team_shopping_item(text, uuid, uuid, text, text, boolean, numeric, numeric, text) to anon;
