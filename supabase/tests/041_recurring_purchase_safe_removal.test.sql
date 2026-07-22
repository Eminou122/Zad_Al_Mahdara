begin;
create extension if not exists pgtap with schema extensions;
set local search_path = 'public', 'extensions';
select plan(90);

insert into profiles(display_name,phone_number,phone_masked,pin_hash,is_admin,is_active) values
 ('041 owner','00000411','00****11',crypt('2468',gen_salt('bf',8)),false,true),
 ('041 other','00000412','00****12',crypt('2468',gen_salt('bf',8)),false,true);
insert into app_sessions(profile_id,token_hash,expires_at) select id,encode(digest('041-owner','sha256'),'hex'),now()+interval '1 day' from profiles where display_name='041 owner';
insert into app_sessions(profile_id,token_hash,expires_at) select id,encode(digest('041-other','sha256'),'hex'),now()+interval '1 day' from profiles where display_name='041 other';
insert into budget_plans(profile_id,total_money,start_date,end_date,is_active) select id,1000,current_date-3,current_date+3,true from profiles where display_name='041 owner';
insert into recurring_purchases(profile_id,name,price,frequency,start_date,end_date) select id,'041 primary',25,'daily',current_date-3,current_date+3 from profiles where display_name='041 owner';
insert into recurring_purchases(profile_id,name,price,frequency,start_date,end_date,is_active) select id,'041 legacy',10,'daily',current_date-3,current_date+3,false from profiles where display_name='041 owner';

-- Schema, grants, and production body proof.
select has_column('public','recurring_purchase_occurrences','voided_at','occurrence voided_at exists');
select has_column('public','recurring_purchase_occurrences','voided_by','occurrence voided_by exists');
select has_column('public','recurring_purchase_occurrences','void_reason','occurrence void_reason exists');
select has_column('public','recurring_purchases','removed_at','definition removed_at exists');
select has_column('public','recurring_purchases','removed_by','definition removed_by exists');
select has_column('public','recurring_purchases','removal_reason','definition removal_reason exists');
select ok((select relrowsecurity from pg_class where oid='public.recurring_purchase_occurrences'::regclass),'occurrence RLS enabled');
select ok(not has_table_privilege('anon','public.recurring_purchase_occurrences','SELECT'),'direct occurrence read revoked');
select ok(has_function_privilege('anon','public.remove_recurring_purchase_occurrence(text,uuid,date,text)','EXECUTE'),'anon removal RPC granted');
select ok(not has_function_privilege('authenticated','public.remove_recurring_purchase_occurrence(text,uuid,date,text)','EXECUTE'),'authenticated removal RPC revoked');
select ok((select prosecdef from pg_proc where oid='public.mark_recurring_purchase_occurrence(text,uuid,date,text,text)'::regprocedure),'mark is definer');
select ok((select 'search_path=public, extensions'=any(proconfig) from pg_proc where oid='public.remove_recurring_purchase_occurrence(text,uuid,date,text)'::regprocedure),'removal search path fixed');
select ok(position('auth.uid' in (select pg_get_functiondef('public.mark_recurring_purchase_occurrence(text,uuid,date,text,text)'::regprocedure)))=0,'no auth uid');
select ok(position('delete from public.expenses' in lower((select pg_get_functiondef('public.mark_recurring_purchase_occurrence(text,uuid,date,text,text)'::regprocedure))))=0,'mark never deletes expense');
select ok(position('delete from public.recurring_purchase_occurrences' in lower((select pg_get_functiondef('public.remove_recurring_purchase_occurrence(text,uuid,date,text)'::regprocedure))))=0,'removal never deletes occurrence');
select ok(position('pg_advisory_xact_lock' in (select pg_get_functiondef('public.mark_recurring_purchase_occurrence(text,uuid,date,text,text)'::regprocedure)))>0,'mark advisory lock');
select ok(position('for update' in lower((select pg_get_functiondef('public.remove_recurring_purchase_occurrence(text,uuid,date,text)'::regprocedure))))>0,'removal row locks');

-- Mark/skip retains one linked expense.
select is(jsonb_array_length(public.mark_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'purchased',null)->'items'),1,'new purchase returned');
select is((select count(*) from expenses where item_name='041 primary'),1::bigint,'new purchase creates one expense');
select is(jsonb_array_length(public.mark_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'purchased',null)->'items'),1,'repeat purchase returned');
select is((select count(*) from expenses where item_name='041 primary'),1::bigint,'repeat purchase no duplicate');
select is(jsonb_array_length(public.mark_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'skipped',null)->'items'),1,'skip returned');
select is((select count(*) from expenses where item_name='041 primary'),1::bigint,'skip retains expense');
select ok((select voided_at is not null from expenses where item_name='041 primary'),'skip voids expense');
select ok((select status='skipped' and expense_id is not null from recurring_purchase_occurrences where occurrence_date=current_date),'skip retains occurrence link');
select is((public.get_budget_overview('041-owner')->'summary'->>'total_spent')::numeric,0::numeric,'voided expense excluded from budget');
select is((select count(*) from recurring_purchase_audit_events where event_type='purchased_skipped'),1::bigint,'skip audits once');
select is(jsonb_array_length(public.mark_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'purchased',null)->'items'),1,'unskip returned');
select is((select count(*) from expenses where item_name='041 primary' and voided_at is null),1::bigint,'unskip has one active expense');
select is((select count(*) from recurring_purchase_audit_events where event_type='skipped_purchased'),1::bigint,'unskip audits once');

-- Explicit occurrence removal is retained, atomic, and idempotent.
select is((public.remove_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'mistake')->>'removed'),'true','owner removes purchased occurrence');
select is((select count(*) from recurring_purchase_occurrences where occurrence_date=current_date),1::bigint,'removed occurrence retained');
select is((select count(*) from expenses where item_name='041 primary'),1::bigint,'removed expense retained');
select ok((select voided_at is not null and voided_by=(select id from profiles where display_name='041 owner') and void_reason='mistake' from recurring_purchase_occurrences where occurrence_date=current_date),'occurrence audit complete');
select ok((select voided_at is not null and voided_by=(select id from profiles where display_name='041 owner') and void_reason='mistake' from expenses where item_name='041 primary'),'expense audit complete');
select ok((select o.expense_id=e.id from recurring_purchase_occurrences o join expenses e on e.id=o.expense_id where o.occurrence_date=current_date),'expense link preserved');
select is((public.remove_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'changed')->>'removed'),'false','repeat removal idempotent');
select is((select void_reason from recurring_purchase_occurrences where occurrence_date=current_date),'mistake','repeat preserves reason');
select is((select count(*) from recurring_purchase_audit_events where event_type='occurrence_removed'),1::bigint,'occurrence removal audits once');
select is((public.get_recurring_purchase_overview('041-owner')->>'today_purchased_total')::numeric,0::numeric,'voided occurrence not purchased');
select is((public.get_recurring_purchase_overview('041-owner')->>'skipped_count')::int,0,'voided occurrence not skipped');
select ok((public.get_today_recurring_purchases('041-owner')->'items'->0->>'is_voided')::boolean,'today exposes voided state');
select ok((public.get_recurring_purchase_history('041-owner',null,50,0)->'items'->0->>'is_voided')::boolean,'history exposes voided state');
select throws_like($$select public.mark_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,'purchased',null)$$,'%removed history cannot be restored%','voided occurrence cannot resurrect');
select throws_like($$select public.remove_recurring_purchase_occurrence('041-other',(select id from recurring_purchases where name='041 primary'),current_date,'x')$$,'recurring purchase not found','cross-user removal rejected');
select throws_like($$select public.remove_recurring_purchase_occurrence('bad',gen_random_uuid(),current_date,'x')$$,'invalid session','invalid session rejected');
select throws_like($$select public.remove_recurring_purchase_occurrence('041-owner',(select id from recurring_purchases where name='041 primary'),current_date,' ')$$,'invalid removal reason','blank reason rejected');

-- Definition removal retains prior finance/history and is idempotent.
select is((public.remove_recurring_purchase('041-owner',(select id from recurring_purchases where name='041 primary'),'finished')->>'removed'),'true','owner removes definition');
select ok((select not is_active and removed_at is not null and removed_by=(select id from profiles where display_name='041 owner') and removal_reason='finished' from recurring_purchases where name='041 primary'),'definition removal metadata complete');
select is(jsonb_array_length(public.get_recurring_purchases('041-owner')->'items'),0,'active list excludes definition');
select is(jsonb_array_length(public.get_today_recurring_purchases('041-owner')->'items'),0,'today excludes removed definition');
select is((select count(*) from recurring_purchase_occurrences),1::bigint,'definition removal retains occurrence');
select is((select count(*) from expenses where item_name='041 primary'),1::bigint,'definition removal retains expense');
select is((public.remove_recurring_purchase('041-owner',(select id from recurring_purchases where name='041 primary'),'changed')->>'removed'),'false','definition repeat idempotent');
select is((select removal_reason from recurring_purchases where name='041 primary'),'finished','definition repeat preserves reason');
select is((select count(*) from recurring_purchase_audit_events where event_type='definition_removed'),1::bigint,'definition removal audits once');
select throws_like($$select public.remove_recurring_purchase('041-other',(select id from recurring_purchases where name='041 primary'),'x')$$,'recurring purchase not found','cross-user definition rejected');
select throws_like($$select public.remove_recurring_purchase('041-owner',(select id from recurring_purchases where name='041 legacy'),' ')$$,'invalid removal reason','definition blank reason rejected');
-- Additional contract precision: catalog constraints, signatures, and grants.
select ok((select data_type='timestamp with time zone' from information_schema.columns where table_schema='public' and table_name='recurring_purchase_occurrences' and column_name='voided_at'),'occurrence voided_at is timestamptz');
select ok((select exists(select 1 from pg_constraint where conrelid='public.recurring_purchase_occurrences'::regclass and conname='recurring_purchase_occurrences_voided_by_fkey' and confrelid='public.profiles'::regclass)),'occurrence voided_by references profiles');
select ok((select data_type='timestamp with time zone' from information_schema.columns where table_schema='public' and table_name='recurring_purchases' and column_name='removed_at'),'definition removed_at is timestamptz');
select ok((select exists(select 1 from pg_constraint where conrelid='public.recurring_purchases'::regclass and conname='recurring_purchases_removed_by_fkey' and confrelid='public.profiles'::regclass)),'definition removed_by references profiles');
select ok((select exists(select 1 from pg_constraint where conrelid='public.recurring_purchase_occurrences'::regclass and conname='recurring_occurrences_void_audit_check')),'occurrence complete-or-null constraint exists');
select ok((select exists(select 1 from pg_constraint where conrelid='public.recurring_purchases'::regclass and conname='recurring_purchases_removal_audit_check')),'definition complete-or-null constraint exists');
select ok((select exists(select 1 from pg_index where indrelid='public.recurring_purchase_occurrences'::regclass and indisunique)),'occurrence uniqueness remains indexed');
select ok((select not is_active and removed_at is null and removed_by is null and removal_reason is null from recurring_purchases where name='041 legacy'),'legacy inactive definition remains valid');
select throws_like($$insert into public.recurring_purchases(profile_id,name,price,frequency,start_date,end_date,is_active,removed_at,removed_by,removal_reason) select id,'041 invalid removed',1,'daily',current_date,current_date,true,now(),id,'x' from profiles where display_name='041 owner'$$,'%recurring_purchases_removal_audit_check%','active removed definition rejected');
select throws_like($$insert into public.recurring_purchase_occurrences(recurring_purchase_id,profile_id,occurrence_date,status,expected_name,expected_price,voided_at) select id,profile_id,current_date-2,'skipped','bad',1,now() from recurring_purchases where name='041 legacy'$$,'%recurring_occurrences_void_audit_check%','partial occurrence void metadata rejected');
select ok(to_regprocedure('public.remove_recurring_purchase_occurrence(text,uuid,date,text)') is not null,'occurrence removal exact signature exists');
select ok(to_regprocedure('public.remove_recurring_purchase(text,uuid,text)') is not null,'definition removal exact signature exists');
select ok(to_regprocedure('public.get_recurring_purchase_history(text,uuid,integer,integer)') is not null,'history exact signature exists');
select ok(to_regprocedure('public.mark_recurring_purchase_occurrence(text,uuid,date,text,text)') is not null,'mark exact signature exists');
select ok(to_regprocedure('public.get_today_recurring_purchases(text)') is not null,'today exact signature exists');
select ok(to_regprocedure('public.get_recurring_purchase_overview(text)') is not null,'statistics exact signature exists');
select ok((select prosecdef from pg_proc where oid='public.remove_recurring_purchase_occurrence(text,uuid,date,text)'::regprocedure),'occurrence mutation is definer');
select ok((select prosecdef from pg_proc where oid='public.remove_recurring_purchase(text,uuid,text)'::regprocedure),'definition mutation is definer');
select ok((select 'search_path=public, extensions'=any(proconfig) from pg_proc where oid='public.remove_recurring_purchase(text,uuid,text)'::regprocedure),'definition mutation search path fixed');
select ok(not has_function_privilege('public','public.remove_recurring_purchase_occurrence(text,uuid,date,text)','EXECUTE'),'PUBLIC occurrence removal revoked');
select ok(not has_function_privilege('public','public.remove_recurring_purchase(text,uuid,text)','EXECUTE'),'PUBLIC definition removal revoked');
select ok(not has_function_privilege('authenticated','public.remove_recurring_purchase(text,uuid,text)','EXECUTE'),'authenticated definition removal revoked');
select ok(has_function_privilege('anon','public.remove_recurring_purchase(text,uuid,text)','EXECUTE'),'anon definition removal granted');
select ok(not has_table_privilege('anon','public.recurring_purchases','INSERT'),'direct recurring insert revoked');
select ok(not has_table_privilege('anon','public.recurring_purchases','UPDATE'),'direct recurring update revoked');
select ok(not has_table_privilege('anon','public.recurring_purchases','DELETE'),'direct recurring delete revoked');
select ok(not has_table_privilege('anon','public.expenses','UPDATE'),'direct expense update revoked');
select ok(not has_table_privilege('anon','public.expenses','DELETE'),'direct expense delete revoked');
select ok(position('voided_at' in lower((select pg_get_functiondef('public.remove_recurring_purchase_occurrence(text,uuid,date,text)'::regprocedure))))>0,'occurrence removal handles voided metadata');
select ok(position('removed_at' in lower((select pg_get_functiondef('public.remove_recurring_purchase(text,uuid,text)'::regprocedure))))>0,'definition removal handles removed metadata');
select ok(position('pg_advisory_xact_lock' in lower((select pg_get_functiondef('public.remove_recurring_purchase_occurrence(text,uuid,date,text)'::regprocedure))))>0,'occurrence removal uses advisory lock');
select ok(position('for update' in lower((select pg_get_functiondef('public.remove_recurring_purchase(text,uuid,text)'::regprocedure))))>0,'definition removal uses row lock');
select * from finish();
rollback;
