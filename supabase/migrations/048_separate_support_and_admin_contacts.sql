-- Gate 4B: move the existing administrator profile without creating a new one.
do $$
declare
  v_old_id uuid;
  v_new_id uuid;
begin
  select id into v_old_id from public.profiles
  where phone_number = '49413435' and is_admin = true for update;
  select id into v_new_id from public.profiles
  where phone_number = '38229821' for update;

  if v_old_id is null then
    -- The production profile may already have been moved; never infer admin
    -- rights from either phone number or create an account here.
    if v_new_id is not null and not exists(
      select 1 from public.profiles where id = v_new_id and is_admin = true
    ) then
      raise exception 'new admin phone is already owned by another account';
    end if;
    return;
  end if;

  if v_new_id is not null and v_new_id <> v_old_id then
    raise exception 'new admin phone is already owned by another account';
  end if;

  update public.profiles
  set phone_number = '38229821', phone_masked = '38****21'
  where id = v_old_id;
end $$;
