\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,m text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'ASSERT: %',m; end if; end $$;
insert into auth.users(id) values('90000000-0000-4000-8000-000000000001'),('90000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select public.app_action('create_team','{"name":"BYOK 测试","timezone":"Asia/Shanghai"}');
select public.app_action('save_plan','{"title":"学习","category":"study","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"23:50","visibility":"team","status":"active"}');
select public.app_action('save_plan','{"title":"运动","category":"exercise","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"23:50","visibility":"private","status":"active"}');
select pg_temp.ok(jsonb_array_length(public.ai_context()->'plans')=2,'context includes the two due plans');
select pg_temp.ok(not exists(select 1 from jsonb_array_elements(public.ai_context()->'plans') p where jsonb_typeof(p)<>'object' or p->>'id' is null),'candidates are flat plan objects, never nested arrays');
create function pg_temp.result(p uuid,plan uuid,c numeric,s text default 'ready') returns jsonb language sql as $$ select jsonb_build_object('photo_id',p,'status',s,'summary',case when s='ready' then '照片中有书页。' else '' end,'fields','[]'::jsonb,'plan_id',plan,'confidence',c,'screenshot_date',null,'origin','byok') $$;
create function pg_temp.stamp(modes jsonb,manual uuid default null) returns uuid language plpgsql as $$
declare bid uuid:=gen_random_uuid(); mid uuid; value jsonb; ids jsonb:='[]'; result jsonb; begin
 for value in select * from jsonb_array_elements(modes) loop
 mid:=gen_random_uuid();
 insert into public.media(id,user_id,team_id,batch_id,path,source,captured_at,local_date,phash,metadata)
 values(mid,auth.uid(),app.team_for(auth.uid()),bid,mid::text||'.jpg','camera',now(),(now() at time zone app.timezone_for(auth.uid()))::date,mid::text,
 jsonb_build_object('byok',pg_temp.result(mid,(value->>'plan')::uuid,(value->>'confidence')::numeric,coalesce(value->>'status','ready'))||'{"revision":0,"user_edited":false}'::jsonb));
 ids:=ids||jsonb_build_array(mid);
 end loop;
 result:=public.app_action('submit_checkin',jsonb_build_object('media_ids',ids,'plan_id',manual,'idempotency_key',bid::text));
 return (result->'checkin_ids'->>0)::uuid; end $$;
create temp table ctx as select (select id from public.plans where title='学习') study,(select id from public.plans where title='运动') exercise;
create temp table samples as
select 'majority' label,pg_temp.stamp(jsonb_build_array(jsonb_build_object('plan',study,'confidence',.8),jsonb_build_object('plan',study,'confidence',.9),jsonb_build_object('plan',exercise,'confidence',.9))) id from ctx
union all select 'tie',pg_temp.stamp(jsonb_build_array(jsonb_build_object('plan',study,'confidence',.9),jsonb_build_object('plan',exercise,'confidence',.9))) from ctx
union all select 'low',pg_temp.stamp(jsonb_build_array(jsonb_build_object('plan',study,'confidence',.79))) from ctx
union all select 'pending',pg_temp.stamp(jsonb_build_array(jsonb_build_object('plan',study,'confidence',.9),jsonb_build_object('plan',null,'confidence',0,'status','pending'))) from ctx
union all select 'manual',pg_temp.stamp(jsonb_build_array(jsonb_build_object('plan',exercise,'confidence',.9)),study) from ctx;
select pg_temp.ok((select c.plan_id=ctx.study from public.checkins c,samples s,ctx where c.id=s.id and label='majority'),'strict majority and 80 percent');
select pg_temp.ok((select bool_and(c.plan_id is null) from public.checkins c join samples s on c.id=s.id where label in ('tie','low','pending')),'tie low and unfinished stay ALL');
select pg_temp.ok((select c.plan_id=ctx.study and c.plan_selection='manual' from public.checkins c,samples s,ctx where c.id=s.id and label='manual'),'manual selection wins');
select pg_temp.ok((select c.visibility='private' from public.checkins c join samples s on c.id=s.id where label='majority'),'private suggested photo keeps aggregate private');
select pg_temp.ok((select count(*)=0 from public.jobs where kind in ('ai','report')),'no AI jobs queued');
select pg_temp.ok((select count(*)=0 from public.claim_jobs('ai',20)),'no server AI leases');
select pg_temp.ok(to_regclass('public.ai_settings') is null,'ciphertext table removed');
select pg_temp.ok(not has_function_privilege('authenticated','public.register_direct_media_before_byok(jsonb,jsonb)','execute'),'legacy registration inaccessible');
select pg_temp.ok(not has_function_privilege('authenticated','public.app_action_before_byok(text,jsonb)','execute'),'legacy action bypass inaccessible');

create temp table pending as select m.id media_id,m.checkin_id,public.ai_context(jsonb_build_object('media_id',m.id)) context
 from public.media m join samples s on m.checkin_id=s.id where s.label='pending' and m.metadata->'byok'->>'status'='pending';
create temp table save_args as select jsonb_build_object('media_id',media_id,'expected_version',context->'record_version','expected_photo_revision',context->'photo_revision','scope_team_id',context->'scope_team_id','idempotency_key','byok-result-test-1','result',pg_temp.result(media_id,ctx.study,.9)) args from pending,ctx;
select pg_temp.ok((public.save_byok_photo(args)->>'applied')::boolean,'pending result applies') from save_args;
select pg_temp.ok((public.save_byok_photo(args)->>'applied')::boolean,'duplicate result returns original success') from save_args;
select pg_temp.ok((select count(*)=1 from public.submissions where idempotency_key='byok:byok-result-test-1'),'result write once');
select pg_temp.ok((public.save_byok_photo(args||'{"idempotency_key":"new-stale-result"}'::jsonb)->>'reason')='version_changed','stale result rejected') from save_args;
select public.app_action('edit_memo',jsonb_build_object('checkin_id',checkin_id,'summary','我确认的摘要','fields','[]'::jsonb)) from pending;
select pg_temp.ok((public.save_byok_photo(args||'{"idempotency_key":"late-after-edit"}'::jsonb)->>'applied')::boolean=false,'edit beats late model') from save_args;
select pg_temp.ok((select c.summary='我确认的摘要' from public.checkins c join pending p on c.id=p.checkin_id),'edited summary retained');
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
do $$ begin perform public.save_byok_photo((select args||'{"idempotency_key":"other-account-result"}' from save_args)); raise exception 'accepted other owner'; exception when insufficient_privilege then null; end $$;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
-- No client can invent a sourced field or incomplete screenshot date.
do $$ declare id uuid:=gen_random_uuid(); v jsonb; begin
 v:=pg_temp.result(id,null,0)||'{"fields":[{"key":"duration","label":"时长","value":"30 分钟","source":"manual","confidence":1}]}';
 begin perform app.validate_byok_photo(auth.uid(),'camera',id,current_date,v); raise exception 'accepted manual'; exception when raise_exception then if sqlerrm='accepted manual' then raise; end if; end;
 v:=pg_temp.result(id,null,0)||'{"screenshot_date":"11-21"}';
 begin perform app.validate_byok_photo(auth.uid(),'screenshot',id,current_date,v); raise exception 'guessed date'; exception when raise_exception then if sqlerrm='guessed date' then raise; end if; end;
 end $$;

select app.build_report(auth.uid(),date_trunc('week',now() at time zone app.timezone_for(auth.uid()))::date,app.timezone_for(auth.uid()));
create temp table report_context as select id,public.report_ai_context(jsonb_build_object('report_id',id)) ctx from public.reports where user_id=auth.uid();
select pg_temp.ok((public.save_byok_report(jsonb_build_object('report_id',id,'version',ctx->>'version','fact_ids','["checkins"]'::jsonb))->>'applied')::boolean,'report selection applies') from report_context;
select pg_temp.ok(app.report_json(id)->>'ai_status'='ready','cached report appears for owner') from report_context;
select pg_temp.ok((select bool_and(public_snapshot='{}') from public.reports),'private AI does not write shared snapshot');
update public.reports set stage='final';
select pg_temp.ok(app.report_json(id)->>'ai_status'='rules','finalization invalidates old selection') from report_context;
select pg_temp.ok((public.save_byok_report(jsonb_build_object('report_id',id,'version',ctx->>'version','fact_ids','["checkins"]'::jsonb))->>'reason')='version_changed','stale report cannot overwrite final') from report_context;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
do $$ begin perform public.report_ai_context(jsonb_build_object('report_id',(select id from report_context))); raise exception 'report privacy bypass'; exception when insufficient_privilege then null; end $$;
rollback;
\echo 'PASS BYOK ownership, sources, votes, idempotency, versions, report privacy and cache'
