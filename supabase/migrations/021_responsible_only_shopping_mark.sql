-- Gate 39.1: Responsible-Only Shopping Mark Permission (backend only)
-- Leader = organizer, can edit the list, but marking items bought/unbought
-- is the job of today's responsible member only. A leader who is not
-- today's responsible member no longer gets a can_mark/mark override.
-- If the leader IS today's responsible member, they can still mark — that
-- falls out of the responsible check alone, no leader-specific branch needed.
-- Preserves every other Gate 37/38 behavior (price field, can_edit_list,
-- responsible_member output, session/item validation, occurrence
-- insert/delete). Apply manually: Supabase Dashboard -> SQL Editor -> Run.
-- Safe to re-apply (create or replace).

-- ─── 1. get_team_shopping_list ─────────────────────────────────────────────
-- Same signature and output shape as Gate 38.1 — only v_can_mark's
-- computation changes: leader-or-responsible becomes responsible-only.

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

  v_can_mark := v_responsible_profile_id is not null
    and v_responsible_profile_id = v_profile_id;

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

-- ─── 2. mark_shopping_item_status ───────────────────────────────────────────
-- Same signature, session/item validation, p_date handling, occurrence
-- insert/delete, and returned get_team_shopping_list response as Gate 37.1.
-- Only the authorization check changes: leader-or-responsible becomes
-- responsible-only, so v_is_leader is no longer needed here.

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
    select 1
    from team_turns tt
    join team_members tm on tm.id = tt.member_id
    where tt.team_id = p_team_id and tt.turn_date = p_date
      and tm.profile_id = v_profile_id
  ) into v_is_responsible;

  if not v_is_responsible then
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

-- ─── 3. Grants ──────────────────────────────────────────────────────────────
-- RPC-only access preserved: no table grants added. Re-grant execute for
-- the two replaced functions (signatures unchanged from Gate 38.1/37.1).

grant execute on function public.get_team_shopping_list(text, uuid, date)               to anon;
grant execute on function public.mark_shopping_item_status(text, uuid, uuid, boolean, date) to anon;
