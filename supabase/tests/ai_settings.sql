\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
insert into auth.users(id) values ('a0000000-0000-4000-8000-000000000001'),('a0000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.ai_settings'::regclass),'AI settings RLS enabled');
select pg_temp.assert_true(not has_table_privilege('anon','public.ai_settings','select,insert,update,delete'),'anonymous cannot access encrypted store');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.ai_settings','select,insert,update,delete'),'authenticated clients cannot access encrypted store');
select pg_temp.assert_true(has_table_privilege('service_role','public.ai_settings','select,insert,update,delete'),'service role can manage store');
select pg_temp.assert_true(not has_function_privilege('authenticated','app.guard_ai_settings_owner()','execute'),'guard cannot be invoked by clients');
set local role service_role;
insert into public.ai_settings(user_id,enabled,base_url,protocol,model,key_ciphertext,key_iv)
values ('a0000000-0000-4000-8000-000000000001',true,'https://models.example.com/v1','responses','vision-model',repeat('a',24),repeat('i',16)),
('a0000000-0000-4000-8000-000000000002',true,'https://other.example.com/v1','chat_completions','vision-other',repeat('b',24),repeat('j',16));
select pg_temp.assert_true((select count(*)=2 from public.ai_settings),'service role can read encrypted settings');
reset role;
set local role authenticated;
do $$ begin
 perform key_ciphertext from public.ai_settings where user_id=auth.uid();
 raise exception 'Owner could read encrypted key directly';
 exception when insufficient_privilege then null;
end $$;
do $$ begin
 perform key_ciphertext from public.ai_settings where user_id='a0000000-0000-4000-8000-000000000002';
 raise exception 'Another owner could read encrypted key';
 exception when insufficient_privilege then null;
end $$;
do $$ begin
 update public.ai_settings set enabled=false where user_id=auth.uid();
 raise exception 'Owner could bypass API to write settings';
 exception when insufficient_privilege then null;
end $$;
select pg_temp.assert_true(public.bootstrap()::text not like '%key_ciphertext%' and public.bootstrap()::text not like '%models.example.com%','bootstrap does not expose custom settings');
reset role;
set local role anon;
do $$ begin
 perform * from public.ai_settings;
 raise exception 'Anonymous could read encrypted settings';
 exception when insufficient_privilege then null;
end $$;
reset role;
update public.profiles set deletion_requested_at=now() where id='a0000000-0000-4000-8000-000000000001';
set local role service_role;
do $$ begin
 update public.ai_settings set model='must-not-save' where user_id='a0000000-0000-4000-8000-000000000001';
 raise exception 'Deleting account accepted settings write';
 exception when raise_exception then if sqlerrm<>'账号正在删除，无法保存 AI 配置' then raise; end if;
end $$;
reset role;
delete from auth.users where id='a0000000-0000-4000-8000-000000000001';
select pg_temp.assert_true((select count(*)=0 from public.ai_settings where user_id='a0000000-0000-4000-8000-000000000001'),'account deletion cascades encrypted key');
select pg_temp.assert_true((select count(*)=1 from public.ai_settings where user_id='a0000000-0000-4000-8000-000000000002'),'account deletion preserves other owner settings');
rollback;
\echo 'AI settings database tests passed'
