-- Gate 52.1A-Fix: Messaging read cursor and RPC grant hardening.
--
-- Compatibility rule for rows created by migration 033:
-- if last_read_message_id can be resolved to the greatest incoming message at
-- exactly last_read_at, store it. Otherwise leave it null and treat the row as
-- lacking a safe compound cursor, which may show old messages unread rather
-- than incorrectly hiding unseen messages.

alter table public.team_conversation_reads
  add column if not exists last_read_message_id uuid null
    references public.team_messages(id) on delete set null;

update public.team_conversation_reads r
set last_read_message_id = (
  select m.id
  from public.team_messages m
  where m.conversation_id = r.conversation_id
    and m.archived_at is null
    and m.sender_profile_id <> r.profile_id
    and m.created_at = r.last_read_at
  order by m.created_at desc, m.id desc
  limit 1
)
where r.last_read_message_id is null;

create or replace function public.get_my_team_conversations(
  p_session_token       text,
  p_limit               integer default 50,
  p_before_updated_at   timestamptz default null,
  p_before_id           uuid default null,
  p_unread_only         boolean default false
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
  v_last_updated_at timestamptz;
  v_last_id         uuid;
  v_next_cursor     jsonb := null;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  v_limit := greatest(least(coalesce(p_limit, 50), 100), 1);

  with eligible as (
    select
      tc.id, tc.team_id, tc.member_profile_id, tc.updated_at,
      case when tc.member_profile_id = v_profile_id then 'member' else 'leader' end as current_user_role
    from team_conversations tc
    where tc.archived_at is null
      and (
        (
          tc.member_profile_id = v_profile_id
          and exists(
            select 1 from team_members tm
            where tm.team_id = tc.team_id and tm.profile_id = v_profile_id
              and tm.is_active = true and tm.removed_at is null
          )
        )
        or tc.team_id in (
          select tm2.team_id from team_members tm2
          where tm2.profile_id = v_profile_id and tm2.role = 'leader'
            and tm2.is_active = true and tm2.removed_at is null
        )
      )
  ),
  enriched as (
    select
      e.id, e.team_id, e.member_profile_id, e.updated_at, e.current_user_role,
      t.name as team_name,
      p.display_name as member_name,
      (
        select m.body from team_messages m
        where m.conversation_id = e.id and m.archived_at is null
        order by m.created_at desc, m.id desc limit 1
      ) as latest_message_body,
      (
        select m.created_at from team_messages m
        where m.conversation_id = e.id and m.archived_at is null
        order by m.created_at desc, m.id desc limit 1
      ) as latest_message_at,
      (
        select count(*) from team_messages m
        left join team_conversation_reads r
          on r.conversation_id = e.id and r.profile_id = v_profile_id
        where m.conversation_id = e.id and m.archived_at is null
          and m.sender_profile_id <> v_profile_id
          and (
            r.profile_id is null
            or r.last_read_message_id is null
            or (m.created_at, m.id) > (r.last_read_at, r.last_read_message_id)
          )
      ) as unread_count
    from eligible e
    join teams t on t.id = e.team_id and t.is_active = true
    join profiles p on p.id = e.member_profile_id
  )
  select
    coalesce(jsonb_agg(x.item order by x.updated_at desc, x.id desc) filter (where x.rn <= v_limit), '[]'::jsonb),
    coalesce(bool_or(x.rn > v_limit), false),
    max(x.updated_at) filter (where x.rn = v_limit),
    (array_agg(x.id) filter (where x.rn = v_limit))[1]
  into v_items, v_has_more, v_last_updated_at, v_last_id
  from (
    select
      en.id, en.updated_at,
      row_number() over (order by en.updated_at desc, en.id desc) as rn,
      jsonb_build_object(
        'id',                     en.id,
        'team_id',                en.team_id,
        'team_name',              en.team_name,
        'member_profile_id',      en.member_profile_id,
        'member_name',            en.member_name,
        'latest_message_preview', left(en.latest_message_body, 140),
        'latest_message_at',      en.latest_message_at,
        'unread_count',           en.unread_count,
        'current_user_role',      en.current_user_role
      ) as item
    from enriched en
    where (not p_unread_only or en.unread_count > 0)
      and (
        p_before_updated_at is null
        or (p_before_id is null and en.updated_at < p_before_updated_at)
        or (p_before_id is not null and (en.updated_at, en.id) < (p_before_updated_at, p_before_id))
      )
    order by en.updated_at desc, en.id desc
    limit v_limit + 1
  ) x;

  if v_has_more and v_last_updated_at is not null then
    v_next_cursor := jsonb_build_object('updated_at', v_last_updated_at, 'id', v_last_id);
  end if;

  return jsonb_build_object(
    'items',       v_items,
    'has_more',    v_has_more,
    'next_cursor', v_next_cursor
  );
end;
$$;

create or replace function public.get_team_conversation_messages(
  p_session_token      text,
  p_conversation_id    uuid,
  p_limit              integer default 50,
  p_before_created_at  timestamptz default null,
  p_before_id          uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id           uuid;
  v_conv                 team_conversations%rowtype;
  v_leader_id            uuid;
  v_is_leader            boolean;
  v_is_member            boolean;
  v_last_read_at         timestamptz;
  v_last_read_message_id uuid;
  v_limit                int;
  v_items                jsonb;
  v_has_more             boolean;
  v_last_created_at      timestamptz;
  v_last_id              uuid;
  v_next_cursor          jsonb := null;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_conv from team_conversations where id = p_conversation_id and archived_at is null;
  if not found then
    raise exception 'conversation not found';
  end if;

  if not exists(select 1 from teams where id = v_conv.team_id and is_active = true) then
    raise exception 'conversation not found';
  end if;

  v_leader_id := current_team_leader_profile_id(v_conv.team_id);
  v_is_leader := (v_leader_id is not null and v_leader_id = v_profile_id);
  v_is_member := (
    v_conv.member_profile_id = v_profile_id
    and exists(
      select 1 from team_members
      where team_id = v_conv.team_id and profile_id = v_profile_id
        and is_active = true and removed_at is null
    )
  );

  if not (v_is_leader or v_is_member) then
    raise exception 'غير مصرح لك بعرض هذه المحادثة';
  end if;

  select last_read_at, last_read_message_id
  into v_last_read_at, v_last_read_message_id
  from team_conversation_reads
  where conversation_id = p_conversation_id and profile_id = v_profile_id;

  v_limit := greatest(least(coalesce(p_limit, 50), 50), 1);

  select
    coalesce(jsonb_agg(t.item order by t.created_at desc, t.id desc) filter (where t.rn <= v_limit), '[]'::jsonb),
    coalesce(bool_or(t.rn > v_limit), false),
    max(t.created_at) filter (where t.rn = v_limit),
    (array_agg(t.id) filter (where t.rn = v_limit))[1]
  into v_items, v_has_more, v_last_created_at, v_last_id
  from (
    select
      m.id, m.created_at,
      row_number() over (order by m.created_at desc, m.id desc) as rn,
      jsonb_build_object(
        'id',                m.id,
        'conversation_id',   m.conversation_id,
        'sender_profile_id', m.sender_profile_id,
        'sender_name',       p.display_name,
        'sender_role',       case when m.sender_profile_id = v_leader_id then 'leader' else 'member' end,
        'body',              m.body,
        'created_at',        m.created_at,
        'is_read',           (m.sender_profile_id = v_profile_id)
                             or (
                               v_last_read_message_id is not null
                               and (m.created_at, m.id) <= (v_last_read_at, v_last_read_message_id)
                             )
      ) as item
    from team_messages m
    join profiles p on p.id = m.sender_profile_id
    where m.conversation_id = p_conversation_id
      and m.archived_at is null
      and (
        p_before_created_at is null
        or (p_before_id is null and m.created_at < p_before_created_at)
        or (p_before_id is not null and (m.created_at, m.id) < (p_before_created_at, p_before_id))
      )
    order by m.created_at desc, m.id desc
    limit v_limit + 1
  ) t;

  if v_has_more and v_last_created_at is not null then
    v_next_cursor := jsonb_build_object('created_at', v_last_created_at, 'id', v_last_id);
  end if;

  return jsonb_build_object(
    'conversation_id', p_conversation_id,
    'items',           v_items,
    'has_more',        v_has_more,
    'next_cursor',     v_next_cursor
  );
end;
$$;

create or replace function public.mark_team_conversation_read(
  p_session_token   text,
  p_conversation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id           uuid;
  v_conv                 team_conversations%rowtype;
  v_leader_id            uuid;
  v_is_leader            boolean;
  v_is_member            boolean;
  v_last_read_at         timestamptz;
  v_last_read_message_id uuid;
  v_unread_count         integer;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_conv from team_conversations where id = p_conversation_id and archived_at is null;
  if not found then
    raise exception 'conversation not found';
  end if;

  if not exists(select 1 from teams where id = v_conv.team_id and is_active = true) then
    raise exception 'conversation not found';
  end if;

  v_leader_id := current_team_leader_profile_id(v_conv.team_id);
  v_is_leader := (v_leader_id is not null and v_leader_id = v_profile_id);
  v_is_member := (
    v_conv.member_profile_id = v_profile_id
    and exists(
      select 1 from team_members
      where team_id = v_conv.team_id and profile_id = v_profile_id
        and is_active = true and removed_at is null
    )
  );

  if not (v_is_leader or v_is_member) then
    raise exception 'غير مصرح لك بتحديث حالة القراءة لهذه المحادثة';
  end if;

  select m.created_at, m.id
  into v_last_read_at, v_last_read_message_id
  from team_messages m
  where m.conversation_id = p_conversation_id
    and m.archived_at is null
    and m.sender_profile_id <> v_profile_id
  order by m.created_at desc, m.id desc
  limit 1;

  if v_last_read_at is null then
    v_last_read_at := '-infinity'::timestamptz;
  end if;

  insert into team_conversation_reads (conversation_id, profile_id, last_read_at, last_read_message_id)
  values (p_conversation_id, v_profile_id, v_last_read_at, v_last_read_message_id)
  on conflict (conversation_id, profile_id) do update
    set last_read_at = excluded.last_read_at,
        last_read_message_id = excluded.last_read_message_id
  returning last_read_at, last_read_message_id into v_last_read_at, v_last_read_message_id;

  select count(*) into v_unread_count
  from team_messages m
  where m.conversation_id = p_conversation_id
    and m.archived_at is null
    and m.sender_profile_id <> v_profile_id
    and (
      v_last_read_message_id is null
      or (m.created_at, m.id) > (v_last_read_at, v_last_read_message_id)
    );

  return jsonb_build_object(
    'conversation_id',        p_conversation_id,
    'last_read_at',           v_last_read_at,
    'last_read_message_id',   v_last_read_message_id,
    'unread_count',           v_unread_count
  );
end;
$$;

create or replace function public.get_my_messaging_unread_count(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id                   uuid;
  v_private_message_unread_count integer;
  v_announcement_unread_count    integer;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select coalesce(sum(unread.cnt), 0) into v_private_message_unread_count
  from (
    select
      (
        select count(*) from team_messages m
        left join team_conversation_reads r
          on r.conversation_id = tc.id and r.profile_id = v_profile_id
        where m.conversation_id = tc.id and m.archived_at is null
          and m.sender_profile_id <> v_profile_id
          and (
            r.profile_id is null
            or r.last_read_message_id is null
            or (m.created_at, m.id) > (r.last_read_at, r.last_read_message_id)
          )
      ) as cnt
    from team_conversations tc
    where tc.archived_at is null
      and exists(select 1 from teams where id = tc.team_id and is_active = true)
      and (
        (
          tc.member_profile_id = v_profile_id
          and exists(
            select 1 from team_members tm
            where tm.team_id = tc.team_id and tm.profile_id = v_profile_id
              and tm.is_active = true and tm.removed_at is null
          )
        )
        or tc.team_id in (
          select tm2.team_id from team_members tm2
          where tm2.profile_id = v_profile_id and tm2.role = 'leader'
            and tm2.is_active = true and tm2.removed_at is null
        )
      )
  ) unread;

  select count(*) into v_announcement_unread_count
  from team_announcements a
  where a.archived_at is null
    and exists(select 1 from teams where id = a.team_id and is_active = true)
    and exists(
      select 1 from team_members tm
      where tm.team_id = a.team_id and tm.profile_id = v_profile_id
        and tm.is_active = true and tm.removed_at is null
    )
    and not exists(
      select 1 from team_announcement_reads r
      where r.announcement_id = a.id and r.profile_id = v_profile_id
    );

  return jsonb_build_object(
    'private_message_unread_count', v_private_message_unread_count,
    'announcement_unread_count',    v_announcement_unread_count,
    'total_unread_count',           v_private_message_unread_count + v_announcement_unread_count
  );
end;
$$;

revoke all on function public.send_team_leader_message(text, uuid, text) from public;
revoke all on function public.send_team_leader_message(text, uuid, text) from authenticated;
grant execute on function public.send_team_leader_message(text, uuid, text) to anon;

revoke all on function public.leader_reply_team_message(text, uuid, text) from public;
revoke all on function public.leader_reply_team_message(text, uuid, text) from authenticated;
grant execute on function public.leader_reply_team_message(text, uuid, text) to anon;

revoke all on function public.get_my_team_conversations(text, integer, timestamptz, uuid, boolean) from public;
revoke all on function public.get_my_team_conversations(text, integer, timestamptz, uuid, boolean) from authenticated;
grant execute on function public.get_my_team_conversations(text, integer, timestamptz, uuid, boolean) to anon;

revoke all on function public.get_team_conversation_messages(text, uuid, integer, timestamptz, uuid) from public;
revoke all on function public.get_team_conversation_messages(text, uuid, integer, timestamptz, uuid) from authenticated;
grant execute on function public.get_team_conversation_messages(text, uuid, integer, timestamptz, uuid) to anon;

revoke all on function public.mark_team_conversation_read(text, uuid) from public;
revoke all on function public.mark_team_conversation_read(text, uuid) from authenticated;
grant execute on function public.mark_team_conversation_read(text, uuid) to anon;

revoke all on function public.create_team_announcement(text, uuid, text, text) from public;
revoke all on function public.create_team_announcement(text, uuid, text, text) from authenticated;
grant execute on function public.create_team_announcement(text, uuid, text, text) to anon;

revoke all on function public.get_my_team_announcements(text, uuid, integer, timestamptz, uuid, boolean) from public;
revoke all on function public.get_my_team_announcements(text, uuid, integer, timestamptz, uuid, boolean) from authenticated;
grant execute on function public.get_my_team_announcements(text, uuid, integer, timestamptz, uuid, boolean) to anon;

revoke all on function public.mark_team_announcement_read(text, uuid) from public;
revoke all on function public.mark_team_announcement_read(text, uuid) from authenticated;
grant execute on function public.mark_team_announcement_read(text, uuid) to anon;

revoke all on function public.get_my_messaging_unread_count(text) from public;
revoke all on function public.get_my_messaging_unread_count(text) from authenticated;
grant execute on function public.get_my_messaging_unread_count(text) to anon;

revoke execute on function public.current_team_leader_profile_id(uuid) from public;
revoke execute on function public.current_team_leader_profile_id(uuid) from anon;
revoke execute on function public.current_team_leader_profile_id(uuid) from authenticated;
