\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,m text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'ASSERT: %',m; end if; end $$;
insert into auth.users(id) values('91000000-0000-4000-8000-000000000001'),('91000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select public.app_action('create_team','{"name":"分组测试","timezone":"Asia/Shanghai"}');
select public.app_action('save_plan','{"title":"学习","category":"study","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"23:50","visibility":"team","status":"active"}');
select public.app_action('save_plan','{"title":"运动","category":"exercise","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"23:50","visibility":"private","status":"active"}');
create temp table ctx as select gen_random_uuid() batch, (select id from public.plans where title='学习' and user_id=auth.uid()) study,(select id from public.plans where title='运动' and user_id=auth.uid()) exercise;
create function pg_temp.photo(b uuid,p uuid,c numeric default .9,s text default 'ready') returns uuid language plpgsql as $$
declare mid uuid:=gen_random_uuid(); begin
 insert into public.media(id,user_id,team_id,batch_id,path,source,captured_at,local_date,phash,metadata)
 values(mid,auth.uid(),app.team_for(auth.uid()),b,mid::text||'.jpg','camera',now(),(now() at time zone app.timezone_for(auth.uid()))::date,mid::text,
 jsonb_build_object('byok',jsonb_build_object('photo_id',mid,'origin','byok','status',s,'summary',case when s='ready' then '逐图摘要 '||mid else '' end,'fields','[]'::jsonb,'plan_id',p,'confidence',c,'revision',0,'user_edited',false)));
 return mid; end $$;
create function pg_temp.grouping(mid uuid,plan uuid,selection text default 'ai') returns jsonb language sql as $$
 select jsonb_build_object('media_ids',jsonb_build_array(mid),'plan_id',plan,'plan_selection',selection,'summary','不应覆盖逐图摘要的占位句','fields','[]'::jsonb,'user_edited',false) $$;
create temp table media_ids as select pg_temp.photo(batch,study) a,pg_temp.photo(batch,exercise) b from ctx;
create temp table request as select jsonb_build_object('idempotency_key','batch-test-submit','groups',jsonb_build_array(pg_temp.grouping(a,study),pg_temp.grouping(b,exercise))) args from ctx,media_ids;
create temp table result as select public.app_action('submit_checkin_batch',args) value from request;
select pg_temp.ok(jsonb_array_length(value->'checkin_ids')=2,'mixed photos create two checkins') from result;
select pg_temp.ok((select count(distinct checkin_id)=2 and bool_and(checkin_id is not null) from public.media where batch_id=(select batch from ctx)),'media bound exactly to its group');
select pg_temp.ok((select bool_and(c.summary='逐图摘要 '||m.id and c.plan_id=m.plan_id) from public.checkins c join public.media m on m.checkin_id=c.id where c.batch_id=(select batch from ctx)),'each record retains its own summary and plan');
select pg_temp.ok(public.app_action('submit_checkin_batch',args)=(select value from result),'repeat confirm returns same IDs') from request;
select pg_temp.ok((select count(*)=2 from public.checkins where batch_id=(select batch from ctx)),'idempotency does not create extra records');

-- Every rejected multi-group request rolls back its first group as well.
do $$ declare b uuid:=gen_random_uuid(); a uuid; z uuid; plan uuid:=(select study from ctx); n int; args jsonb; begin
 a:=pg_temp.photo(b,plan); z:=pg_temp.photo(gen_random_uuid(),plan);
 n:=(select count(*) from public.checkins where user_id=auth.uid());
 args:=jsonb_build_object('idempotency_key','batch-mismatch-test','groups',jsonb_build_array(pg_temp.grouping(a,plan),pg_temp.grouping(z,plan)));
 begin perform public.app_action('submit_checkin_batch',args); raise exception 'accepted different batches';
 exception when raise_exception then if sqlerrm='accepted different batches' then raise; end if; end;
 perform pg_temp.ok((select count(*)=n from public.checkins where user_id=auth.uid()),'mixed batch transaction rolls back');
 perform pg_temp.ok((select checkin_id is null from public.media where id=a),'first media remains unused after rollback');
 args:=jsonb_set(args,'{groups,1}',pg_temp.grouping(a,plan));
 begin perform public.app_action('submit_checkin_batch',args); raise exception 'accepted duplicate';
 exception when raise_exception then if sqlerrm='accepted duplicate' then raise; end if; end;
 perform pg_temp.ok((select checkin_id is null from public.media where id=a),'duplicate photo rejected atomically');
 -- Existing plan can receive another independent record on the same date.
 args:=jsonb_set(args,'{groups}',jsonb_build_array(pg_temp.grouping(a,plan)));
 perform public.app_action('submit_checkin_batch',args);
end $$;

do $$ declare b uuid:=gen_random_uuid(); a uuid; plan uuid:=(select study from ctx); args jsonb; v jsonb; cid uuid; context jsonb; begin
 a:=pg_temp.photo(b,plan,.79);
 args:=jsonb_build_object('idempotency_key','low-group-test','groups',jsonb_build_array(pg_temp.grouping(a,plan)));
 begin perform public.app_action('submit_checkin_batch',args); raise exception 'accepted low confidence AI';
 exception when raise_exception then if sqlerrm='accepted low confidence AI' then raise; end if; end;
 args:=jsonb_set(args,'{groups}',jsonb_build_array(pg_temp.grouping(a,null,'all')));
 v:=public.app_action('submit_checkin_batch',args);
 cid:=(v->'checkin_ids'->>0)::uuid;
 perform pg_temp.ok((select plan_id is null and summary='逐图摘要 '||a from public.checkins where id=cid),'low confidence ALL keeps summary');
 a:=pg_temp.photo(gen_random_uuid(),null,0,'pending');
 args:=jsonb_build_object('idempotency_key','manual-pending-test','groups',jsonb_build_array(pg_temp.grouping(a,plan,'manual')||'{"summary":"我确认的纪要","user_edited":true}'::jsonb));
 v:=public.app_action('submit_checkin_batch',args); cid:=(v->'checkin_ids'->>0)::uuid;
 context:=public.ai_context(jsonb_build_object('media_id',a));
 v:=public.save_byok_photo(jsonb_build_object('media_id',a,'expected_version',context->'record_version','expected_photo_revision',context->'photo_revision','scope_team_id',context->'scope_team_id','idempotency_key','batch-late-result','result',jsonb_build_object('photo_id',a,'origin','byok','status','ready','summary','补齐的照片摘要','fields','[]'::jsonb,'plan_id',(select exercise from ctx),'confidence',.9,'screenshot_date',null)));
 perform pg_temp.ok((v->>'applied')::boolean,'pending photo result can complete');
 perform pg_temp.ok((select plan_id=plan and summary='我确认的纪要' from public.checkins where id=cid),'late result preserves manual group and edited memo');
 perform pg_temp.ok((select metadata->'byok'->>'summary'='补齐的照片摘要' from public.media where id=a),'per-photo summary independently retained');
end $$;
select pg_temp.ok((select count(*)=2 from public.notifications n where n.kind='stamp' and n.target_id in (select jsonb_array_elements_text(value->'checkin_ids')::uuid from result)),'batch stamp notifications preserve existing behavior');
do $$ begin
 begin
  perform public.app_action('submit_checkin_batch',jsonb_build_object('target_date',(now() at time zone app.timezone_for(auth.uid()))::date-1,'makeup_reason','合成补卡','idempotency_key','makeup-all-not-allowed','groups',jsonb_build_array(jsonb_build_object('plan_id',null,'media_ids','[]'::jsonb))));
  raise exception 'accepted ALL makeup';
 exception when raise_exception then if sqlerrm<>'补卡时请选择原计划' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.app_action('submit_checkin_batch',(select args from request)); raise exception 'accepted other owner';
 exception when raise_exception then if sqlerrm='accepted other owner' then raise; end if; end;
end $$;
select pg_temp.ok(not has_function_privilege('authenticated','public.app_action_before_batch_checkin(text,jsonb)','execute'),'old wrapper cannot bypass batch validation');
rollback;
\echo 'PASS batch splits, binding, summaries, atomic rollback, ownership, repeated days, confidence, late edits and idempotency'
