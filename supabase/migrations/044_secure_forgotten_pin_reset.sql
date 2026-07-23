-- Gate 1 secure forgotten PIN: final redemption is bound to one opaque request ID.
create or replace function public.request_pin_reset(p_phone_number text) returns jsonb language plpgsql security definer set search_path = 'public','extensions' as $$
declare v_profile profiles%rowtype; v_id uuid; v_name text;
begin
 if coalesce(p_phone_number,'') !~ '^[0-9]{8}$' then return jsonb_build_object('ok',true); end if;
 select * into v_profile from profiles where phone_number=p_phone_number and is_active and not is_admin;
 if not found then return jsonb_build_object('ok',true); end if;
 update pin_reset_requests set status='cancelled', cancelled_at=now(), updated_at=now() where profile_id=v_profile.id and status in ('pending','code_issued');
 insert into pin_reset_requests(profile_id,status) values(v_profile.id,'pending') returning id into v_id;
 select array_to_string(array_agg(left(x,1)||'***'),' ') into v_name from unnest(regexp_split_to_array(trim(v_profile.display_name),'\s+')) x;
 return jsonb_build_object('ok',true,'reset_request_id',v_id,'masked_name',coalesce(v_name,'***'),'expires_at',now()+interval '5 minutes');
end $$;
create or replace function public.complete_pin_reset(p_reset_request_id uuid,p_verification_code text,p_new_pin text,p_new_pin_confirmation text) returns jsonb language plpgsql security definer set search_path = 'public','extensions' as $$
declare r pin_reset_requests%rowtype; n int;
begin
 if p_reset_request_id is null or coalesce(p_verification_code,'') !~ '^[0-9]{8}$' or coalesce(p_new_pin,'') !~ '^[0-9]{4}$' or p_new_pin<>p_new_pin_confirmation then return jsonb_build_object('ok',false); end if;
 select * into r from pin_reset_requests where id=p_reset_request_id for update;
 if not found or r.status<>'code_issued' or r.code_expires_at is null or r.code_expires_at<=now() or r.attempt_count>=5 then if found then update pin_reset_requests set status='expired',expired_at=coalesce(expired_at,now()),updated_at=now() where id=r.id and status='code_issued'; end if; return jsonb_build_object('ok',false); end if;
 if r.code_hash is null or crypt(p_verification_code,r.code_hash)<>r.code_hash then n:=r.attempt_count+1; update pin_reset_requests set attempt_count=n,status=case when n>=5 then 'expired' else status end,expired_at=case when n>=5 then now() else expired_at end,updated_at=now() where id=r.id; return jsonb_build_object('ok',false); end if;
 update profiles set pin_hash=crypt(p_new_pin,gen_salt('bf',8)),failed_login_count=0,locked_until=null,updated_at=now() where id=r.profile_id;
 update pin_reset_requests set status='used',used_at=now(),updated_at=now() where id=r.id;
 update pin_reset_requests set status='cancelled',cancelled_at=now(),updated_at=now() where profile_id=r.profile_id and id<>r.id and status in ('pending','code_issued');
 update app_sessions set revoked_at=now() where profile_id=r.profile_id and revoked_at is null;
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.cancel_pin_reset_request(p_reset_request_id uuid) returns jsonb language plpgsql security definer set search_path='public','extensions' as $$ begin update pin_reset_requests set status='cancelled',cancelled_at=now(),updated_at=now() where id=p_reset_request_id and status in ('pending','code_issued'); return jsonb_build_object('ok',true); end $$;
revoke all on function public.complete_pin_reset(text,text,text) from public,anon,authenticated;
grant execute on function public.complete_pin_reset(uuid,text,text,text), public.cancel_pin_reset_request(uuid), public.request_pin_reset(text) to anon;
