\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
insert into auth.users(id) values ('c0000000-0000-4000-8000-000000000001'),('c0000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000001',true);
create temp table register_input as select jsonb_build_object(
 'id','c1000000-0000-4000-8000-000000000001','user_id',auth.uid(),'batch_id','c2000000-0000-4000-8000-000000000001',
 'team_id',null,'path',auth.uid()||'/c2000000-0000-4000-8000-000000000001/c1000000-0000-4000-8000-000000000001.jpg',
 'source','camera','captured_at',now(),'local_date',(now() at time zone 'Asia/Shanghai')::date,'phash','registration-test-1',
 'metadata',jsonb_build_object('original_sha256',repeat('a',64),'analysis_sha256',repeat('b',64),'image_mode','direct')) media,
 jsonb_build_object('data_url','data:image/jpeg;base64,/9j/2Q==','result',null,'screenshot_date',null,'recognition_status','pending') analysis;
select pg_temp.assert_true(not has_function_privilege('anon','public.register_direct_media(jsonb,jsonb)','execute') and not has_function_privilege('authenticated','public.register_direct_media(jsonb,jsonb)','execute'),'registration is not callable by clients');
select pg_temp.assert_true(has_function_privilege('service_role','public.register_direct_media(jsonb,jsonb)','execute'),'service can atomically register');
do $$ begin
 perform public.register_direct_media(media,analysis||'{"recognition_status":"ready","result":{}}') from register_input;
 raise exception 'Malformed cache committed';
 exception when check_violation then null;
end $$;
select pg_temp.assert_true(not exists(select 1 from public.media where id='c1000000-0000-4000-8000-000000000001'),'cache failure rolls back original registration');
grant select on register_input to service_role;
set local role service_role;
select public.register_direct_media(media,analysis) from register_input;
reset role;
select pg_temp.assert_true((select count(*)=1 from public.media m join public.media_analysis a on a.media_id=m.id where m.id='c1000000-0000-4000-8000-000000000001'),'both records committed');
create temp table initial_cache as select * from public.media_analysis where media_id='c1000000-0000-4000-8000-000000000001';
update public.media_analysis set result='{"assignments":[],"groups":[]}',recognition_status='ready' where media_id='c1000000-0000-4000-8000-000000000001';
select public.register_direct_media(media,analysis) from register_input;
select pg_temp.assert_true((select a.recognition_status='ready' and a.result is not null and a.created_at=i.created_at and a.expires_at=i.expires_at from public.media_analysis a join initial_cache i using(media_id)),'replay preserves verified result and original expiry');
do $$ begin
 perform public.register_direct_media(jsonb_set(media,'{metadata,analysis_sha256}',to_jsonb(repeat('c',64))),analysis) from register_input;
 raise exception 'Changed analysis accepted';
 exception when sqlstate 'PT409' then null;
end $$;
do $$ begin
 perform public.register_direct_media(jsonb_set(media,'{metadata,original_sha256}',to_jsonb(repeat('c',64))),analysis) from register_input;
 raise exception 'Changed original accepted';
 exception when sqlstate 'PT409' then null;
end $$;
do $$ begin
 perform public.register_direct_media(media||jsonb_build_object('user_id','c0000000-0000-4000-8000-000000000002'),analysis) from register_input;
 raise exception 'Cross-owner identity accepted';
 exception when sqlstate 'PT409' then null;
end $$;
do $$ begin
 perform public.register_direct_media(media||jsonb_build_object('local_date',current_date-2),analysis) from register_input;
 raise exception 'Old upload replay accepted';
 exception when sqlstate 'PT410' then null;
end $$;
-- Historical interrupted rows are repaired from the original retention start.
delete from public.media_analysis where media_id='c1000000-0000-4000-8000-000000000001';
update public.media set created_at=now()-interval '2 hours' where id='c1000000-0000-4000-8000-000000000001';
select public.register_direct_media(media,analysis) from register_input;
select pg_temp.assert_true((select a.created_at=m.created_at and a.expires_at=m.created_at+interval '24 hours' from public.media_analysis a join public.media m on m.id=a.media_id where m.id='c1000000-0000-4000-8000-000000000001'),'repair cannot extend original retention');
delete from public.media_analysis where media_id='c1000000-0000-4000-8000-000000000001';
update public.media set created_at=now()-interval '25 hours' where id='c1000000-0000-4000-8000-000000000001';
do $$ begin
 perform public.register_direct_media(media,analysis) from register_input;
 raise exception 'Expired original regained cached pixels';
 exception when sqlstate 'PT410' then null;
end $$;
select pg_temp.assert_true(not exists(select 1 from public.media_analysis where media_id='c1000000-0000-4000-8000-000000000001'),'expired repair creates no cache');
update public.media set deleted_at=now() where id='c1000000-0000-4000-8000-000000000001';
do $$ begin
 perform public.register_direct_media(media,analysis) from register_input;
 raise exception 'Deleted original revived';
 exception when sqlstate 'PT409' then null;
end $$;
rollback;
\echo 'Atomic media registration database tests passed'
