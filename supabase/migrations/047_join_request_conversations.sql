-- Gate 4A: applicants may use a private, leader-bound conversation before
-- becoming team members. Existing member conversations remain unchanged.
alter table public.team_conversations
  add column if not exists origin text not null default 'member'
    check (origin in ('member','join_request')),
  add column if not exists join_leader_profile_id uuid null references public.profiles(id) on delete restrict;

create index if not exists team_conversations_join_leader_idx
  on public.team_conversations(join_leader_profile_id, updated_at desc)
  where origin='join_request' and archived_at is null;

create or replace function public.can_access_team_conversation(p_conversation_id uuid, p_profile_id uuid)
returns boolean language sql security definer set search_path='public','extensions' as $$
  select exists(
    select 1 from public.team_conversations c
    where c.id=p_conversation_id and c.archived_at is null and (
      (c.origin='join_request' and (c.member_profile_id=p_profile_id or c.join_leader_profile_id=p_profile_id))
      or (c.origin='member' and (
        (c.member_profile_id=p_profile_id and exists(select 1 from public.team_members m where m.team_id=c.team_id and m.profile_id=p_profile_id and m.is_active and m.removed_at is null))
        or public.current_team_leader_profile_id(c.team_id)=p_profile_id
      ))
    )
  )
$$;

create or replace function public.contact_available_team_leader(p_session_token text,p_team_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; leader uuid; body text:=nullif(trim(coalesce(p_body,'')), ''); c public.team_conversations%rowtype; m public.team_messages%rowtype; team_name text; sender_name text;
begin
 me:=public.current_profile_id_from_session(p_session_token);
 if body is null or length(body)>500 then raise exception 'invalid contact message'; end if;
 select public.current_team_leader_profile_id(p_team_id) into leader;
 if leader is null or not exists(select 1 from public.profiles p where p.id=leader and p.is_active) or not exists(select 1 from public.teams t where t.id=p_team_id and t.is_active and t.is_public and t.status='open') then raise exception 'team unavailable for contact'; end if;
 if exists(select 1 from public.team_members tm where tm.team_id=p_team_id and tm.profile_id=me and tm.is_active and tm.removed_at is null) then raise exception 'team unavailable for contact'; end if;
 insert into public.team_conversations(team_id,member_profile_id,origin,join_leader_profile_id)
 values(p_team_id,me,'join_request',leader)
 on conflict(team_id,member_profile_id) do update set updated_at=now()
 returning * into c;
 if c.origin <> 'join_request' or c.join_leader_profile_id is distinct from leader then raise exception 'team unavailable for contact'; end if;
 insert into public.team_messages(conversation_id,sender_profile_id,body) values(c.id,me,body) returning * into m;
 update public.team_conversations set updated_at=m.created_at where id=c.id;
 select name into team_name from public.teams where id=p_team_id; select display_name into sender_name from public.profiles where id=me;
 perform public.create_notification_internal(p_recipient_profile_id=>leader,p_type=>'available_team_contact',p_title=>'طلب انضمام إلى الفريق',p_body=>coalesce(sender_name,'متقدم')||' طلب الانضمام إلى فريق '||team_name,p_team_id=>p_team_id,p_action_type=>'open_team_conversation',p_action_payload=>jsonb_build_object('team_id',p_team_id,'conversation_id',c.id),p_dedupe_key=>'join-request:'||m.id::text);
 return jsonb_build_object('ok',true,'conversation_id',c.id,'team_id',p_team_id);
end $$;

create or replace function public.get_my_team_conversations(p_session_token text,p_limit integer default 50,p_before_updated_at timestamptz default null,p_before_id uuid default null,p_unread_only boolean default false)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; items jsonb;
begin me:=public.current_profile_id_from_session(p_session_token);
 select coalesce(jsonb_agg(x order by (x->>'updated_at')::timestamptz desc),'[]'::jsonb) into items from (
  select jsonb_build_object('id',c.id,'team_id',c.team_id,'team_name',t.name,'member_profile_id',c.member_profile_id,'member_name',p.display_name,'latest_message_preview',(select left(m.body,140) from public.team_messages m where m.conversation_id=c.id and m.archived_at is null order by m.created_at desc,m.id desc limit 1),'latest_message_at',(select m.created_at from public.team_messages m where m.conversation_id=c.id and m.archived_at is null order by m.created_at desc,m.id desc limit 1),'unread_count',(select count(*) from public.team_messages m left join public.team_conversation_reads r on r.conversation_id=c.id and r.profile_id=me where m.conversation_id=c.id and m.sender_profile_id<>me and (r.profile_id is null or r.last_read_message_id is null or (m.created_at,m.id)>(r.last_read_at,r.last_read_message_id))),'current_user_role',case when c.member_profile_id=me then 'member' else 'leader' end,'origin',c.origin) x
  from public.team_conversations c join public.teams t on t.id=c.team_id join public.profiles p on p.id=c.member_profile_id
  where c.archived_at is null and public.can_access_team_conversation(c.id,me)
  order by c.updated_at desc limit greatest(least(coalesce(p_limit,50),100),1)
 ) q; return jsonb_build_object('items',items,'has_more',false,'next_cursor',null); end $$;

create or replace function public.get_team_conversation_messages(p_session_token text,p_conversation_id uuid,p_limit integer default 50,p_before_created_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; leader uuid; read_at timestamptz; read_id uuid; items jsonb;
begin me:=public.current_profile_id_from_session(p_session_token); if not public.can_access_team_conversation(p_conversation_id,me) then raise exception 'غير مصرح لك بعرض هذه المحادثة'; end if; select coalesce(join_leader_profile_id,public.current_team_leader_profile_id(team_id)) into leader from public.team_conversations where id=p_conversation_id; select last_read_at,last_read_message_id into read_at,read_id from public.team_conversation_reads where conversation_id=p_conversation_id and profile_id=me;
 select coalesce(jsonb_agg(x order by (x->>'created_at')::timestamptz desc),'[]'::jsonb) into items from (select jsonb_build_object('id',m.id,'conversation_id',m.conversation_id,'sender_profile_id',m.sender_profile_id,'sender_name',p.display_name,'sender_role',case when m.sender_profile_id=leader then 'leader' else 'member' end,'body',m.body,'created_at',m.created_at,'is_read',m.sender_profile_id=me or (read_id is not null and (m.created_at,m.id)<=(read_at,read_id))) x from public.team_messages m join public.profiles p on p.id=m.sender_profile_id where m.conversation_id=p_conversation_id and m.archived_at is null order by m.created_at desc,m.id desc limit greatest(least(coalesce(p_limit,50),50),1)) q;
 return jsonb_build_object('conversation_id',p_conversation_id,'items',items,'has_more',false,'next_cursor',null); end $$;

create or replace function public.mark_team_conversation_read(p_session_token text,p_conversation_id uuid)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; t timestamptz; mid uuid;
begin me:=public.current_profile_id_from_session(p_session_token); if not public.can_access_team_conversation(p_conversation_id,me) then raise exception 'غير مصرح لك بتحديث حالة القراءة لهذه المحادثة'; end if; select created_at,id into t,mid from public.team_messages where conversation_id=p_conversation_id and sender_profile_id<>me and archived_at is null order by created_at desc,id desc limit 1; t:=coalesce(t,'-infinity'); insert into public.team_conversation_reads(conversation_id,profile_id,last_read_at,last_read_message_id) values(p_conversation_id,me,t,mid) on conflict(conversation_id,profile_id) do update set last_read_at=excluded.last_read_at,last_read_message_id=excluded.last_read_message_id; return jsonb_build_object('conversation_id',p_conversation_id,'last_read_at',t,'last_read_message_id',mid,'unread_count',0); end $$;

create or replace function public.send_team_leader_message(p_session_token text,p_team_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; body text:=nullif(trim(coalesce(p_body,'')), ''); c public.team_conversations%rowtype; m public.team_messages%rowtype; name text;
begin me:=public.current_profile_id_from_session(p_session_token); if body is null or length(body)>2000 then raise exception 'لا يمكن إرسال رسالة فارغة'; end if; select * into c from public.team_conversations where team_id=p_team_id and member_profile_id=me and origin='join_request' and archived_at is null; if not found then raise exception 'ليست لديك عضوية فعالة في هذا الفريق'; end if; if c.join_leader_profile_id is null then raise exception 'conversation not found'; end if; insert into public.team_messages(conversation_id,sender_profile_id,body) values(c.id,me,body) returning * into m; update public.team_conversations set updated_at=m.created_at where id=c.id; select display_name into name from public.profiles where id=me; perform public.create_notification_internal(p_recipient_profile_id=>c.join_leader_profile_id,p_type=>'team_message',p_title=>'طلب انضمام إلى الفريق',p_body=>coalesce(name,'متقدم')||' أرسل رسالة جديدة',p_team_id=>p_team_id,p_action_type=>'open_team_conversation',p_action_payload=>jsonb_build_object('team_id',p_team_id,'conversation_id',c.id),p_dedupe_key=>'team_message:'||m.id::text); return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'team_id',p_team_id,'member_profile_id',me),'message',jsonb_build_object('id',m.id,'conversation_id',c.id,'sender_profile_id',me,'sender_name',name,'sender_role','member','body',m.body,'created_at',m.created_at,'is_read',true)); end $$;

create or replace function public.leader_reply_team_message(p_session_token text,p_conversation_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; body text:=nullif(trim(coalesce(p_body,'')), ''); c public.team_conversations%rowtype; m public.team_messages%rowtype; name text;
begin me:=public.current_profile_id_from_session(p_session_token); select * into c from public.team_conversations where id=p_conversation_id and origin='join_request' and archived_at is null; if not found or c.join_leader_profile_id<>me then raise exception 'القائد الحالي فقط يمكنه الرد على هذه المحادثة'; end if; if body is null or length(body)>2000 then raise exception 'لا يمكن إرسال رسالة فارغة'; end if; insert into public.team_messages(conversation_id,sender_profile_id,body) values(c.id,me,body) returning * into m; update public.team_conversations set updated_at=m.created_at where id=c.id; select display_name into name from public.profiles where id=me; perform public.create_notification_internal(p_recipient_profile_id=>c.member_profile_id,p_type=>'team_message_reply',p_title=>'رد على طلب الانضمام',p_body=>coalesce(name,'قائد الفريق')||' رد عليك',p_team_id=>c.team_id,p_action_type=>'open_team_conversation',p_action_payload=>jsonb_build_object('team_id',c.team_id,'conversation_id',c.id),p_dedupe_key=>'team_message:'||m.id::text); return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'team_id',c.team_id,'member_profile_id',c.member_profile_id),'message',jsonb_build_object('id',m.id,'conversation_id',c.id,'sender_profile_id',me,'sender_name',name,'sender_role','leader','body',m.body,'created_at',m.created_at,'is_read',true)); end $$;

create or replace function public.send_team_leader_message(p_session_token text,p_team_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid:=public.current_profile_id_from_session(p_session_token); leader uuid; body text:=nullif(trim(coalesce(p_body,'')), ''); c public.team_conversations%rowtype; m public.team_messages%rowtype; name text; team_name text;
begin
  if body is null or length(body)>2000 then raise exception 'لا يمكن إرسال رسالة فارغة'; end if;
  select * into c from public.team_conversations where team_id=p_team_id and member_profile_id=me and origin='join_request' and archived_at is null;
  if found then
    insert into public.team_messages(conversation_id,sender_profile_id,body) values(c.id,me,body) returning * into m; update public.team_conversations set updated_at=m.created_at where id=c.id; select display_name into name from public.profiles where id=me;
    perform public.create_notification_internal(p_recipient_profile_id=>c.join_leader_profile_id,p_type=>'team_message',p_title=>'طلب انضمام إلى الفريق',p_body=>coalesce(name,'متقدم')||' أرسل رسالة جديدة',p_team_id=>p_team_id,p_action_type=>'open_team_conversation',p_action_payload=>jsonb_build_object('team_id',p_team_id,'conversation_id',c.id),p_dedupe_key=>'team_message:'||m.id::text);
    return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'team_id',p_team_id,'member_profile_id',me),'message',jsonb_build_object('id',m.id,'conversation_id',c.id,'sender_profile_id',me,'sender_name',name,'sender_role','member','body',m.body,'created_at',m.created_at,'is_read',true));
  end if;
  if not exists(select 1 from public.teams where id=p_team_id and is_active=true) then raise exception 'team not found'; end if;
  if not exists(select 1 from public.team_members where team_id=p_team_id and profile_id=me and is_active=true and removed_at is null) then raise exception 'ليست لديك عضوية فعالة في هذا الفريق'; end if;
  leader:=public.current_team_leader_profile_id(p_team_id); if leader is null then raise exception 'لا يوجد قائد حالي لهذا الفريق'; end if; if me=leader then raise exception 'قائد الفريق لا يمكنه استخدام هذه الوظيفة؛ استخدم الرد على رسائل الأعضاء'; end if;
  insert into public.team_conversations(team_id,member_profile_id) values(p_team_id,me) on conflict(team_id,member_profile_id) do update set updated_at=now() returning * into c;
  insert into public.team_messages(conversation_id,sender_profile_id,body) values(c.id,me,body) returning * into m; update public.team_conversations set updated_at=m.created_at where id=c.id; select display_name into name from public.profiles where id=me; select name into team_name from public.teams where id=p_team_id;
  if exists(select 1 from public.profiles where id=leader and is_active=true) then perform public.create_notification_internal(p_recipient_profile_id=>leader,p_type=>'team_message',p_title=>'رسالة جديدة من عضو الفريق',p_body=>coalesce(name,'أحد الأعضاء')||' أرسل رسالة في فريق '||team_name,p_team_id=>p_team_id,p_action_type=>'open_team_conversation',p_action_payload=>jsonb_build_object('team_id',p_team_id,'conversation_id',c.id),p_dedupe_key=>'team_message:'||m.id::text); end if;
  return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'team_id',p_team_id,'member_profile_id',me),'message',jsonb_build_object('id',m.id,'conversation_id',c.id,'sender_profile_id',me,'sender_name',name,'sender_role','member','body',m.body,'created_at',m.created_at,'is_read',true));
end $$;

create or replace function public.leader_reply_team_message(p_session_token text,p_conversation_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid:=public.current_profile_id_from_session(p_session_token); body text:=nullif(trim(coalesce(p_body,'')), ''); c public.team_conversations%rowtype; m public.team_messages%rowtype; name text; team_name text;
begin
  select * into c from public.team_conversations where id=p_conversation_id and archived_at is null; if not found then raise exception 'conversation not found'; end if;
  if body is null or length(body)>2000 then raise exception 'لا يمكن إرسال رسالة فارغة'; end if;
  if c.origin='join_request' then
    if c.join_leader_profile_id is distinct from me then raise exception 'القائد المعيّن فقط يمكنه الرد على هذه المحادثة'; end if;
  else
    if not exists(select 1 from public.teams where id=c.team_id and is_active=true) then raise exception 'team not found'; end if;
    if public.current_team_leader_profile_id(c.team_id) is distinct from me then raise exception 'القائد الحالي فقط يمكنه الرد على هذه المحادثة'; end if;
    if not exists(select 1 from public.team_members where team_id=c.team_id and profile_id=c.member_profile_id and is_active=true and removed_at is null) then raise exception 'العضو لم يعد ضمن الفريق؛ لا يمكن إرسال رد جديد'; end if;
  end if;
  insert into public.team_messages(conversation_id,sender_profile_id,body) values(c.id,me,body) returning * into m; update public.team_conversations set updated_at=m.created_at where id=c.id; select display_name into name from public.profiles where id=me; select name into team_name from public.teams where id=c.team_id;
  perform public.create_notification_internal(p_recipient_profile_id=>c.member_profile_id,p_type=>'team_message_reply',p_title=>case when c.origin='join_request' then 'رد على طلب الانضمام' else 'رد جديد من قائد الفريق' end,p_body=>coalesce(name,'قائد الفريق')||' رد عليك في فريق '||team_name,p_team_id=>c.team_id,p_action_type=>'open_team_conversation',p_action_payload=>jsonb_build_object('team_id',c.team_id,'conversation_id',c.id),p_dedupe_key=>'team_message:'||m.id::text);
  return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'team_id',c.team_id,'member_profile_id',c.member_profile_id),'message',jsonb_build_object('id',m.id,'conversation_id',c.id,'sender_profile_id',me,'sender_name',name,'sender_role','leader','body',m.body,'created_at',m.created_at,'is_read',true));
end $$;

revoke all on function public.can_access_team_conversation(uuid,uuid),public.contact_available_team_leader(text,uuid,text),public.get_my_team_conversations(text,integer,timestamptz,uuid,boolean),public.get_team_conversation_messages(text,uuid,integer,timestamptz,uuid),public.mark_team_conversation_read(text,uuid),public.send_team_leader_message(text,uuid,text),public.leader_reply_team_message(text,uuid,text) from public,authenticated;
grant execute on function public.contact_available_team_leader(text,uuid,text),public.get_my_team_conversations(text,integer,timestamptz,uuid,boolean),public.get_team_conversation_messages(text,uuid,integer,timestamptz,uuid),public.mark_team_conversation_read(text,uuid),public.send_team_leader_message(text,uuid,text),public.leader_reply_team_message(text,uuid,text) to anon;
