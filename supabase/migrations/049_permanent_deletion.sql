-- Gate 5A: permanent, RPC-only deletion for existing records.

create or replace function public.delete_notifications(p_session_token text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; wanted int;
begin
  me:=public.current_profile_id_from_session(p_session_token);
  wanted:=cardinality(p_ids); if wanted is null or wanted=0 then raise exception 'no items selected'; end if;
  if (select count(*) from public.notifications where id=any(p_ids) and recipient_profile_id=me)<>wanted then raise exception 'notification not found'; end if;
  delete from public.notifications where id=any(p_ids) and recipient_profile_id=me;
  return jsonb_build_object('deleted_count',wanted,'unread_count',(select count(*) from public.notifications where recipient_profile_id=me and read_at is null));
end $$;

create or replace function public.delete_team_announcements(p_session_token text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; wanted int;
begin
  me:=public.current_profile_id_from_session(p_session_token); wanted:=cardinality(p_ids); if wanted is null or wanted=0 then raise exception 'no items selected'; end if;
  if (select count(*) from public.team_announcements a where a.id=any(p_ids) and exists(select 1 from public.team_members m where m.team_id=a.team_id and m.profile_id=me and m.role='leader' and m.is_active and m.removed_at is null))<>wanted then raise exception 'announcement not found'; end if;
  delete from public.team_announcements where id=any(p_ids);
  return jsonb_build_object('deleted_count',wanted);
end $$;

create or replace function public.delete_team_messages(p_session_token text, p_conversation_id uuid, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; wanted int;
begin
  me:=public.current_profile_id_from_session(p_session_token); wanted:=cardinality(p_ids); if wanted is null or wanted=0 then raise exception 'no items selected'; end if;
  if not public.can_access_team_conversation(p_conversation_id,me) then raise exception 'conversation not found'; end if;
  if (select count(*) from public.team_messages where id=any(p_ids) and conversation_id=p_conversation_id and sender_profile_id=me)<>wanted then raise exception 'message not found'; end if;
  delete from public.team_messages where id=any(p_ids) and conversation_id=p_conversation_id and sender_profile_id=me;
  return jsonb_build_object('deleted_count',wanted);
end $$;

create or replace function public.delete_team_conversation(p_session_token text, p_conversation_id uuid)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid;
begin
  me:=public.current_profile_id_from_session(p_session_token);
  if not public.can_access_team_conversation(p_conversation_id,me) then raise exception 'conversation not found'; end if;
  delete from public.team_conversations where id=p_conversation_id;
  return jsonb_build_object('deleted',true);
end $$;

create or replace function public.delete_expenses(p_session_token text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; wanted int;
begin
  me:=public.current_profile_id_from_session(p_session_token); wanted:=cardinality(p_ids); if wanted is null or wanted=0 then raise exception 'no items selected'; end if;
  if (select count(*) from public.expenses where id=any(p_ids) and profile_id=me and source='manual')<>wanted then raise exception 'expense not found'; end if;
  delete from public.expenses where id=any(p_ids) and profile_id=me and source='manual';
  return public.get_budget_overview(p_session_token);
end $$;

create or replace function public.delete_recurring_purchase_occurrences(p_session_token text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; wanted int;
begin
  me:=public.current_profile_id_from_session(p_session_token); wanted:=cardinality(p_ids); if wanted is null or wanted=0 then raise exception 'no items selected'; end if;
  if (select count(*) from public.recurring_purchase_occurrences where id=any(p_ids) and profile_id=me)<>wanted then raise exception 'purchase not found'; end if;
  delete from public.expenses e using public.recurring_purchase_occurrences o where o.id=any(p_ids) and o.profile_id=me and e.id=o.expense_id;
  delete from public.recurring_purchase_occurrences where id=any(p_ids) and profile_id=me;
  return public.get_budget_overview(p_session_token);
end $$;

create or replace function public.delete_recurring_purchases(p_session_token text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; wanted int;
begin
  me:=public.current_profile_id_from_session(p_session_token); wanted:=cardinality(p_ids); if wanted is null or wanted=0 then raise exception 'no items selected'; end if;
  if (select count(*) from public.recurring_purchases where id=any(p_ids) and profile_id=me)<>wanted then raise exception 'purchase not found'; end if;
  delete from public.expenses e using public.recurring_purchase_occurrences o where o.recurring_purchase_id=any(p_ids) and o.profile_id=me and e.id=o.expense_id;
  delete from public.recurring_purchases where id=any(p_ids) and profile_id=me;
  return public.get_budget_overview(p_session_token);
end $$;

create or replace function public.delete_team_permanently(p_session_token text, p_team_id uuid)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare me uuid; team_expenses uuid[];
begin
  me:=public.current_profile_id_from_session(p_session_token);
  if not exists(select 1 from public.teams t where t.id=p_team_id and (exists(select 1 from public.profiles p where p.id=me and p.is_admin) or exists(select 1 from public.team_members m where m.team_id=t.id and m.profile_id=me and m.role='leader' and m.is_active and m.removed_at is null))) then raise exception 'team not available'; end if;
  select array_agg(expense_id) into team_expenses from public.team_shopping_reports where team_id=p_team_id and expense_id is not null;
  delete from public.team_shopping_reports where team_id=p_team_id;
  delete from public.team_turns where team_id=p_team_id;
  if team_expenses is not null then delete from public.expenses where id=any(team_expenses); end if;
  delete from public.teams where id=p_team_id;
  return jsonb_build_object('deleted',true);
end $$;

revoke all on function public.delete_notifications(text,uuid[]),public.delete_team_announcements(text,uuid[]),public.delete_team_messages(text,uuid,uuid[]),public.delete_team_conversation(text,uuid),public.delete_expenses(text,uuid[]),public.delete_recurring_purchase_occurrences(text,uuid[]),public.delete_recurring_purchases(text,uuid[]),public.delete_team_permanently(text,uuid) from public,authenticated;
grant execute on function public.delete_notifications(text,uuid[]),public.delete_team_announcements(text,uuid[]),public.delete_team_messages(text,uuid,uuid[]),public.delete_team_conversation(text,uuid),public.delete_expenses(text,uuid[]),public.delete_recurring_purchase_occurrences(text,uuid[]),public.delete_recurring_purchases(text,uuid[]),public.delete_team_permanently(text,uuid) to anon;
