\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
insert into auth.users(id) values ('b0000000-0000-4000-8000-000000000001'),('b0000000-0000-4000-8000-000000000002'),('b0000000-0000-4000-8000-000000000003');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
select public.app_action('create_team','{"name":"直连识别测试","timezone":"Asia/Shanghai"}');
create temp table context as select app.team_for(auth.uid()) team_id,(public.app_action('create_invite')->>'token') token;
select public.app_action('save_plan','{"title":"公开阅读","category":"study","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"23:59","visibility":"team"}');
select public.app_action('save_plan','{"title":"私密运动","category":"exercise","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"23:59","visibility":"private"}');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select public.app_action('join_team',jsonb_build_object('token',token)) from context;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
insert into public.media(id,user_id,team_id,batch_id,path,source,captured_at,local_date,phash,metadata)
select ('b1000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,auth.uid(),team_id,
 ('b2000000-0000-4000-8000-'||lpad((case when i<=3 then 1 when i<=5 then 2 else i end)::text,12,'0'))::uuid,
 auth.uid()||'/direct-'||i||'.jpg','album',now(),(now() at time zone 'Asia/Shanghai')::date,'direct-phash-'||i,jsonb_build_object('original_sha256',lpad(i::text,64,'a'))
from context cross join generate_series(1,9) i;
insert into public.media(id,user_id,batch_id,path,source,captured_at,local_date,phash,metadata)
values ('b1000000-0000-4000-8000-000000000010','b0000000-0000-4000-8000-000000000003',gen_random_uuid(),'other/direct.jpg','album',now(),current_date,'outside-phash',jsonb_build_object('original_sha256',lpad('1',64,'a')));
insert into public.media(id,user_id,team_id,batch_id,path,source,captured_at,local_date,phash,metadata)
select ('b1000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,auth.uid(),team_id,'b2000000-0000-4000-8000-000000000011',
 auth.uid()||'/direct-'||i||'.jpg','album',now(),(now() at time zone 'Asia/Shanghai')::date,'direct-phash-'||i,jsonb_build_object('original_sha256',lpad(i::text,64,'a'))
from context cross join generate_series(11,13) i;
select pg_temp.assert_true((select count(*)=2 from public.media where metadata->>'original_sha256'=lpad('1',64,'a')),'same original allowed outside team scope');
do $$ begin
 insert into public.media(user_id,team_id,batch_id,path,source,captured_at,local_date,phash,metadata)
 select 'b0000000-0000-4000-8000-000000000002',team_id,gen_random_uuid(),'repeat-original.jpg','album',now(),current_date,'different-thumbnail-hash',jsonb_build_object('original_sha256',lpad('1',64,'a')) from context;
 raise exception 'Same original bypassed dedup with different thumbnail';
 exception when unique_violation then null;
end $$;
do $$ begin
 update public.media set metadata=jsonb_build_object('original_sha256','invalid') where id='b1000000-0000-4000-8000-000000000009';
 raise exception 'Invalid original hash accepted';
 exception when check_violation then null;
end $$;

select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.media_analysis'::regclass),'analysis RLS enabled');
select pg_temp.assert_true(not has_table_privilege('anon','public.media_analysis','select,insert,update,delete'),'anonymous cannot access cache');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.media_analysis','select,insert,update,delete'),'owner clients cannot access cache');
select pg_temp.assert_true(has_table_privilege('service_role','public.media_analysis','select,insert,update,delete'),'service can use cache');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.clear_expired_media_analysis()','execute'),'client cannot invoke cache expiry');
select pg_temp.assert_true(not exists(select 1 from pg_publication_tables where schemaname='public' and tablename='media_analysis'),'cache absent from Realtime');
set local role service_role;
insert into public.media_analysis(media_id,user_id,data_url,recognition_status)
select id,user_id,'data:image/jpeg;base64,/9j/2Q==','pending' from public.media;
select pg_temp.assert_true((select count(*)=13 from public.media_analysis),'service stores cache');
do $$ begin
 update public.media_analysis set user_id='b0000000-0000-4000-8000-000000000002' where media_id='b1000000-0000-4000-8000-000000000001';
 raise exception 'Cache owner changed';
 exception when raise_exception then if sqlerrm<>'分析缓存归属和有效期不可更改' then raise; end if;
end $$;
do $$ begin
 insert into public.media_analysis(media_id,user_id) values ('b1000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000002');
 raise exception 'Cross-owner cache accepted';
 exception when raise_exception then if sqlerrm<>'分析缓存与照片归属不符或照片已删除' then raise; end if;
end $$;
do $$ begin
 update public.media_analysis set data_url='data:image/jpeg;base64,'||repeat('A',3*1024*1024) where media_id='b1000000-0000-4000-8000-000000000001';
 raise exception 'Oversized pixel cache accepted';
 exception when check_violation then null;
end $$;
do $$ begin
 update public.media_analysis set result='{}',recognition_status='ready' where media_id='b1000000-0000-4000-8000-000000000001';
 raise exception 'Malformed result accepted';
 exception when check_violation then null;
end $$;
do $$ begin
 update public.media_analysis set expires_at=expires_at+interval '1 hour' where media_id='b1000000-0000-4000-8000-000000000001';
 raise exception 'Cache lifetime extended';
 exception when raise_exception then if sqlerrm<>'分析缓存归属和有效期不可更改' then raise; end if;
end $$;
reset role;
set local role authenticated;
do $$ begin
 perform * from public.media_analysis;
 raise exception 'Client read analysis pixels';
 exception when insufficient_privilege then null;
end $$;
select pg_temp.assert_true(public.bootstrap()::text not like '%data:image/jpeg%' and public.bootstrap()::text not like '%media_analysis%','cache absent from bootstrap');
reset role;

-- ALL immediately stamps, then one majority group reuses the existing CAS RPC.
select public.app_action('submit_checkin','{"media_ids":["b1000000-0000-4000-8000-000000000001","b1000000-0000-4000-8000-000000000002","b1000000-0000-4000-8000-000000000003"],"idempotency_key":"direct-majority-test"}');
create temp table majority as select * from public.checkins where batch_id='b2000000-0000-4000-8000-000000000001';
select pg_temp.assert_true((select status='stamped' and visibility='private' and classification_pending from majority),'ALL stamps before model completion');
create temp table claimed_majority as select * from public.claim_jobs('ai',20) where payload->>'checkin_id'=(select id::text from majority);
create temp table majority_result as select jsonb_build_object('version',1,'job_id',id,'lease_token',lease_token,
 'assignments',(select jsonb_agg(jsonb_build_object('photo_id',m.id,'plan_id',(select id from public.plans where title='公开阅读'),'confidence',0.9)) from public.media m where checkin_id=(select id from majority)),
 'groups',jsonb_build_array(jsonb_build_object('plan_id',(select id from public.plans where title='公开阅读'),'photo_ids',(select jsonb_agg(id) from public.media where checkin_id=(select id from majority)),'summary','阅读记录','fields','[]'::jsonb))) body from claimed_majority;
select pg_temp.assert_true((public.apply_ai_result((select id from majority),(select body from majority_result))->>'applied')::boolean,'single majority group applied');
select pg_temp.assert_true((select count(*)=1 from public.checkins where batch_id='b2000000-0000-4000-8000-000000000001'),'majority batch not split');
select pg_temp.assert_true((select status='stamped' and memo_status='ready' and not classification_pending and visibility='team' from public.checkins where id=(select id from majority)),'majority result preserved stamp');
select pg_temp.assert_true(not (public.apply_ai_result((select id from majority),(select body from majority_result))->>'applied')::boolean,'stale result cannot replay');

-- A tie result with null plan stays private and explicitly awaiting a choice.
select public.app_action('submit_checkin','{"media_ids":["b1000000-0000-4000-8000-000000000004","b1000000-0000-4000-8000-000000000005"],"idempotency_key":"direct-tie-test"}');
create temp table tied as select * from public.checkins where batch_id='b2000000-0000-4000-8000-000000000002';
create temp table claimed_tie as select * from public.claim_jobs('ai',20) where payload->>'checkin_id'=(select id::text from tied);
select public.apply_ai_result((select id from tied),jsonb_build_object('version',1,'job_id',id,'lease_token',lease_token,
 'assignments',(select jsonb_agg(jsonb_build_object('photo_id',m.id,'plan_id',null,'confidence',0.4)) from public.media m where checkin_id=(select id from tied)),
 'groups',jsonb_build_array(jsonb_build_object('plan_id',null,'photo_ids',(select jsonb_agg(id) from public.media where checkin_id=(select id from tied)),'summary','待确认记录','fields','[]'::jsonb)))) from claimed_tie;
select pg_temp.assert_true((select plan_id is null and status='stamped' and visibility='private' and classification_pending and memo_status='ready' from public.checkins where id=(select id from tied)),'tie keeps ALL private and awaiting confirmation');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.media where id in ('b1000000-0000-4000-8000-000000000004','b1000000-0000-4000-8000-000000000005')),'teammate cannot see tied photo batch');
reset role;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);

-- The user's explicit plan cannot be replaced by any model result.
select public.app_action('submit_checkin',jsonb_build_object('media_ids',jsonb_build_array('b1000000-0000-4000-8000-000000000006'),'plan_id',(select id from public.plans where title='私密运动'),'idempotency_key','direct-manual-test'));
create temp table manual as select * from public.checkins where batch_id='b2000000-0000-4000-8000-000000000006';
create temp table claimed_manual as select * from public.claim_jobs('ai',20) where payload->>'checkin_id'=(select id::text from manual);
do $$ declare body jsonb; begin
 select jsonb_build_object('version',1,'job_id',id,'lease_token',lease_token,'assignments',jsonb_build_array(jsonb_build_object('photo_id','b1000000-0000-4000-8000-000000000006','plan_id',(select id from public.plans where title='公开阅读'),'confidence',1)),'groups','[]'::jsonb) into body from claimed_manual;
 perform public.apply_ai_result((select id from manual),body);
 raise exception 'Model changed explicit plan';
 exception when raise_exception then if sqlerrm<>'AI cannot override selected plan' then raise; end if;
end $$;
select pg_temp.assert_true((select plan_id=(select id from public.plans where title='私密运动') and status='stamped' from public.checkins where id=(select id from manual)),'manual plan and stamp unchanged');
select public.apply_ai_result((select id from manual),jsonb_build_object('version',1,'job_id',id,'lease_token',lease_token,
 'assignments',jsonb_build_array(jsonb_build_object('photo_id','b1000000-0000-4000-8000-000000000006','plan_id',(select id from public.plans where title='私密运动'),'confidence',1)),
 'groups',jsonb_build_array(jsonb_build_object('plan_id',(select id from public.plans where title='私密运动'),'photo_ids',jsonb_build_array('b1000000-0000-4000-8000-000000000006'),'summary','运动已记录','fields','[]'::jsonb)))) from claimed_manual;
select pg_temp.assert_true((select memo_status='ready' and status='stamped' and visibility='private' from public.checkins where id=(select id from manual)),'matching manual result applies privately');

-- Partial output is readable, but keeps the original version for the same lease.
select public.app_action('submit_checkin','{"media_ids":["b1000000-0000-4000-8000-000000000009"],"note":"原始私密说明","idempotency_key":"direct-partial-test"}');
create temp table partial_checkin as select * from public.checkins where batch_id='b2000000-0000-4000-8000-000000000009';
create temp table claimed_partial as select * from public.claim_jobs('ai',20) where payload->>'checkin_id'=(select id::text from partial_checkin);
create temp table partial_result as select jsonb_build_object('version',1,'job_id',id,'lease_token',lease_token,'partial',true,'privacy_required',true,
 'assignments',jsonb_build_array(jsonb_build_object('photo_id','b1000000-0000-4000-8000-000000000009','plan_id',null,'confidence',0.3)),
 'groups',jsonb_build_array(jsonb_build_object('plan_id',null,'photo_ids',jsonb_build_array('b1000000-0000-4000-8000-000000000009'),'summary','部分识别结果','fields','[]'::jsonb))) body from claimed_partial;
select pg_temp.assert_true((public.apply_ai_result((select id from partial_checkin),(select body from partial_result))->>'applied')::boolean,'partial result applies');
select pg_temp.assert_true((select version=1 and memo_status='ready' and classification_pending and status='stamped' and visibility='private' from public.checkins where id=(select id from partial_checkin)),'partial output preserves retry version and stamp');
select pg_temp.assert_true((select summary='原始私密说明' from public.batch_field_drafts where checkin_id=(select id from partial_checkin)),'original note retained privately');
select pg_temp.assert_true((public.apply_ai_result((select id from partial_checkin),(select jsonb_set(jsonb_set(body,'{partial}','false'),'{groups,0,summary}','"完整但待确认的结果"') from partial_result))->>'applied')::boolean,'complete result reuses original version and lease');
select pg_temp.assert_true((select version=2 and summary='完整但待确认的结果' and memo_status='ready' and classification_pending and status='stamped' and visibility='private' from public.checkins where id=(select id from partial_checkin)),'complete unresolved result remains private ALL');
select pg_temp.assert_true((select summary='原始私密说明' from public.batch_field_drafts where checkin_id=(select id from partial_checkin)),'later AI output cannot replace original private draft');

-- A private minority keeps the entire automatic majority batch private, even if
-- the worker omitted its privacy flag. Cached source classifications are evidence.
update public.media_analysis ma set recognition_status='ready',result=jsonb_build_object(
 'assignments',jsonb_build_array(jsonb_build_object('photo_id',ma.media_id,'plan_id',(select id from public.plans where title=case when ma.media_id='b1000000-0000-4000-8000-000000000013' then '私密运动' else '公开阅读' end),'confidence',0.95)),
 'groups','[]'::jsonb)
where ma.media_id in ('b1000000-0000-4000-8000-000000000011','b1000000-0000-4000-8000-000000000012','b1000000-0000-4000-8000-000000000013');
select public.app_action('submit_checkin','{"media_ids":["b1000000-0000-4000-8000-000000000011","b1000000-0000-4000-8000-000000000012","b1000000-0000-4000-8000-000000000013"],"idempotency_key":"direct-private-minority"}');
create temp table private_majority as select * from public.checkins where batch_id='b2000000-0000-4000-8000-000000000011';
create temp table claimed_private_majority as select * from public.claim_jobs('ai',20) where payload->>'checkin_id'=(select id::text from private_majority);
select public.apply_ai_result((select id from private_majority),jsonb_build_object('version',1,'job_id',id,'lease_token',lease_token,
 'assignments',(select jsonb_agg(jsonb_build_object('photo_id',m.id,'plan_id',(select id from public.plans where title='公开阅读'),'confidence',0.9)) from public.media m where checkin_id=(select id from private_majority)),
 'groups',jsonb_build_array(jsonb_build_object('plan_id',(select id from public.plans where title='公开阅读'),'photo_ids',(select jsonb_agg(id) from public.media where checkin_id=(select id from private_majority)),'summary','混合图片记录','fields','[]'::jsonb)))) from claimed_private_majority;
select pg_temp.assert_true((select plan_id=(select id from public.plans where title='公开阅读') and visibility='private' and memo_status='ready' and not classification_pending and status='stamped' from public.checkins where id=(select id from private_majority)),'private minority cannot become publicly visible through majority');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.media where batch_id='b2000000-0000-4000-8000-000000000011'),'teammate cannot see mixed private batch');
reset role;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);

-- Soft-deleting an original immediately removes cached analysis and rejects late writes.
select public.app_action('delete_photo','{"photo_id":"b1000000-0000-4000-8000-000000000004"}');
select pg_temp.assert_true(not exists(select 1 from public.media_analysis where media_id='b1000000-0000-4000-8000-000000000004'),'soft delete clears analysis');
do $$ begin
 insert into public.media_analysis(media_id,user_id) values ('b1000000-0000-4000-8000-000000000004',auth.uid());
 raise exception 'Deleted media recreated cache';
 exception when raise_exception then if sqlerrm<>'分析缓存与照片归属不符或照片已删除' then raise; end if;
end $$;
-- Simulate time passing without relaxing production expiry writes.
alter table public.media_analysis disable trigger live_owner_before_media_analysis;
update public.media_analysis set created_at=now()-interval '25 hours',expires_at=now()-interval '1 hour',result='{"assignments":[],"groups":[]}',recognition_status='ready' where media_id='b1000000-0000-4000-8000-000000000007';
alter table public.media_analysis enable trigger live_owner_before_media_analysis;
set local role service_role;
select pg_temp.assert_true(public.clear_expired_media_analysis()=1,'expired pixels cleared');
select pg_temp.assert_true((select data_url is null and result is not null and recognition_status='ready' from public.media_analysis where media_id='b1000000-0000-4000-8000-000000000007'),'expiry keeps verified text');
select pg_temp.assert_true(public.clear_expired_media_analysis()=0,'expiry is idempotent');
reset role;
delete from public.media where id='b1000000-0000-4000-8000-000000000008';
select pg_temp.assert_true(not exists(select 1 from public.media_analysis where media_id='b1000000-0000-4000-8000-000000000008'),'hard delete cascades analysis');
delete from auth.users where id='b0000000-0000-4000-8000-000000000003';
select pg_temp.assert_true(not exists(select 1 from public.media_analysis where media_id='b1000000-0000-4000-8000-000000000010'),'account deletion cascades analysis');
rollback;
\echo 'Direct recognition database tests passed'
