-- Gate 52.4A: Messaging live presence and adaptive-sync RPC foundation.
--
-- This app uses custom PIN sessions, not Supabase Auth. Conversation activity
-- therefore stays behind SECURITY DEFINER RPCs instead of public Realtime
-- channels or Supabase Auth based Postgres changes subscriptions.

create table public.messaging_presence (
  profile_id     uuid        primary key references public.profiles(id) on delete cascade,
  session_id     uuid        null references public.app_sessions(id) on delete set null,
  last_active_at timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index messaging_presence_last_active_idx
  on public.messaging_presence(last_active_at desc);

alter table public.messaging_presence enable row level security;
revoke all on public.messaging_presence from public;
revoke all on public.messaging_presence from anon, authenticated;

create table public.team_conversation_typing (
  conversation_id uuid        not null references public.team_conversations(id) on delete cascade,
  profile_id      uuid        not null references public.profiles(id) on delete cascade,
  typing_until    timestamptz not null,
  updated_at      timestamptz not null default now(),
  primary key (conversation_id, profile_id)
);

create index team_conversation_typing_conversation_idx
  on public.team_conversation_typing(conversation_id, typing_until desc);

create index team_conversation_typing_cleanup_idx
  on public.team_conversation_typing(typing_until);

alter table public.team_conversation_typing enable row level security;
revoke all on public.team_conversation_typing from public;
revoke all on public.team_conversation_typing from anon, authenticated;

create or replace function public.messaging_session_context(
  p_session_token text
) returns table (
  profile_id uuid,
  session_id uuid
)
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_token_hash text;
begin
  v_token_hash := encode(digest(p_session_token, 'sha256'), 'hex');

  return query
  select p.id, s.id
  from public.app_sessions s
  join public.profiles p on p.id = s.profile_id
  where s.token_hash = v_token_hash
    and s.revoked_at is null
    and s.expires_at > now()
    and p.is_active = true
  limit 1;

  if not found then
    raise exception 'invalid session';
  end if;

  update public.app_sessions s
  set last_seen_at = now()
  where s.token_hash = v_token_hash;
end;
$$;

create or replace function public.authorize_team_conversation_live(
  p_session_token   text,
  p_conversation_id uuid
) returns table (
  caller_profile_id         uuid,
  caller_session_id         uuid,
  conversation_id           uuid,
  team_id                   uuid,
  member_profile_id         uuid,
  current_leader_id         uuid,
  is_leader                 boolean,
  is_member                 boolean,
  other_profile_id          uuid
)
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id   uuid;
  v_session_id   uuid;
  v_conv         public.team_conversations%rowtype;
  v_leader_id    uuid;
  v_is_leader    boolean;
  v_is_member    boolean;
  v_other_id     uuid;
begin
  select c.profile_id, c.session_id
  into v_profile_id, v_session_id
  from public.messaging_session_context(p_session_token) c;

  select *
  into v_conv
  from public.team_conversations tc
  where tc.id = p_conversation_id
    and tc.archived_at is null;

  if not found then
    raise exception 'conversation not found';
  end if;

  if not exists(
    select 1
    from public.teams t
    where t.id = v_conv.team_id
      and t.is_active = true
  ) then
    raise exception 'conversation not found';
  end if;

  v_leader_id := public.current_team_leader_profile_id(v_conv.team_id);
  v_is_leader := (v_leader_id is not null and v_leader_id = v_profile_id);
  v_is_member := (
    v_conv.member_profile_id = v_profile_id
    and exists(
      select 1
      from public.team_members tm
      where tm.team_id = v_conv.team_id
        and tm.profile_id = v_profile_id
        and tm.is_active = true
        and tm.removed_at is null
    )
  );

  if not (v_is_leader or v_is_member) then
    raise exception 'غير مصرح لك بعرض هذه المحادثة';
  end if;

  v_other_id := case
    when v_is_leader then v_conv.member_profile_id
    else v_leader_id
  end;

  return query
  select
    v_profile_id,
    v_session_id,
    v_conv.id,
    v_conv.team_id,
    v_conv.member_profile_id,
    v_leader_id,
    v_is_leader,
    v_is_member,
    v_other_id;
end;
$$;

create or replace function public.update_messaging_presence(
  p_session_token text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_session_id uuid;
  v_now        timestamptz := now();
begin
  select c.profile_id, c.session_id
  into v_profile_id, v_session_id
  from public.messaging_session_context(p_session_token) c;

  insert into public.messaging_presence (profile_id, session_id, last_active_at, updated_at)
  values (v_profile_id, v_session_id, v_now, v_now)
  on conflict (profile_id) do update
    set session_id     = excluded.session_id,
        last_active_at = excluded.last_active_at,
        updated_at     = excluded.updated_at;

  return jsonb_build_object(
    'profile_id',      v_profile_id,
    'last_active_at',  v_now,
    'server_time',     v_now
  );
end;
$$;

create or replace function public.get_conversation_live_state(
  p_session_token   text,
  p_conversation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_auth         record;
  v_now          timestamptz := now();
  v_online_after interval := interval '60 seconds';
  v_live_state   jsonb;
begin
  select *
  into v_auth
  from public.authorize_team_conversation_live(p_session_token, p_conversation_id);

  if v_auth.other_profile_id is null then
    return jsonb_build_object(
      'other_participant', null,
      'server_time',       v_now
    );
  end if;

  select jsonb_build_object(
    'profile_id',      p.id,
    'display_name',    p.display_name,
    'is_online',       (mp.last_active_at is not null and mp.last_active_at >= v_now - v_online_after),
    'last_active_at',  mp.last_active_at,
    'is_typing',       (ct.typing_until is not null and ct.typing_until > v_now),
    'typing_until',    ct.typing_until,
    'server_time',     v_now
  )
  into v_live_state
  from public.profiles p
  left join public.messaging_presence mp on mp.profile_id = p.id
  left join public.team_conversation_typing ct
    on ct.conversation_id = p_conversation_id
   and ct.profile_id = p.id
   and ct.typing_until > v_now
  where p.id = v_auth.other_profile_id
    and p.is_active = true;

  return jsonb_build_object(
    'other_participant', v_live_state,
    'server_time',       v_now
  );
end;
$$;

create or replace function public.set_conversation_typing(
  p_session_token   text,
  p_conversation_id uuid,
  p_is_typing       boolean
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_auth         record;
  v_now          timestamptz := now();
  v_typing_until timestamptz := null;
begin
  select *
  into v_auth
  from public.authorize_team_conversation_live(p_session_token, p_conversation_id);

  if coalesce(p_is_typing, false) then
    v_typing_until := v_now + interval '8 seconds';

    insert into public.team_conversation_typing (conversation_id, profile_id, typing_until, updated_at)
    values (p_conversation_id, v_auth.caller_profile_id, v_typing_until, v_now)
    on conflict (conversation_id, profile_id) do update
      set typing_until = excluded.typing_until,
          updated_at   = excluded.updated_at;
  else
    delete from public.team_conversation_typing ct
    where ct.conversation_id = p_conversation_id
      and ct.profile_id = v_auth.caller_profile_id;
  end if;

  return jsonb_build_object(
    'conversation_id', p_conversation_id,
    'is_typing',       coalesce(p_is_typing, false),
    'typing_until',    v_typing_until,
    'server_time',     v_now
  );
end;
$$;

create or replace function public.get_conversation_updates(
  p_session_token     text,
  p_conversation_id   uuid,
  p_after_created_at  timestamptz,
  p_after_id          uuid,
  p_limit             integer default 50
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_auth                 record;
  v_last_read_at         timestamptz;
  v_last_read_message_id uuid;
  v_limit                int;
  v_items                jsonb;
  v_unread_count         integer;
  v_newest_created_at    timestamptz;
  v_newest_id            uuid;
  v_newest_cursor        jsonb := null;
begin
  select *
  into v_auth
  from public.authorize_team_conversation_live(p_session_token, p_conversation_id);

  if (p_after_created_at is null) <> (p_after_id is null) then
    raise exception 'invalid conversation cursor';
  end if;

  select r.last_read_at, r.last_read_message_id
  into v_last_read_at, v_last_read_message_id
  from public.team_conversation_reads r
  where r.conversation_id = p_conversation_id
    and r.profile_id = v_auth.caller_profile_id;

  v_limit := greatest(least(coalesce(p_limit, 50), 100), 1);

  if p_after_created_at is null then
    select
      coalesce(jsonb_agg(x.item order by x.created_at asc, x.id asc), '[]'::jsonb),
      max(x.created_at),
      (array_agg(x.id order by x.created_at desc, x.id desc))[1]
    into v_items, v_newest_created_at, v_newest_id
    from (
      select
        m.id,
        m.created_at,
        jsonb_build_object(
          'id',                m.id,
          'conversation_id',   m.conversation_id,
          'sender_profile_id', m.sender_profile_id,
          'sender_name',       p.display_name,
          'sender_role',       case when m.sender_profile_id = v_auth.current_leader_id then 'leader' else 'member' end,
          'body',              m.body,
          'created_at',        m.created_at,
          'is_read',           (m.sender_profile_id = v_auth.caller_profile_id)
                               or (
                                 v_last_read_message_id is not null
                                 and (m.created_at, m.id) <= (v_last_read_at, v_last_read_message_id)
                               )
        ) as item
      from public.team_messages m
      join public.profiles p on p.id = m.sender_profile_id
      where m.conversation_id = p_conversation_id
        and m.archived_at is null
      order by m.created_at desc, m.id desc
      limit v_limit
    ) x;
  else
    select
      coalesce(jsonb_agg(x.item order by x.created_at asc, x.id asc), '[]'::jsonb),
      max(x.created_at),
      (array_agg(x.id order by x.created_at desc, x.id desc))[1]
    into v_items, v_newest_created_at, v_newest_id
    from (
      select
        m.id,
        m.created_at,
        jsonb_build_object(
          'id',                m.id,
          'conversation_id',   m.conversation_id,
          'sender_profile_id', m.sender_profile_id,
          'sender_name',       p.display_name,
          'sender_role',       case when m.sender_profile_id = v_auth.current_leader_id then 'leader' else 'member' end,
          'body',              m.body,
          'created_at',        m.created_at,
          'is_read',           (m.sender_profile_id = v_auth.caller_profile_id)
                               or (
                                 v_last_read_message_id is not null
                                 and (m.created_at, m.id) <= (v_last_read_at, v_last_read_message_id)
                               )
        ) as item
      from public.team_messages m
      join public.profiles p on p.id = m.sender_profile_id
      where m.conversation_id = p_conversation_id
        and m.archived_at is null
        and (m.created_at, m.id) > (p_after_created_at, p_after_id)
      order by m.created_at asc, m.id asc
      limit v_limit
    ) x;
  end if;

  if v_newest_created_at is not null then
    v_newest_cursor := jsonb_build_object('created_at', v_newest_created_at, 'id', v_newest_id);
  end if;

  select count(*)
  into v_unread_count
  from public.team_messages m
  where m.conversation_id = p_conversation_id
    and m.archived_at is null
    and m.sender_profile_id <> v_auth.caller_profile_id
    and (
      v_last_read_message_id is null
      or (m.created_at, m.id) > (v_last_read_at, v_last_read_message_id)
    );

  return jsonb_build_object(
    'conversation_id', p_conversation_id,
    'items',           v_items,
    'newest_cursor',   v_newest_cursor,
    'unread_count',    v_unread_count,
    'live_state',      public.get_conversation_live_state(p_session_token, p_conversation_id),
    'server_time',     now()
  );
end;
$$;

revoke all on function public.messaging_session_context(text) from public;
revoke all on function public.messaging_session_context(text) from anon;
revoke all on function public.messaging_session_context(text) from authenticated;

revoke all on function public.authorize_team_conversation_live(text, uuid) from public;
revoke all on function public.authorize_team_conversation_live(text, uuid) from anon;
revoke all on function public.authorize_team_conversation_live(text, uuid) from authenticated;

revoke all on function public.update_messaging_presence(text) from public;
revoke all on function public.update_messaging_presence(text) from authenticated;
grant execute on function public.update_messaging_presence(text) to anon;

revoke all on function public.get_conversation_live_state(text, uuid) from public;
revoke all on function public.get_conversation_live_state(text, uuid) from authenticated;
grant execute on function public.get_conversation_live_state(text, uuid) to anon;

revoke all on function public.set_conversation_typing(text, uuid, boolean) from public;
revoke all on function public.set_conversation_typing(text, uuid, boolean) from authenticated;
grant execute on function public.set_conversation_typing(text, uuid, boolean) to anon;

revoke all on function public.get_conversation_updates(text, uuid, timestamptz, uuid, integer) from public;
revoke all on function public.get_conversation_updates(text, uuid, timestamptz, uuid, integer) from authenticated;
grant execute on function public.get_conversation_updates(text, uuid, timestamptz, uuid, integer) to anon;
