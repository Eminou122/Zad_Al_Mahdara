-- Gate 38.1: Optional Shopping Item Price (backend only)
-- Additive-only. Does NOT modify 001-019 migrations (auth, budget, teams,
-- turns, external students, admin, PIN reset, account settings, and the
-- shopping checklist foundation itself all untouched beyond the price
-- column/params added here).
-- No budget integration, no handover workflow, no notifications, no PDF
-- export, no totals, no money deduction in this gate — price is a plain
-- optional attribute on the item definition, nothing more.
-- Currency is implicit MRU; no currency column is added (matches every
-- other money column in this schema, none of which store a currency).
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run.
-- Safe to re-apply (if not exists / create or replace).

-- ─── 1. team_shopping_items.price ──────────────────────────────────────────
-- Nullable: existing rows become price = null, meaning "no price set", not
-- price = 0. Never backfilled.

alter table public.team_shopping_items
  add column if not exists price numeric(12,2) null
  check (price is null or price >= 0);

-- ─── 2. get_team_shopping_list ─────────────────────────────────────────────
-- Read-only. Same input signature as Gate 37.1 — only the returned item
-- JSON gains a "price" field. Old clients that ignore unknown JSON keys are
-- unaffected.

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

  v_can_mark := v_is_leader
    or (v_responsible_profile_id is not null and v_responsible_profile_id = v_profile_id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',             i.id,
      'name',           i.name,
      'quantity_note',  i.quantity_note,
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
-- Leader only. Trailing p_price param keeps old (5-arg) calls working
-- unchanged. p_price = null means "no price", not 0 — never coerced.
--
-- Postgres note: CREATE OR REPLACE FUNCTION only replaces a function whose
-- argument-type list matches exactly. Adding a trailing parameter changes
-- that list, so without an explicit drop first, Postgres would keep the old
-- 5-arg function as a separate overload (never learning about price) instead
-- of retiring it. Dropping the old signature first ensures every caller —
-- old (5-arg, still deployed in production) and new (6-arg) alike — resolves
-- to this single function, with p_price defaulting to null when omitted.

drop function if exists public.add_team_shopping_item(text, uuid, text, text, boolean);

create or replace function public.add_team_shopping_item(
  p_session_token text,
  p_team_id       uuid,
  p_name          text,
  p_quantity_note text default null,
  p_is_required   boolean default true,
  p_price         numeric default null
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

  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_shopping_items
  where team_id = p_team_id;

  insert into team_shopping_items(
    team_id, name, quantity_note, is_required, position, created_by, price
  ) values (
    p_team_id, v_name, v_note, coalesce(p_is_required, true), v_next_pos, v_profile_id, p_price
  );

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 4. update_team_shopping_item ──────────────────────────────────────────
-- Leader only. Trailing p_price param keeps old (6-arg) calls working
-- unchanged. Item must belong to the team and still be active.
-- Same drop-before-replace reasoning as add_team_shopping_item above.

drop function if exists public.update_team_shopping_item(text, uuid, uuid, text, text, boolean);

create or replace function public.update_team_shopping_item(
  p_session_token text,
  p_team_id       uuid,
  p_item_id       uuid,
  p_name          text,
  p_quantity_note text default null,
  p_is_required   boolean default true,
  p_price         numeric default null
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

  update team_shopping_items
  set name          = v_name,
      quantity_note = v_note,
      is_required   = coalesce(p_is_required, true),
      price         = p_price,
      updated_at    = now()
  where id = p_item_id and team_id = p_team_id and is_active = true;

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 5. Grants ──────────────────────────────────────────────────────────────
-- RPC-only access preserved: no table grants added, RLS/revoke-all on
-- team_shopping_items and team_shopping_item_occurrences unchanged from
-- Gate 37.1. Re-grant execute for the two changed (now 6/7-arg) function
-- signatures; get_team_shopping_list's signature is unchanged but its
-- grant is re-confirmed here for completeness.

grant execute on function public.get_team_shopping_list(text, uuid, date)                          to anon;
grant execute on function public.add_team_shopping_item(text, uuid, text, text, boolean, numeric)   to anon;
grant execute on function public.update_team_shopping_item(text, uuid, uuid, text, text, boolean, numeric) to anon;
