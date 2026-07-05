-- Gate 37.1: Team Lunch Shopping List / Purchase Checklist Foundation
-- Additive-only. Does NOT modify 001-018 migrations (auth, budget, teams,
-- turns, external students, admin, PIN reset, account settings all
-- untouched).
-- Not financial: no money/price fields, no approval workflow, no linkage
-- to budget_plans/expenses.
-- Apply manually: Supabase Dashboard → SQL Editor → Run.
-- Safe to re-apply (if not exists / create or replace). Never hard-deletes
-- team_shopping_items rows (deactivate only); occurrence rows are the only
-- thing ever deleted, and only to represent "unmarked", never as cleanup.

-- ─── 1. team_shopping_items ───────────────────────────────────────────────
-- Reusable, leader-managed checklist definition. Persists across days;
-- only the per-day "bought" state (below) resets.

create table if not exists public.team_shopping_items (
  id            uuid          primary key default gen_random_uuid(),
  team_id       uuid          not null references public.teams(id) on delete cascade,
  name          text          not null check (length(trim(name)) between 1 and 80),
  quantity_note text          null check (quantity_note is null or length(quantity_note) <= 40),
  is_required   boolean       not null default true,
  is_active     boolean       not null default true,
  position      int           not null,
  created_by    uuid          not null references public.profiles(id) on delete restrict,
  created_at    timestamptz   not null default now(),
  updated_at    timestamptz   not null default now()
);

create index if not exists team_shopping_items_team_active_idx
  on public.team_shopping_items(team_id, is_active, position);

-- ─── 2. team_shopping_item_occurrences ────────────────────────────────────
-- Per-day "bought" record. A row's mere existence for (item, date) IS the
-- bought signal — no reset job, no cron: a new day has no row yet, so it's
-- implicitly "not bought" again automatically. Mirrors the exact pattern
-- already proven by recurring_purchase_occurrences (Gate 7), minus any
-- price/expense linkage since this feature has none.

create table if not exists public.team_shopping_item_occurrences (
  id                    uuid        primary key default gen_random_uuid(),
  team_shopping_item_id uuid        not null references public.team_shopping_items(id) on delete cascade,
  occurrence_date       date        not null,
  status                text        not null default 'bought' check (status = 'bought'),
  marked_by             uuid        not null references public.profiles(id) on delete restrict,
  marked_at             timestamptz not null default now(),
  unique(team_shopping_item_id, occurrence_date)
);

create index if not exists team_shopping_item_occurrences_date_idx
  on public.team_shopping_item_occurrences(occurrence_date desc);

-- ─── 3. RLS: no direct table access — all goes through SECURITY DEFINER RPCs ─

alter table public.team_shopping_items            enable row level security;
alter table public.team_shopping_item_occurrences enable row level security;

revoke all on public.team_shopping_items            from anon, authenticated;
revoke all on public.team_shopping_item_occurrences from anon, authenticated;

-- ─── 4. get_team_shopping_list ────────────────────────────────────────────
-- Read-only. Never creates or mutates a team_turns row — "responsible
-- member" is looked up from whatever turn already exists for p_date, if any.
-- Membership check matches this gate's own spec literally: active
-- (is_active = true and removed_at is null) team membership is required to
-- view — slightly stricter than get_team_detail/get_team_turn_state's own
-- "removed_at is null only" visibility threshold, a deliberate choice to
-- follow this gate's explicit instructions rather than that precedent.

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
      'marked_at',      occ.marked_at
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

-- ─── 5. add_team_shopping_item ────────────────────────────────────────────
-- Leader only. Assigns the next position automatically.

create or replace function public.add_team_shopping_item(
  p_session_token text,
  p_team_id       uuid,
  p_name          text,
  p_quantity_note text default null,
  p_is_required   boolean default true
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

  select coalesce(max(position), 0) + 1 into v_next_pos
  from team_shopping_items
  where team_id = p_team_id;

  insert into team_shopping_items(
    team_id, name, quantity_note, is_required, position, created_by
  ) values (
    p_team_id, v_name, v_note, coalesce(p_is_required, true), v_next_pos, v_profile_id
  );

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 6. update_team_shopping_item ─────────────────────────────────────────
-- Leader only. Item must belong to the team and still be active.

create or replace function public.update_team_shopping_item(
  p_session_token text,
  p_team_id       uuid,
  p_item_id       uuid,
  p_name          text,
  p_quantity_note text default null,
  p_is_required   boolean default true
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

  update team_shopping_items
  set name          = v_name,
      quantity_note = v_note,
      is_required   = coalesce(p_is_required, true),
      updated_at    = now()
  where id = p_item_id and team_id = p_team_id and is_active = true;

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 7. deactivate_team_shopping_item ─────────────────────────────────────
-- Leader only. Soft-deactivate; never deletes the row or its occurrence
-- history.

create or replace function public.deactivate_team_shopping_item(
  p_session_token text,
  p_team_id       uuid,
  p_item_id       uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
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

  update team_shopping_items
  set is_active  = false,
      updated_at = now()
  where id = p_item_id and team_id = p_team_id;

  return get_team_shopping_list(p_session_token, p_team_id);
end;
$$;

-- ─── 8. mark_shopping_item_status ─────────────────────────────────────────
-- Today's responsible member (per team_turns) OR the active leader only.
-- p_bought = true upserts the day's occurrence row (idempotent: marking an
-- already-bought item bought again just refreshes marked_by/marked_at).
-- p_bought = false deletes it (idempotent: unmarking an unbought item is a
-- no-op, zero rows affected, no error). No money/price logic anywhere.

create or replace function public.mark_shopping_item_status(
  p_session_token text,
  p_team_id       uuid,
  p_item_id       uuid,
  p_bought        boolean,
  p_date          date default current_date
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id     uuid;
  v_is_leader      boolean;
  v_is_responsible boolean;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(
    select 1 from team_shopping_items
    where id = p_item_id and team_id = p_team_id and is_active = true
  ) then
    raise exception 'item not found';
  end if;

  select exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id and role = 'leader'
      and is_active = true and removed_at is null
  ) into v_is_leader;

  select exists(
    select 1
    from team_turns tt
    join team_members tm on tm.id = tt.member_id
    where tt.team_id = p_team_id and tt.turn_date = p_date
      and tm.profile_id = v_profile_id
  ) into v_is_responsible;

  if not v_is_leader and not v_is_responsible then
    raise exception 'not authorized to mark this item';
  end if;

  if p_bought then
    insert into team_shopping_item_occurrences(
      team_shopping_item_id, occurrence_date, marked_by
    ) values (
      p_item_id, p_date, v_profile_id
    )
    on conflict (team_shopping_item_id, occurrence_date)
    do update set marked_by = excluded.marked_by, marked_at = now();
  else
    delete from team_shopping_item_occurrences
    where team_shopping_item_id = p_item_id and occurrence_date = p_date;
  end if;

  return get_team_shopping_list(p_session_token, p_team_id, p_date);
end;
$$;

-- ─── 9. Grants ─────────────────────────────────────────────────────────────

grant execute on function public.get_team_shopping_list(text, uuid, date)               to anon;
grant execute on function public.add_team_shopping_item(text, uuid, text, text, boolean) to anon;
grant execute on function public.update_team_shopping_item(text, uuid, uuid, text, text, boolean) to anon;
grant execute on function public.deactivate_team_shopping_item(text, uuid, uuid)          to anon;
grant execute on function public.mark_shopping_item_status(text, uuid, uuid, boolean, date) to anon;
