-- Gate 52.1: Leader/Member Messaging Backend Foundation (backend only, RPC-only access)
-- Adds controlled V1 team messaging: a private member<->current-leader
-- conversation per (team, member), and team-wide leader announcements.
-- This is NOT unrestricted user-to-user chat: a member may only ever reach
-- the current leader of a team they belong to, and a leader may only ever
-- reach members of a team they currently lead. There is no member<->member
-- messaging and no cross-team messaging anywhere in this migration.
--
-- Apply manually: Supabase Dashboard -> SQL Editor -> Run. Not applied by
-- this gate; local-only until explicitly approved.
--
-- ─── Design decisions (read before extending) ────────────────────────────
--
-- 1. Leadership is never copied onto a row. team_conversations stores only
--    (team_id, member_profile_id) -- never a leader_profile_id -- because
--    team leadership can change and a stored leader id would go stale. The
--    "current leader" is resolved live, every call, via the internal helper
--    current_team_leader_profile_id(team_id), which reads team_members
--    (role = 'leader', is_active = true, removed_at is null) at query time.
--    A former leader loses access the instant their role/active flag
--    changes; a new leader gains access to the existing conversation
--    history immediately -- because access is a live query, not a stored
--    grant. Same reasoning for team_announcements.author_profile_id: it
--    identifies who wrote it (historical fact), never who may manage it
--    (a live authorization check, done again on every read/write).
--
-- 2. Membership validity = team_members.is_active = true and removed_at is
--    null, the exact same "valid active member" test used everywhere else
--    in this schema (turns, shopping). Chosen V1 lifecycle policy:
--      * A member must be currently valid to SEND a new private message,
--        and must be currently valid to READ their own conversation.
--        Once removed/deactivated, that member's side of the conversation
--        freezes entirely (no new sends, no further reads) -- they no
--        longer have a "valid team relationship" to the leader, mirroring
--        how a private team is invisible to a non-member elsewhere in
--        this schema.
--      * The current leader always keeps READ access to a team's
--        conversations for operational audit, regardless of the member's
--        status. The leader may not SEND a new reply once the member is
--        no longer valid -- there is no one currently "there" to reply to,
--        and allowing it would mean messaging someone with no team
--        relationship, the same thing this gate forbids in the other
--        direction.
--      * Announcements: only members with a currently valid membership see
--        new announcements or may mark them read; removed/deactivated
--        members stop receiving them (both the notification fan-out and
--        get_my_team_announcements exclude them going forward). Already
--        delivered notifications/rows are not retroactively deleted.
--    This is intentionally the strictest reading of "not unrestricted
--    chat": nothing keeps working once a team relationship ends, except
--    the current leader's own audit read.
--
-- 3. team_conversations is keyed by (team_id, member_profile_id), not by a
--    specific team_members.id row. If a member is removed and later
--    re-added to the same team, they resume the same conversation thread
--    rather than starting a new one -- this is operational team
--    communication tied to the person+team pair, not a disposable chat
--    session.
--
-- 4. Read-state model: private conversations use a conversation-level
--    last_read_at per participant (team_conversation_reads), not a
--    per-message read row, because a conversation only ever has two
--    possible readers (the member and whoever currently leads) and a
--    single timestamp comparison is enough to compute unread counts
--    correctly and cheaply. Announcements fan out to every team member,
--    so team_announcement_reads stays a genuine per-(announcement,
--    profile) row set, as recommended.
--
-- 5. External-student team_members rows (profile_id is null, see Gate 11)
--    can never send or receive messages -- they have no account/session.
--    They are simply skipped wherever this migration loops over team
--    members to notify (mirrors the existing skip-not-raise pattern used
--    for turn/shopping notifications).
--
-- 6. Pagination: every list RPC here uses the compound (sort_column, id)
--    cursor pattern from day one (Gate 50.1A-H/H1 fixed this after the
--    fact for notifications; same-timestamp ties would otherwise silently
--    drop rows at a page boundary). uuid has no built-in max()/min()
--    aggregate, so the last-row id is read back via
--    array_agg(...) filter (...) [1], not max(id) -- exactly the Gate
--    50.1A-H1 hotfix shape.
--
-- 7. Deferred (not built here, tracked as future hardening): archiving a
--    shared conversation from one side only (messages must stay auditable
--    for both participants; no per-user hide), message editing, message
--    attachments/reactions, per-profile rate limiting, abuse
--    reporting/blocking, moderation.

-- ─── A. team_conversations ───────────────────────────────────────────────
-- One private member<->current-leader conversation per (team, member).

create table public.team_conversations (
  id                uuid        primary key default gen_random_uuid(),
  team_id           uuid        not null references public.teams(id) on delete cascade,
  member_profile_id uuid        not null references public.profiles(id) on delete restrict,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  archived_at       timestamptz null,
  unique (team_id, member_profile_id)
);

create index team_conversations_team_updated_idx
  on public.team_conversations(team_id, updated_at desc, id desc)
  where archived_at is null;

create index team_conversations_member_updated_idx
  on public.team_conversations(member_profile_id, updated_at desc, id desc)
  where archived_at is null;

alter table public.team_conversations enable row level security;
revoke all on public.team_conversations from anon, authenticated;

-- ─── B. team_messages ─────────────────────────────────────────────────────
-- No editing, no hard delete, no attachments/reactions in V1 (edited_at is
-- reserved for a future edit feature and is never set by any RPC here).

create table public.team_messages (
  id                 uuid        primary key default gen_random_uuid(),
  conversation_id    uuid        not null references public.team_conversations(id) on delete cascade,
  sender_profile_id  uuid        not null references public.profiles(id) on delete restrict,
  body               text        not null,
  created_at         timestamptz not null default now(),
  edited_at          timestamptz null,
  archived_at        timestamptz null,
  constraint team_messages_body_length_check
    check (length(trim(body)) between 1 and 2000)
);

create index team_messages_conversation_created_idx
  on public.team_messages(conversation_id, created_at desc, id desc)
  where archived_at is null;

create index team_messages_conversation_sender_idx
  on public.team_messages(conversation_id, sender_profile_id, created_at)
  where archived_at is null;

alter table public.team_messages enable row level security;
revoke all on public.team_messages from anon, authenticated;

-- ─── C. team_conversation_reads ───────────────────────────────────────────
-- Conversation-level last_read_at per participant (see design note 4).

create table public.team_conversation_reads (
  conversation_id uuid        not null references public.team_conversations(id) on delete cascade,
  profile_id      uuid        not null references public.profiles(id) on delete cascade,
  last_read_at    timestamptz not null,
  primary key (conversation_id, profile_id)
);

alter table public.team_conversation_reads enable row level security;
revoke all on public.team_conversation_reads from anon, authenticated;

-- ─── D. team_announcements ────────────────────────────────────────────────

create table public.team_announcements (
  id                 uuid        primary key default gen_random_uuid(),
  team_id            uuid        not null references public.teams(id) on delete cascade,
  author_profile_id  uuid        not null references public.profiles(id) on delete restrict,
  title              text        null,
  body               text        not null,
  created_at         timestamptz not null default now(),
  archived_at        timestamptz null,
  constraint team_announcements_title_length_check
    check (title is null or length(trim(title)) between 1 and 120),
  constraint team_announcements_body_length_check
    check (length(trim(body)) between 1 and 3000)
);

create index team_announcements_team_created_idx
  on public.team_announcements(team_id, created_at desc, id desc)
  where archived_at is null;

alter table public.team_announcements enable row level security;
revoke all on public.team_announcements from anon, authenticated;

-- ─── E. team_announcement_reads ───────────────────────────────────────────

create table public.team_announcement_reads (
  announcement_id uuid        not null references public.team_announcements(id) on delete cascade,
  profile_id      uuid        not null references public.profiles(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (announcement_id, profile_id)
);

create index team_announcement_reads_profile_idx
  on public.team_announcement_reads(profile_id, announcement_id);

alter table public.team_announcement_reads enable row level security;
revoke all on public.team_announcement_reads from anon, authenticated;

-- ─── F. current_team_leader_profile_id ───────────────────────────────────
-- Internal-only. The single source of truth for "who currently leads this
-- team" -- every RPC below resolves the leader through this instead of
-- re-deriving the query, so the live-leadership rule (design note 1) can
-- never drift between call sites.

create or replace function public.current_team_leader_profile_id(
  p_team_id uuid
) returns uuid
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_leader_profile_id uuid;
begin
  select tm.profile_id into v_leader_profile_id
  from team_members tm
  where tm.team_id = p_team_id
    and tm.role = 'leader'
    and tm.is_active = true
    and tm.removed_at is null
  limit 1;

  return v_leader_profile_id;
end;
$$;

revoke execute on function public.current_team_leader_profile_id(uuid) from public;
revoke execute on function public.current_team_leader_profile_id(uuid) from anon;
revoke execute on function public.current_team_leader_profile_id(uuid) from authenticated;

-- ─── G. send_team_leader_message ─────────────────────────────────────────
-- Member -> current leader. No recipient parameter exists: the leader is
-- always resolved server-side, so a member can never choose an arbitrary
-- recipient. If the caller is themselves the current leader, this RPC
-- refuses rather than inventing a member on their behalf -- leaders reply
-- to members via leader_reply_team_message instead.

create or replace function public.send_team_leader_message(
  p_session_token text,
  p_team_id       uuid,
  p_body          text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id        uuid;
  v_leader_profile_id uuid;
  v_body              text;
  v_conv              team_conversations%rowtype;
  v_msg               team_messages%rowtype;
  v_team_name         text;
  v_sender_name       text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(select 1 from teams where id = p_team_id and is_active = true) then
    raise exception 'team not found';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id
      and is_active = true and removed_at is null
  ) then
    raise exception 'ليست لديك عضوية فعالة في هذا الفريق';
  end if;

  v_leader_profile_id := current_team_leader_profile_id(p_team_id);
  if v_leader_profile_id is null then
    raise exception 'لا يوجد قائد حالي لهذا الفريق';
  end if;

  if v_profile_id = v_leader_profile_id then
    raise exception 'قائد الفريق لا يمكنه استخدام هذه الوظيفة؛ استخدم الرد على رسائل الأعضاء';
  end if;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is null then
    raise exception 'لا يمكن إرسال رسالة فارغة';
  end if;
  if length(v_body) > 2000 then
    raise exception 'الرسالة طويلة جدًا (الحد الأقصى 2000 حرف)';
  end if;

  insert into team_conversations (team_id, member_profile_id)
  values (p_team_id, v_profile_id)
  on conflict (team_id, member_profile_id) do update set updated_at = now()
  returning * into v_conv;

  insert into team_messages (conversation_id, sender_profile_id, body)
  values (v_conv.id, v_profile_id, v_body)
  returning * into v_msg;

  update team_conversations
  set updated_at = v_msg.created_at
  where id = v_conv.id;

  select name into v_team_name from teams where id = p_team_id;
  select display_name into v_sender_name from profiles where id = v_profile_id;

  if exists(select 1 from profiles where id = v_leader_profile_id and is_active = true) then
    perform create_notification_internal(
      p_recipient_profile_id => v_leader_profile_id,
      p_type                 => 'team_message',
      p_title                => 'رسالة جديدة من عضو الفريق',
      p_body                 => coalesce(v_sender_name, 'أحد الأعضاء') || ' أرسل رسالة في فريق ' || v_team_name,
      p_team_id              => p_team_id,
      p_action_type          => 'open_team_conversation',
      p_action_payload       => jsonb_build_object('team_id', p_team_id, 'conversation_id', v_conv.id),
      p_dedupe_key           => 'team_message:' || v_msg.id::text
    );
  end if;

  return jsonb_build_object(
    'conversation', jsonb_build_object(
      'id',                v_conv.id,
      'team_id',           p_team_id,
      'member_profile_id', v_profile_id,
      'updated_at',        v_msg.created_at
    ),
    'message', jsonb_build_object(
      'id',                v_msg.id,
      'conversation_id',   v_msg.conversation_id,
      'sender_profile_id', v_msg.sender_profile_id,
      'sender_name',       v_sender_name,
      'sender_role',       'member',
      'body',              v_msg.body,
      'created_at',        v_msg.created_at,
      'is_read',           true
    )
  );
end;
$$;

-- ─── H. leader_reply_team_message ────────────────────────────────────────
-- Current leader -> the conversation's member. The member is resolved from
-- the conversation row, never supplied by the caller.

create or replace function public.leader_reply_team_message(
  p_session_token   text,
  p_conversation_id uuid,
  p_body            text
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id  uuid;
  v_conv        team_conversations%rowtype;
  v_body        text;
  v_msg         team_messages%rowtype;
  v_team_name   text;
  v_leader_name text;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_conv from team_conversations where id = p_conversation_id and archived_at is null;
  if not found then
    raise exception 'conversation not found';
  end if;

  if not exists(select 1 from teams where id = v_conv.team_id and is_active = true) then
    raise exception 'team not found';
  end if;

  if current_team_leader_profile_id(v_conv.team_id) is distinct from v_profile_id then
    raise exception 'القائد الحالي فقط يمكنه الرد على هذه المحادثة';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = v_conv.team_id and profile_id = v_conv.member_profile_id
      and is_active = true and removed_at is null
  ) then
    raise exception 'العضو لم يعد ضمن الفريق؛ لا يمكن إرسال رد جديد';
  end if;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is null then
    raise exception 'لا يمكن إرسال رسالة فارغة';
  end if;
  if length(v_body) > 2000 then
    raise exception 'الرسالة طويلة جدًا (الحد الأقصى 2000 حرف)';
  end if;

  insert into team_messages (conversation_id, sender_profile_id, body)
  values (v_conv.id, v_profile_id, v_body)
  returning * into v_msg;

  update team_conversations
  set updated_at = v_msg.created_at
  where id = v_conv.id;

  select name into v_team_name from teams where id = v_conv.team_id;
  select display_name into v_leader_name from profiles where id = v_profile_id;

  if exists(select 1 from profiles where id = v_conv.member_profile_id and is_active = true) then
    perform create_notification_internal(
      p_recipient_profile_id => v_conv.member_profile_id,
      p_type                 => 'team_message_reply',
      p_title                => 'رد جديد من قائد الفريق',
      p_body                 => coalesce(v_leader_name, 'قائد الفريق') || ' رد عليك في فريق ' || v_team_name,
      p_team_id              => v_conv.team_id,
      p_action_type          => 'open_team_conversation',
      p_action_payload       => jsonb_build_object('team_id', v_conv.team_id, 'conversation_id', v_conv.id),
      p_dedupe_key           => 'team_message:' || v_msg.id::text
    );
  end if;

  return jsonb_build_object(
    'conversation', jsonb_build_object(
      'id',                v_conv.id,
      'team_id',           v_conv.team_id,
      'member_profile_id', v_conv.member_profile_id,
      'updated_at',        v_msg.created_at
    ),
    'message', jsonb_build_object(
      'id',                v_msg.id,
      'conversation_id',   v_msg.conversation_id,
      'sender_profile_id', v_msg.sender_profile_id,
      'sender_name',       v_leader_name,
      'sender_role',       'leader',
      'body',              v_msg.body,
      'created_at',        v_msg.created_at,
      'is_read',           true
    )
  );
end;
$$;

-- ─── I. get_my_team_conversations ────────────────────────────────────────
-- Members see their own conversation(s); leaders see every conversation for
-- every team they currently lead. A profile that is both a member of one
-- team and the leader of another sees both. Compound (updated_at, id)
-- cursor, newest-first.

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
        where m.conversation_id = e.id and m.archived_at is null
          and m.sender_profile_id <> v_profile_id
          and m.created_at > coalesce(
            (select r.last_read_at from team_conversation_reads r
             where r.conversation_id = e.id and r.profile_id = v_profile_id),
            '-infinity'::timestamptz
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

-- ─── J. get_team_conversation_messages ───────────────────────────────────
-- Only the conversation's own member (while currently valid) or the
-- conversation's current leader (always, for audit) may read it.
-- Newest-first, compound (created_at, id) cursor, max 50 per page.

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
  v_profile_id      uuid;
  v_conv            team_conversations%rowtype;
  v_leader_id       uuid;
  v_is_leader       boolean;
  v_is_member       boolean;
  v_last_read_at    timestamptz;
  v_limit           int;
  v_items           jsonb;
  v_has_more        boolean;
  v_last_created_at timestamptz;
  v_last_id         uuid;
  v_next_cursor     jsonb := null;
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

  select last_read_at into v_last_read_at
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
                             or (v_last_read_at is not null and m.created_at <= v_last_read_at)
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

-- ─── K. mark_team_conversation_read ──────────────────────────────────────
-- Marks everything visible as of now as read; a message inserted after this
-- call always has created_at > the stored last_read_at, so it is never
-- marked read in advance.

create or replace function public.mark_team_conversation_read(
  p_session_token   text,
  p_conversation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id   uuid;
  v_conv         team_conversations%rowtype;
  v_leader_id    uuid;
  v_is_leader    boolean;
  v_is_member    boolean;
  v_now          timestamptz := now();
  v_last_read_at timestamptz;
  v_unread_count integer;
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

  insert into team_conversation_reads (conversation_id, profile_id, last_read_at)
  values (p_conversation_id, v_profile_id, v_now)
  on conflict (conversation_id, profile_id) do update
    set last_read_at = greatest(team_conversation_reads.last_read_at, excluded.last_read_at)
  returning last_read_at into v_last_read_at;

  select count(*) into v_unread_count
  from team_messages
  where conversation_id = p_conversation_id
    and archived_at is null
    and sender_profile_id <> v_profile_id
    and created_at > v_last_read_at;

  return jsonb_build_object(
    'conversation_id', p_conversation_id,
    'last_read_at',    v_last_read_at,
    'unread_count',    v_unread_count
  );
end;
$$;

-- ─── L. create_team_announcement ─────────────────────────────────────────
-- Leader-only broadcast to every currently valid team member except the
-- author. The author is auto-marked as having read their own announcement
-- (they wrote it) and never notified about it.

create or replace function public.create_team_announcement(
  p_session_token text,
  p_team_id       uuid,
  p_body          text,
  p_title         text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id  uuid;
  v_title       text;
  v_body        text;
  v_ann         team_announcements%rowtype;
  v_team_name   text;
  v_author_name text;
  v_recipient   record;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  if not exists(select 1 from teams where id = p_team_id and is_active = true) then
    raise exception 'team not found';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = p_team_id and profile_id = v_profile_id
      and role = 'leader' and is_active = true and removed_at is null
  ) then
    raise exception 'القائد فقط يمكنه نشر إعلانات الفريق';
  end if;

  v_title := nullif(trim(coalesce(p_title, '')), '');
  if v_title is not null and length(v_title) > 120 then
    raise exception 'العنوان طويل جدًا (الحد الأقصى 120 حرف)';
  end if;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is null then
    raise exception 'لا يمكن نشر إعلان فارغ';
  end if;
  if length(v_body) > 3000 then
    raise exception 'الإعلان طويل جدًا (الحد الأقصى 3000 حرف)';
  end if;

  insert into team_announcements (team_id, author_profile_id, title, body)
  values (p_team_id, v_profile_id, v_title, v_body)
  returning * into v_ann;

  insert into team_announcement_reads (announcement_id, profile_id, read_at)
  values (v_ann.id, v_profile_id, v_ann.created_at);

  select name into v_team_name from teams where id = p_team_id;
  select display_name into v_author_name from profiles where id = v_profile_id;

  for v_recipient in
    select tm.profile_id
    from team_members tm
    where tm.team_id = p_team_id
      and tm.is_active = true
      and tm.removed_at is null
      and tm.profile_id is not null
      and tm.profile_id <> v_profile_id
  loop
    if exists(select 1 from profiles where id = v_recipient.profile_id and is_active = true) then
      perform create_notification_internal(
        p_recipient_profile_id => v_recipient.profile_id,
        p_type                 => 'team_announcement',
        p_title                => coalesce(v_title, 'إعلان جديد للفريق'),
        p_body                 => coalesce(v_author_name, 'قائد الفريق') || ' نشر إعلانًا في فريق ' || v_team_name,
        p_team_id              => p_team_id,
        p_action_type          => 'open_team_announcements',
        p_action_payload       => jsonb_build_object('team_id', p_team_id, 'announcement_id', v_ann.id),
        p_dedupe_key           => 'team_announcement:' || v_ann.id::text || ':' || v_recipient.profile_id::text
      );
    end if;
  end loop;

  return jsonb_build_object(
    'id',                v_ann.id,
    'team_id',           v_ann.team_id,
    'team_name',         v_team_name,
    'author_profile_id', v_ann.author_profile_id,
    'author_name',       v_author_name,
    'title',             v_ann.title,
    'body',              v_ann.body,
    'created_at',        v_ann.created_at,
    'is_read',           true
  );
end;
$$;

-- ─── M. get_my_team_announcements ────────────────────────────────────────
-- Only announcements from teams where the caller currently has a valid
-- membership (any role). Compound (created_at, id) cursor, newest-first.

create or replace function public.get_my_team_announcements(
  p_session_token      text,
  p_team_id            uuid default null,
  p_limit              integer default 50,
  p_before_created_at  timestamptz default null,
  p_before_id          uuid default null,
  p_unread_only        boolean default false
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
  v_last_created_at timestamptz;
  v_last_id         uuid;
  v_next_cursor     jsonb := null;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  v_limit := greatest(least(coalesce(p_limit, 50), 100), 1);

  select
    coalesce(jsonb_agg(t.item order by t.created_at desc, t.id desc) filter (where t.rn <= v_limit), '[]'::jsonb),
    coalesce(bool_or(t.rn > v_limit), false),
    max(t.created_at) filter (where t.rn = v_limit),
    (array_agg(t.id) filter (where t.rn = v_limit))[1]
  into v_items, v_has_more, v_last_created_at, v_last_id
  from (
    select
      a.id, a.created_at,
      row_number() over (order by a.created_at desc, a.id desc) as rn,
      jsonb_build_object(
        'id',                a.id,
        'team_id',           a.team_id,
        'team_name',         t.name,
        'author_profile_id', a.author_profile_id,
        'author_name',       p.display_name,
        'title',             a.title,
        'body',              a.body,
        'created_at',        a.created_at,
        'is_read',           exists(
          select 1 from team_announcement_reads r
          where r.announcement_id = a.id and r.profile_id = v_profile_id
        )
      ) as item
    from team_announcements a
    join teams t on t.id = a.team_id and t.is_active = true
    join profiles p on p.id = a.author_profile_id
    where a.archived_at is null
      and exists(
        select 1 from team_members tm
        where tm.team_id = a.team_id and tm.profile_id = v_profile_id
          and tm.is_active = true and tm.removed_at is null
      )
      and (p_team_id is null or a.team_id = p_team_id)
      and (
        not p_unread_only
        or not exists(
          select 1 from team_announcement_reads r
          where r.announcement_id = a.id and r.profile_id = v_profile_id
        )
      )
      and (
        p_before_created_at is null
        or (p_before_id is null and a.created_at < p_before_created_at)
        or (p_before_id is not null and (a.created_at, a.id) < (p_before_created_at, p_before_id))
      )
    order by a.created_at desc, a.id desc
    limit v_limit + 1
  ) t;

  if v_has_more and v_last_created_at is not null then
    v_next_cursor := jsonb_build_object('created_at', v_last_created_at, 'id', v_last_id);
  end if;

  return jsonb_build_object(
    'items',       v_items,
    'has_more',    v_has_more,
    'next_cursor', v_next_cursor
  );
end;
$$;

-- ─── N. mark_team_announcement_read ──────────────────────────────────────
-- Idempotent: re-marking an already-read announcement keeps the original
-- read_at (on conflict do nothing).

create or replace function public.mark_team_announcement_read(
  p_session_token   text,
  p_announcement_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_profile_id uuid;
  v_ann        team_announcements%rowtype;
  v_read_at    timestamptz;
begin
  v_profile_id := current_profile_id_from_session(p_session_token);

  select * into v_ann from team_announcements where id = p_announcement_id and archived_at is null;
  if not found then
    raise exception 'announcement not found';
  end if;

  if not exists(select 1 from teams where id = v_ann.team_id and is_active = true) then
    raise exception 'announcement not found';
  end if;

  if not exists(
    select 1 from team_members
    where team_id = v_ann.team_id and profile_id = v_profile_id
      and is_active = true and removed_at is null
  ) then
    raise exception 'غير مصرح لك بتحديث حالة قراءة هذا الإعلان';
  end if;

  insert into team_announcement_reads (announcement_id, profile_id, read_at)
  values (p_announcement_id, v_profile_id, now())
  on conflict (announcement_id, profile_id) do nothing;

  select read_at into v_read_at
  from team_announcement_reads
  where announcement_id = p_announcement_id and profile_id = v_profile_id;

  return jsonb_build_object(
    'announcement_id', p_announcement_id,
    'is_read',         true,
    'read_at',         v_read_at
  );
end;
$$;

-- ─── O. get_my_messaging_unread_count ────────────────────────────────────

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
        where m.conversation_id = tc.id and m.archived_at is null
          and m.sender_profile_id <> v_profile_id
          and m.created_at > coalesce(
            (select r.last_read_at from team_conversation_reads r
             where r.conversation_id = tc.id and r.profile_id = v_profile_id),
            '-infinity'::timestamptz
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

-- ─── P. Grants ─────────────────────────────────────────────────────────────
-- Client-facing messaging RPCs are granted to anon (RPC-only access, same
-- convention as every other client entry point). current_team_leader_profile_id
-- stays internal-only (section F above).

grant execute on function public.send_team_leader_message(text, uuid, text) to anon;
grant execute on function public.leader_reply_team_message(text, uuid, text) to anon;
grant execute on function public.get_my_team_conversations(text, integer, timestamptz, uuid, boolean) to anon;
grant execute on function public.get_team_conversation_messages(text, uuid, integer, timestamptz, uuid) to anon;
grant execute on function public.mark_team_conversation_read(text, uuid) to anon;
grant execute on function public.create_team_announcement(text, uuid, text, text) to anon;
grant execute on function public.get_my_team_announcements(text, uuid, integer, timestamptz, uuid, boolean) to anon;
grant execute on function public.mark_team_announcement_read(text, uuid) to anon;
grant execute on function public.get_my_messaging_unread_count(text) to anon;
