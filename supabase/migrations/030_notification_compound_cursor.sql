-- Gate 50.1A-H: Notification Pagination Compound Cursor (backend only)
-- Fixes a live-reproduced defect in get_my_notifications (029): ordering is
-- (created_at desc, id desc) but the cursor only filtered on created_at.
-- When 2+ notifications for the same recipient share an identical
-- created_at (e.g. inserted in the same transaction) and a page boundary
-- falls inside that tie group, the leftover tied rows were permanently
-- skipped on every later page — not reordered, genuinely lost.
--
-- Fix: add an optional p_before_id uuid parameter and use a compound
-- (created_at, id) tuple comparison whenever it's supplied. Existing
-- callers that only ever pass p_before keep the old created_at-only
-- behavior (still tie-blind, but unchanged) via the default.
--
-- create or replace cannot turn a 4-argument function into a 5-argument
-- one in place — Postgres identifies a function by its full parameter
-- list, so "create or replace" with an added parameter creates a second,
-- overloaded function alongside the original rather than replacing it.
-- With both a (text,integer,timestamptz,boolean) and a (text,integer,
-- timestamptz,boolean,uuid) overload live, PostgREST (and any Postgres
-- caller relying on default values) faces an ambiguous call whenever the
-- request omits the last parameter, since either overload could match.
-- The old signature is therefore dropped explicitly before the new one is
-- created, guaranteeing exactly one get_my_notifications function exists
-- after this migration.

drop function if exists public.get_my_notifications(text, integer, timestamptz, boolean);

create or replace function public.get_my_notifications(
  p_session_token text,
  p_limit         integer default 50,
  p_before        timestamptz default null,
  p_unread_only   boolean default false,
  p_before_id     uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id      uuid;
  v_limit           int;
  v_items           jsonb;
  v_has_more        boolean;
  v_unread_count    integer;
  v_last_created_at timestamptz;
  v_last_id         uuid;
  v_next_cursor     jsonb := null;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  v_limit := greatest(least(coalesce(p_limit, 50), 100), 1);

  select count(*) into v_unread_count
  from notifications
  where recipient_profile_id = v_profile_id
    and archived_at is null
    and is_read = false;

  select
    coalesce(jsonb_agg(t.item order by t.created_at desc, t.id desc) filter (where t.rn <= v_limit), '[]'::jsonb),
    coalesce(bool_or(t.rn > v_limit), false),
    max(t.created_at) filter (where t.rn = v_limit),
    max(t.id) filter (where t.rn = v_limit)
  into v_items, v_has_more, v_last_created_at, v_last_id
  from (
    select
      n.id,
      n.created_at,
      row_number() over (order by n.created_at desc, n.id desc) as rn,
      jsonb_build_object(
        'id',                 n.id,
        'type',               n.type,
        'title',              n.title,
        'body',               n.body,
        'team_id',            n.team_id,
        'turn_id',            n.turn_id,
        'shopping_report_id', n.shopping_report_id,
        'action_type',        n.action_type,
        'action_payload',     n.action_payload,
        'is_read',            n.is_read,
        'read_at',            n.read_at,
        'created_at',         n.created_at
      ) as item
    from notifications n
    where n.recipient_profile_id = v_profile_id
      and n.archived_at is null
      and (not p_unread_only or n.is_read = false)
      and (
        p_before is null
        or (p_before_id is null and n.created_at < p_before)
        or (p_before_id is not null and (n.created_at, n.id) < (p_before, p_before_id))
      )
    order by n.created_at desc, n.id desc
    limit v_limit + 1
  ) t;

  if v_has_more and v_last_created_at is not null then
    v_next_cursor := jsonb_build_object(
      'created_at', v_last_created_at,
      'id',         v_last_id
    );
  end if;

  return jsonb_build_object(
    'items',        v_items,
    'unread_count', v_unread_count,
    'has_more',     v_has_more,
    'next_cursor',  v_next_cursor
  );
end;
$$;

grant execute on function public.get_my_notifications(text, integer, timestamptz, boolean, uuid) to anon;
