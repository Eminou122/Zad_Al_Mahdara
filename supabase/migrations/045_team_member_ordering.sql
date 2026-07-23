-- Gate 2: atomic persistent ordering using existing team_members.position.
create or replace function public.reorder_team_members(p_session_token text, p_team_id uuid, p_member_ids uuid[]) returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare v_me uuid; v_count int; v_distinct int; v_bad int;
begin
 v_me:=current_profile_id_from_session(p_session_token);
 if not exists(select 1 from team_members where team_id=p_team_id and profile_id=v_me and role='leader' and is_active and removed_at is null) then raise exception 'only team leader can reorder members'; end if;
 select count(*) into v_count from team_members where team_id=p_team_id and is_active and removed_at is null;
 select count(distinct x) into v_distinct from unnest(coalesce(p_member_ids,'{}'::uuid[])) x;
 if cardinality(p_member_ids)<>v_count or v_distinct<>v_count then raise exception 'member order is invalid'; end if;
 select count(*) into v_bad from unnest(p_member_ids) x where not exists(select 1 from team_members where id=x and team_id=p_team_id and is_active and removed_at is null);
 if v_bad<>0 then raise exception 'member order is invalid'; end if;
 update team_members set position=position+100000,updated_at=now() where team_id=p_team_id and is_active and removed_at is null;
 update team_members tm set position=o.pos,updated_at=now() from unnest(p_member_ids) with ordinality o(id,pos) where tm.id=o.id;
 return get_team_detail(p_session_token,p_team_id);
end $$;
revoke all on function public.reorder_team_members(text,uuid,uuid[]) from public;
revoke all on function public.reorder_team_members(text,uuid,uuid[]) from authenticated;
grant execute on function public.reorder_team_members(text,uuid,uuid[]) to anon;

-- Atomic initial ordered membership. Each item is {kind: leader|account|manual, profile_id?, name?, phone?}.
create or replace function public.create_team_with_members(p_session_token text,p_name text,p_team_type text,p_is_public boolean,p_status text,p_note text,p_members jsonb) returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; team_id uuid; item jsonb; pos int:=0; account_id uuid; external_id uuid; seen_accounts uuid[]:='{}'; seen_phones text[]:='{}'; leader_count int:=0; phone text; name text;
begin
 me:=current_profile_id_from_session(p_session_token);
 if jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)=0 then raise exception 'member order is invalid'; end if;
 if length(trim(p_name)) not between 1 and 80 or p_team_type not in ('lunch','breakfast','dinner','tea','other') or p_status not in ('open','closed','full') then raise exception 'team invalid'; end if;
 for item in select value from jsonb_array_elements(p_members) loop
  pos:=pos+1;
  if item->>'kind'='leader' then account_id:=me; leader_count:=leader_count+1;
  elsif item->>'kind'='account' then account_id:=(item->>'profile_id')::uuid; if not exists(select 1 from profiles where id=account_id and is_active) then raise exception 'student not found'; end if;
  elsif item->>'kind'='manual' then account_id:=null; name:=trim(item->>'name'); phone:=item->>'phone'; if length(name) not between 1 and 80 or phone !~ '^[0-9]{8}$' or phone=any(seen_phones) or exists(select 1 from profiles where phone_number=phone) then raise exception 'manual member invalid'; end if; seen_phones:=array_append(seen_phones,phone);
  else raise exception 'member order is invalid'; end if;
  if account_id is not null then if account_id=any(seen_accounts) then raise exception 'duplicate member'; end if; seen_accounts:=array_append(seen_accounts,account_id); end if;
 end loop;
 if leader_count<>1 then raise exception 'member order is invalid'; end if;
 insert into teams(name,team_type,leader_id,is_public,status,note) values(trim(p_name),p_team_type,me,coalesce(p_is_public,true),p_status,p_note) returning id into team_id;
 pos:=0;
 for item in select value from jsonb_array_elements(p_members) loop pos:=pos+1; account_id:=case when item->>'kind'='leader' then me when item->>'kind'='account' then (item->>'profile_id')::uuid else null end;
  if item->>'kind'='manual' then name:=trim(item->>'name'); phone:=item->>'phone'; insert into external_students(display_name,phone_number,phone_masked,created_by) values(name,phone,left(phone,2)||'****'||right(phone,2),me) returning id into external_id; insert into team_members(team_id,external_student_id,position,role,is_active) values(team_id,external_id,pos,'member',true);
  else insert into team_members(team_id,profile_id,position,role,is_active) values(team_id,account_id,pos,case when account_id=me then 'leader' else 'member' end,true); end if;
 end loop;
 return get_team_detail(p_session_token,team_id);
end $$;
revoke all on function public.create_team_with_members(text,text,text,boolean,text,text,jsonb) from public;
revoke all on function public.create_team_with_members(text,text,text,boolean,text,text,jsonb) from authenticated;
grant execute on function public.create_team_with_members(text,text,text,boolean,text,text,jsonb) to anon;
