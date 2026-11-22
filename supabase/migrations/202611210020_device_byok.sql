-- AI execution belongs to the device. Non-AI jobs and all evidence remain.
create or replace function public.claim_jobs(p_kind text,p_limit int default 10) returns setof public.jobs
language sql security definer set search_path='' as $$
 update public.jobs set status='processing',attempts=attempts+1,lease_until=now()+interval '2 minutes',lease_token=gen_random_uuid()
 where id in(select id from public.jobs where kind=p_kind and p_kind not in ('ai','report') and available_at<=now()
 and (status='queued' or (status='processing' and lease_until<now())) order by available_at for update skip locked limit least(greatest(p_limit,1),20)) returning *
$$;
create function app.stop_server_ai_jobs() returns trigger language plpgsql set search_path='' as $$
begin if new.kind in ('ai','report') then return null; end if; return new; end $$;
create trigger stop_server_ai_jobs before insert on public.jobs for each row execute function app.stop_server_ai_jobs();
update public.jobs set status='dead',last_error='CLIENT_BYOK_REQUIRED',lease_token=null,lease_until=null
 where kind in ('ai','report') and status in ('queued','processing');
create or replace function public.apply_ai_result(p_checkin_id uuid,p_result jsonb) returns jsonb
language sql security definer set search_path='' as $$ select '{"applied":false,"reason":"client_byok_required"}'::jsonb $$;
create or replace function public.apply_report_result(p_report_id uuid,p_result jsonb) returns jsonb
language sql security definer set search_path='' as $$ select '{"applied":false,"reason":"client_byok_required"}'::jsonb $$;
-- Explicitly authorized removal of current ciphertext, not historical backups.
drop table public.ai_settings;
drop function app.guard_ai_settings_owner();

alter table public.checkins add column plan_selection text not null default 'all'
 check (plan_selection in ('all','manual','ai'));
update public.checkins set plan_selection='manual' where plan_id is not null;

-- Keep existing independent per-image results. Do not rewrite historic memos.
update public.media m set metadata=metadata||jsonb_build_object('byok',jsonb_build_object(
 'photo_id',m.id,'status',a.recognition_status,'summary',coalesce(a.result->'groups'->0->>'summary',''),
 'fields',coalesce(a.result->'groups'->0->'fields','[]'),'plan_id',a.result->'assignments'->0->'plan_id',
 'confidence',coalesce(a.result->'assignments'->0->'confidence','0'),'screenshot_date',a.screenshot_date,
 'origin','legacy','revision',0,'user_edited',false))
 from public.media_analysis a where a.media_id=m.id and not m.metadata ? 'byok';

create function app.validate_byok_photo(p_user uuid,p_source text,p_photo uuid,p_day date,p_result jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s text:=p_result->>'status'; plan uuid; selected_category text; f jsonb; fields jsonb:='[]'; name text; value text; ranges text[]; d date;
begin
 if jsonb_typeof(p_result) is distinct from 'object' or (p_result-array['photo_id','status','summary','fields','plan_id','confidence','screenshot_date','origin'])<>'{}'
 or p_result->>'photo_id' is distinct from p_photo::text or p_result->>'origin' is distinct from 'byok'
 or s not in ('ready','pending','rejected') or s is null
 or jsonb_typeof(p_result->'summary') is distinct from 'string' or length(p_result->>'summary')>2000
 or jsonb_typeof(p_result->'fields') is distinct from 'array' or jsonb_array_length(p_result->'fields')>30
 or jsonb_typeof(p_result->'confidence') is distinct from 'number' or (p_result->>'confidence')::numeric not between 0 and 1
 then raise exception '识别结果结构不完整'; end if;
 plan:=nullif(p_result->>'plan_id','')::uuid;
 if plan is not null then
  select p.category into selected_category from public.plans p where p.id=plan and p.user_id=p_user;
  if not found then raise exception using errcode='42501',message='识别计划不属于当前账号'; end if;
 end if;
 if (p_result->>'confidence')::numeric<0.8 then plan:=null; end if;
 if nullif(p_result->>'screenshot_date','') is not null then
  if p_result->>'screenshot_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception '截图日期必须完整'; end if;
  d:=(p_result->>'screenshot_date')::date;
  if to_char(d,'YYYY-MM-DD')<>p_result->>'screenshot_date' then raise exception '截图日期无效'; end if;
 end if;
 if s='ready' and p_source='screenshot' and (d is null or d<>p_day) then raise exception '截图日期与记录日期不符'; end if;
 if s<>'ready' and (jsonb_array_length(p_result->'fields')>0 or plan is not null) then raise exception '未完成识别不能提交字段或归类'; end if;
 for f in select * from jsonb_array_elements(p_result->'fields') loop
  if jsonb_typeof(f) is distinct from 'object' or (f-array['key','label','value','source','confidence'])<>'{}'
   or jsonb_typeof(f->'key') is distinct from 'string' or length(f->>'key') not between 1 and 100
   or jsonb_typeof(f->'label') is distinct from 'string' or length(f->>'label') not between 1 and 100
   or jsonb_typeof(f->'value') is distinct from 'string' or length(f->>'value')>500
   or jsonb_typeof(f->'confidence') is distinct from 'number' or (f->>'confidence')::numeric not between 0 and 1
   or coalesce(f->>'source','') not in ('ai','screenshot') then raise exception '字段来源或结构无效'; end if;
  name:=(f->>'key')||(f->>'label'); value:=f->>'value';
  if f->>'source'='screenshot' and p_source<>'screenshot' then raise exception '照片不能伪装截图读数'; end if;
  if f->>'source'='ai' and name ~* '(duration|distance|volume|water_ml|sleep|meditation|时长|距离|消耗|饮水量|毫升|睡眠)' then raise exception '不能从照片推算数值'; end if;
  if f->>'source'='ai' and name ~* '(calor|energy|热量|卡路里)' then
   if selected_category is distinct from 'food' or value not like '%估算%' then raise exception '热量仅允许饮食估算区间'; end if;
   ranges:=regexp_match(value,'(\d+(?:\.\d+)?)\s*[-~至到]\s*(\d+(?:\.\d+)?)');
   if ranges is null or ranges[1]::numeric<0 or ranges[2]::numeric<ranges[1]::numeric then raise exception '热量估算区间无效'; end if;
   f:=f||jsonb_build_object('key','calorie_range','value',jsonb_build_object('min',ranges[1]::numeric,'max',ranges[2]::numeric,'unit','kcal','estimated',true));
  end if;
  fields:=fields||jsonb_build_array(f);
 end loop;
 return p_result||jsonb_build_object('plan_id',plan,'fields',fields,'origin','byok');
end $$;

-- Validate client results again inside the atomic original-registration RPC.
alter function public.register_direct_media(jsonb,jsonb) rename to register_direct_media_before_byok;
create function public.register_direct_media(p_media jsonb,p_analysis jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare value jsonb; begin
 value:=coalesce(p_media->'metadata'->'byok',jsonb_build_object('photo_id',p_media->>'id','origin','byok',
  'status','pending','summary','','fields','[]'::jsonb,'plan_id',null,'confidence',0,'screenshot_date',null));
 value:=app.validate_byok_photo((p_media->>'user_id')::uuid,p_media->>'source',(p_media->>'id')::uuid,(p_media->>'local_date')::date,value)
  ||jsonb_build_object('revision',0,'user_edited',false);
 return public.register_direct_media_before_byok(jsonb_set(p_media,'{metadata,byok}',value),p_analysis);
end $$;
revoke all on function public.register_direct_media_before_byok(jsonb,jsonb),public.register_direct_media(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.register_direct_media_before_byok(jsonb,jsonb) from service_role;
grant execute on function public.register_direct_media(jsonb,jsonb) to service_role;

create function public.ai_context(p_args jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); m public.media; c public.checkins; d date; zone text; selected uuid:=nullif(p_args->>'plan_id','')::uuid; plans jsonb;
begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 if not exists(select 1 from public.profiles where id=u and deletion_requested_at is null) then raise exception using errcode='42501',message='账号正在删除'; end if;
 zone:=app.timezone_for(u); d:=(now() at time zone zone)::date;
 if nullif(p_args->>'media_id','') is not null then
  select * into m from public.media where id=(p_args->>'media_id')::uuid and user_id=u and deleted_at is null;
  if not found then raise exception using errcode='42501',message='照片已不可用'; end if;
  if m.checkin_id is null then return jsonb_build_object('awaiting_confirmation',true); end if;
  select * into c from public.checkins where id=m.checkin_id and user_id=u;
  if not found then raise exception using errcode='42501',message='记录已不可用'; end if;
  zone:=c.timezone; d:=m.local_date; selected:=c.plan_id;
 end if;
 select coalesce(jsonb_agg(to_jsonb(p)),'[]') into plans from public.ai_plan_candidates(u,coalesce(c.local_date,d),p_selected=>selected) p;
 if jsonb_array_length(plans)>=25 and selected is null then plans:='[]'; end if;
 return jsonb_build_object('timezone',zone,'local_date',d,'plans',plans,'checkin_id',c.id,'record_version',c.version,
 'photo_revision',coalesce((m.metadata->'byok'->>'revision')::int,0),'scope_team_id',app.team_for(u),
 'created_at',c.created_at,'source',m.source,'batch_id',m.batch_id,'result',m.metadata->'byok');
end $$;

create function app.rebuild_byok_checkin(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.checkins; total int; complete boolean; winner uuid; v_summary text; v_fields jsonb; field jsonb; cat text; private_photo boolean;
begin
 select * into c from public.checkins where id=p_id for update;
 if not found then return; end if;
 select count(*),coalesce(bool_and(coalesce(metadata->'byok'->>'status'='ready',false)),false) into total,complete from public.media where checkin_id=c.id and deleted_at is null;
 if total=0 then return; end if;
 if c.plan_selection='manual' then winner:=c.plan_id;
 elsif complete then
  select p.id into winner from public.media m join public.plans p on p.id=nullif(m.metadata->'byok'->>'plan_id','')::uuid
  where m.checkin_id=c.id and m.deleted_at is null and p.user_id=c.user_id and (m.metadata->'byok'->>'confidence')::numeric>=0.8
  group by p.id having count(*)>total/2.0 limit 1;
 end if;
 cat:=coalesce((select category from public.plans where id=winner),'all');
 select string_agg(distinct nullif(metadata->'byok'->>'summary',''),E'\n') into v_summary from public.media where checkin_id=c.id and deleted_at is null;
 v_fields:='[]';
 for field in select distinct value from public.media m cross join lateral jsonb_array_elements(coalesce(m.metadata->'byok'->'fields','[]'))
  where m.checkin_id=c.id and m.deleted_at is null loop
  if app.validate_fields(jsonb_build_array(field),cat) then v_fields:=v_fields||jsonb_build_array(field); end if;
 end loop;
 select exists(select 1 from public.media m join public.plans p on p.id=nullif(m.metadata->'byok'->>'plan_id','')::uuid
  where m.checkin_id=c.id and m.deleted_at is null and p.visibility='private') into private_photo;
 update public.checkins set plan_id=winner,plan_selection=case when c.plan_selection='manual' then 'manual' when winner is null then 'all' else 'ai' end,
  visibility=case when c.plan_selection<>'manual' and (private_photo or c.user_edited) then 'private' else coalesce((select visibility from public.plans where id=winner),'private') end,
  summary=case when c.user_edited then c.summary else coalesce(nullif(v_summary,''),c.summary) end,
  fields=case when c.user_edited then c.fields else v_fields end,
  memo_status=case when complete then 'ready' else 'pending' end,classification_pending=winner is null,
  version=c.version+case when complete and c.memo_status<>'ready' then 1 else 0 end,
  is_late=case when c.redo_of is not null or c.is_makeup then c.is_late when winner is null then false
   when app.plan_on_day(winner,c.local_date)->>'schedule_kind'='weekly_target' then false
   else (c.created_at at time zone c.timezone)::time>(app.plan_on_day(winner,c.local_date)->>'deadline')::time end
 where id=c.id;
 update public.media set plan_id=winner where checkin_id=c.id and deleted_at is null;
 if winner is not null then update public.overdue_feed set status='resolved' where user_id=c.user_id and plan_id=winner and local_date=c.local_date; end if;
end $$;

create function public.save_byok_photo(p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); m public.media; c public.checkins; result jsonb; previous jsonb; idem text:='byok:'||(p_args->>'idempotency_key'); clean jsonb;
begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 if not exists(select 1 from public.profiles where id=u and deletion_requested_at is null) then raise exception using errcode='42501',message='账号正在删除'; end if;
 if char_length(coalesce(idem,'')) not between 13 and 133 then raise exception '提交标识不完整'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 select s.result into result from public.submissions s where s.user_id=u and s.idempotency_key=idem;
 if found then return result; end if;
 select * into m from public.media where id=(p_args->>'media_id')::uuid and user_id=u and deleted_at is null;
 if not found or m.checkin_id is null then raise exception using errcode='42501',message='照片尚未关联有效记录'; end if;
 select * into c from public.checkins where id=m.checkin_id and user_id=u for update;
 if not found then raise exception using errcode='42501',message='记录不可用'; end if;
 select * into m from public.media where id=m.id and deleted_at is null for update;
 if not found then raise exception using errcode='42501',message='照片已删除'; end if;
 previous:=coalesce(m.metadata->'byok','{}');
 if c.version is distinct from (p_args->>'expected_version')::int
 or coalesce((previous->>'revision')::int,0) is distinct from (p_args->>'expected_photo_revision')::int
 or app.team_for(u) is distinct from nullif(p_args->>'scope_team_id','')::uuid
 or coalesce((previous->>'user_edited')::boolean,false)
 then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 clean:=app.validate_byok_photo(u,m.source,m.id,m.local_date,p_args->'result');
 if previous->>'status'='ready' and clean->>'status'<>'ready' then
  return jsonb_build_object('applied',false,'reason','preserved_ready'); end if;
 clean:=clean||jsonb_build_object('revision',coalesce((previous->>'revision')::int,0)+1,'user_edited',false);
 update public.media set metadata=metadata||jsonb_build_object('byok',clean) where id=m.id;
 perform app.rebuild_byok_checkin(c.id);
 result:=jsonb_build_object('applied',true,'checkin_ids',jsonb_build_array(c.id));
 insert into public.submissions(user_id,idempotency_key,result) values(u,idem,result);
 return result;
end $$;

-- Decorate the existing action transaction; old clients can still stamp ALL.
alter function public.app_action(text,jsonb) rename to app_action_before_byok;
create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; cid uuid; begin
 if p_action='submit_checkin' then
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  select s.result into result from public.submissions s where s.user_id=auth.uid() and s.idempotency_key=p_args->>'idempotency_key';
  if found then return result; end if;
 end if;
 result:=public.app_action_before_byok(p_action,p_args);
 if p_action='submit_checkin' then
  for cid in select jsonb_array_elements_text(result->'checkin_ids')::uuid loop
   update public.checkins set plan_selection=case when nullif(p_args->>'plan_id','') is not null or redo_of is not null or is_makeup then 'manual' else 'all' end, user_edited=user_edited or length(trim(coalesce(p_args->>'note','')))>0 where id=cid and user_id=auth.uid();
   perform app.rebuild_byok_checkin(cid);
  end loop;
 elsif p_action='reclassify' then
  update public.checkins set plan_selection='manual' where id=(p_args->>'checkin_id')::uuid and user_id=auth.uid();
 end if;
 return result;
end $$;
revoke all on function public.app_action_before_byok(text,jsonb) from public,anon,authenticated;
revoke all on function public.app_action(text,jsonb),public.ai_context(jsonb),public.save_byok_photo(jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb),public.ai_context(jsonb),public.save_byok_photo(jsonb) to authenticated;
revoke all on function app.validate_byok_photo(uuid,text,uuid,date,jsonb),app.rebuild_byok_checkin(uuid),app.stop_server_ai_jobs() from public,anon,authenticated;

-- All record readers share the permission check in the original implementation.
alter function app.checkin_json(uuid) rename to checkin_json_before_byok;
create function app.checkin_json(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select base||jsonb_build_object('photos',coalesce((select jsonb_agg(photo||jsonb_build_object('recognition',m.metadata->'byok') order by n)
 from jsonb_array_elements(base->'photos') with ordinality x(photo,n) join public.media m on m.id=(photo->>'id')::uuid),'[]'))
 from (select app.checkin_json_before_byok(p_id) base) b where base is not null
$$;
revoke all on function app.checkin_json(uuid),app.checkin_json_before_byok(uuid) from public,anon,authenticated;

-- Personal report AI selects server-produced facts. It cannot invent metrics or
-- write the shared snapshot. A content fingerprint invalidates cached selections.
create table public.report_ai_results (
 report_id uuid primary key references public.reports(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 version text not null, summary text not null, fact_ids jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.report_ai_results enable row level security;
revoke all on public.report_ai_results from anon,authenticated;

create function public.report_ai_context(p_args jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r public.reports; facts jsonb:='[]'; p jsonb; v text; total_seconds numeric; rows_version text;
begin
 select * into r from public.reports where id=(p_args->>'report_id')::uuid and user_id=auth.uid() and kind='personal';
 if not found then raise exception using errcode='42501',message='只能为本人的周报生成摘要'; end if;
 select coalesce(string_agg(c.id::text||':'||c.version::text,',' order by c.id),'') into rows_version
 from public.checkins c where c.user_id=r.user_id and c.local_date between r.week_start and r.week_start+6;
 v:=md5(jsonb_build_object('metrics',r.metrics,'stage',r.stage,'generated_at',r.generated_at,'records',rows_version)::text);
 if r.metrics->>'checkins' ~ '^\d+$' then facts:=facts||jsonb_build_array(jsonb_build_object('id','checkins','text','这周留下了 '||(r.metrics->>'checkins')||' 次打卡记录。')); end if;
 if r.metrics->>'completed' ~ '^\d+$' and r.metrics->>'expected' ~ '^\d+$' and (r.metrics->>'expected')::int>0 then
 facts:=facts||jsonb_build_array(jsonb_build_object('id','completion','text','计划应完成 '||(r.metrics->>'expected')||' 次，已完成 '||(r.metrics->>'completed')||' 次。')); end if;
 for p in select * from jsonb_array_elements(coalesce(r.metrics->'plans','[]')) loop
  if p->>'completed' ~ '^\d+$' and (p->>'completed')::int>0 then
   facts:=facts||jsonb_build_array(jsonb_build_object('id','plan:'||(p->>'id'),'text','「'||left(p->>'title',80)||'」完成了 '||(p->>'completed')||' 天。'));
  end if;
 end loop;
 select sum(seconds) into total_seconds from (
  select distinct on (c.id) c.id,
   (regexp_match(f->>'value','^(\d+(?:\.\d+)?)'))[1]::numeric *
   case when f->>'value' ~* '(分钟|minute)' then 60 when f->>'value' ~* '(小时|hour)' then 3600 when f->>'value' ~* '(秒|second)' then 1
   when f->>'key'='duration_minutes' then 60 when f->>'key'='duration_hours' then 3600 when f->>'key'='duration_seconds' then 1 end seconds
  from public.checkins c cross join lateral jsonb_array_elements(c.fields) f
  where c.user_id=r.user_id and exists(select 1 from public.plans p where p.id=c.plan_id and p.category='exercise') and c.status in ('stamped','makeup')
   and c.local_date between r.week_start and r.week_start+6
   and f->>'source' in ('screenshot','timer','health') and f->>'key' in ('duration','duration_seconds','duration_minutes','duration_hours')
   and f->>'value' ~* '^\d+(?:\.\d+)?\s*(秒|分钟|小时|seconds?|minutes?|hours?)?$'
  order by c.id,case f->>'source' when 'timer' then 3 when 'health' then 2 else 1 end desc
 ) q;
 if total_seconds>0 then facts:=facts||jsonb_build_array(jsonb_build_object('id','duration','text','有来源的运动时长累计 '||round(total_seconds/60)||' 分钟。')); end if;
 return jsonb_build_object('report_id',r.id,'version',v,'facts',facts,'cached',exists(select 1 from public.report_ai_results a where a.report_id=r.id and a.version=v));
end $$;

create function public.save_byok_report(p_args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.reports; ctx jsonb; ids jsonb:=p_args->'fact_ids'; fact_id text; sentence text; content text:=''; begin
 select * into r from public.reports where id=(p_args->>'report_id')::uuid and user_id=auth.uid() and kind='personal' for update;
 if not found then raise exception using errcode='42501',message='周报不可用'; end if;
 ctx:=public.report_ai_context(p_args);
 if ctx->>'version' is distinct from p_args->>'version' then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 if jsonb_typeof(ids) is distinct from 'array' or jsonb_array_length(ids) not between 1 and 4
 or exists(select 1 from jsonb_array_elements(ids) x where jsonb_typeof(x)<>'string')
 or (select count(distinct x) from jsonb_array_elements_text(ids) x)<>jsonb_array_length(ids) then raise exception '周报事实选择无效'; end if;
 for fact_id in select jsonb_array_elements_text(ids) loop
  select f->>'text' into sentence from jsonb_array_elements(ctx->'facts') f where f->>'id'=fact_id;
  if sentence is null then raise exception '周报包含未知事实'; end if;
  content:=content||sentence;
 end loop;
 insert into public.report_ai_results(report_id,user_id,version,summary,fact_ids) values(r.id,auth.uid(),ctx->>'version',content,ids)
 on conflict(report_id) do update set version=excluded.version,summary=excluded.summary,fact_ids=excluded.fact_ids,created_at=now();
 return jsonb_build_object('applied',true);
end $$;
revoke all on function public.report_ai_context(jsonb),public.save_byok_report(jsonb) from public,anon;
grant execute on function public.report_ai_context(jsonb),public.save_byok_report(jsonb) to authenticated;

alter function app.report_json(uuid) rename to report_json_before_byok;
create function app.report_json(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare base jsonb; ctx jsonb; saved public.report_ai_results; begin
 base:=app.report_json_before_byok(p_id);
 if base is null then return null; end if;
 if base->>'user_id'=auth.uid()::text and base->>'kind'='personal' then
  ctx:=public.report_ai_context(jsonb_build_object('report_id',p_id));
  select * into saved from public.report_ai_results where report_id=p_id and version=ctx->>'version';
  base:=base||jsonb_build_object('ai_version',ctx->>'version','ai_status',case when found then 'ready' else 'rules' end);
  if found then base:=base||jsonb_build_object('summary',saved.summary); end if;
 end if;
 return base;
end $$;
revoke all on function app.report_json(uuid),app.report_json_before_byok(uuid) from public,anon,authenticated;
