alter table public.media add column analysis_path text, add column metadata jsonb not null default '{}';
alter table public.jobs add column lease_token uuid, add column deadline_at timestamptz;
alter table public.push_outbox add column lease_token uuid;

create function public.reserve_photo(p_id uuid,p_batch_id uuid,p_source text,p_storage_path text,p_analysis_path text,p_captured_at timestamptz,p_phash text,p_metadata jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; tz text; d date; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 t:=app.team_for(u); tz:=app.timezone_for(u); d:=(now() at time zone tz)::date;
 if p_storage_path not like u::text||'/%' or (p_analysis_path is not null and p_analysis_path not like u::text||'/%') then raise exception '照片路径不可用'; end if;
 if p_source not in ('camera','album','screenshot') or p_captured_at is null or (p_captured_at at time zone tz)::date<>d then raise exception '这张不是今天拍的，请换一张今天的照片'; end if;
 if char_length(p_phash)<8 or p_batch_id is null then raise exception '照片校验信息不完整'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_batch_id::text,1));
 if (select count(*) from public.media where user_id=u and batch_id=p_batch_id and deleted_at is null)>=9 then raise exception '每次最多 9 张照片'; end if;
 insert into public.media(id,user_id,team_id,batch_id,path,analysis_path,source,captured_at,local_date,phash,metadata)
 values(p_id,u,t,p_batch_id,p_storage_path,p_analysis_path,p_source,p_captured_at,d,p_phash,coalesce(p_metadata,'{}'));
 return jsonb_build_object('id',p_id,'path',p_storage_path,'captured_at',p_captured_at,'source',p_source);
exception when unique_violation then raise exception '这张照片已经用过，请换一张';
end $$;
revoke all on function public.reserve_photo(uuid,uuid,text,text,text,timestamptz,text,jsonb) from public,anon;
grant execute on function public.reserve_photo(uuid,uuid,text,text,text,timestamptz,text,jsonb) to authenticated;

create function public.claim_jobs(p_kind text,p_limit int default 10) returns setof public.jobs
language sql security definer set search_path='' as $$
 update public.jobs set status='processing',attempts=attempts+1,lease_until=now()+interval '2 minutes',lease_token=gen_random_uuid()
 where id in(select id from public.jobs where kind=p_kind and available_at<=now() and (status='queued' or (status='processing' and lease_until<now())) order by available_at for update skip locked limit least(greatest(p_limit,1),20)) returning *
$$;
create function public.finish_job(p_id uuid,p_lease_token uuid,p_error text default null,p_retry_at timestamptz default null) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 update public.jobs set status=case when p_error is null then 'done' when p_retry_at is not null then 'queued' else 'dead' end,
  last_error=p_error,available_at=coalesce(p_retry_at,available_at),lease_until=null,lease_token=null where id=p_id and lease_token=p_lease_token and status='processing';
 return found;
end $$;
create function public.claim_push(p_limit int default 20) returns setof public.push_outbox
language sql security definer set search_path='' as $$
 update public.push_outbox set status='processing',attempts=attempts+1,lease_until=now()+interval '2 minutes',lease_token=gen_random_uuid()
 where id in(select id from public.push_outbox where available_at<=now() and (status='queued' or (status='processing' and lease_until<now())) order by available_at for update skip locked limit least(greatest(p_limit,1),50)) returning *
$$;
create function public.finish_push(p_id uuid,p_lease_token uuid,p_error text default null,p_retry_at timestamptz default null) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 update public.push_outbox set status=case when p_error is null then 'done' when p_retry_at is not null then 'queued' else 'dead' end,
  error=p_error,available_at=coalesce(p_retry_at,available_at),lease_until=null,lease_token=null where id=p_id and lease_token=p_lease_token and status='processing'; return found;
end $$;

create function public.apply_ai_result(p_checkin_id uuid,p_result jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.checkins; a jsonb; g jsonb; pid uuid; newid uuid; groupids uuid[]; fields jsonb; category text; target record; begin
 select * into c from public.checkins where id=p_checkin_id for update;
 if not found then return jsonb_build_object('applied',false,'reason','missing'); end if;
 if c.version<>coalesce((p_result->>'version')::int,0) or c.user_edited then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 if jsonb_typeof(p_result->'assignments')<>'array' then raise exception 'AI assignments schema mismatch'; end if;
 if c.plan_id is null then
  for a in select value from jsonb_array_elements(p_result->'assignments') loop
   pid:=nullif(a->>'plan_id','')::uuid;
   if pid is not null and not exists(select 1 from public.plans where id=pid and user_id=c.user_id and status='active') then pid:=null; end if;
   update public.media set plan_id=pid,confidence=least(1,greatest(0,coalesce((a->>'confidence')::numeric,0))) where id=(a->>'photo_id')::uuid and checkin_id=c.id;
  end loop;
  for target in select distinct m.plan_id from public.media m where m.checkin_id=c.id loop
   pid:=target.plan_id;
   if groupids is null then
    newid:=c.id;
    update public.checkins set plan_id=pid,visibility=coalesce((select visibility from public.plans where id=pid),'team') where id=c.id;
   else
    insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,status,is_makeup,is_late,summary,fields,memo_status,visibility,team_size,created_at)
    values(c.user_id,c.team_id,pid,c.batch_id,c.local_date,c.timezone,c.status,c.is_makeup,c.is_late,'','[]','pending',coalesce((select visibility from public.plans where id=pid),'team'),c.team_size,c.created_at) returning id into newid;
   end if;
   update public.media set checkin_id=newid where checkin_id=c.id and plan_id is not distinct from pid;
   groupids:=array_append(groupids,newid);
  end loop;
 else groupids:=array[c.id]; end if;
 foreach newid in array coalesce(groupids,array[c.id]) loop
  select coalesce(p.category,'all') into category from public.checkins x left join public.plans p on p.id=x.plan_id where x.id=newid;
  select value into g from jsonb_array_elements(coalesce(p_result->'groups','[]')) where nullif(value->>'plan_id','')::uuid is not distinct from (select plan_id from public.checkins where id=newid) limit 1;
  fields:=coalesce(g->'fields',p_result->'fields','[]');
  if not app.validate_fields(fields,category) then raise exception 'AI fields violate source/range rules'; end if;
  update public.checkins set summary=left(coalesce(g->>'summary',p_result->>'summary',''),4000),fields=fields,memo_status='ready' where id=newid and not user_edited;
  update public.overdue_feed set status='resolved' where plan_id=(select plan_id from public.checkins where id=newid) and local_date=c.local_date and user_id=c.user_id;
 end loop;
 return jsonb_build_object('applied',true,'checkin_ids',to_jsonb(groupids));
end $$;

create function app.build_report(p_user uuid,p_week date,p_tz text) returns uuid
language plpgsql security definer set search_path='' as $$
declare rid uuid; t uuid:=app.team_for(p_user); total int; completed int; expected int; makeup int; previous_rate numeric; rate numeric; title text:=''; m jsonb; hs jsonb; sugg jsonb:='{}'; suggested_plan record;
begin
 select count(*),count(*) filter(where is_makeup) into total,makeup from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') and redo_of is null;
 select count(*) into completed from (select distinct plan_id,local_date from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') and plan_id is not null) x;
 select count(*) into expected from public.plans p cross join generate_series(p_week::timestamp,(p_week+6)::timestamp,interval '1 day') d
 where p.user_id=p_user and p.status='active' and d::date>=(p.created_at at time zone p_tz)::date and extract(isodow from d)::int=any(p.weekdays);
 rate:=case when expected=0 then 0 else least(1,completed::numeric/expected) end;
 if expected>0 and completed>=expected and makeup=0 then title:='最稳的一个，零漏打';
 elsif total>0 and not exists(select 1 from public.team_members tm where tm.team_id=t and tm.left_at is null and (select count(*) from public.checkins c where c.user_id=tm.user_id and c.local_date between p_week and p_week+6 and c.status in ('stamped','makeup') and c.redo_of is null)>total) then title:='你是这周打卡最积极的人';
 end if;
 m:=jsonb_build_object('checkins',total,'completed',completed,'expected',expected,'makeup',makeup,'completion_rate',rate,'streak',app.streak(p_user),
  'unclassified',(select count(*) from public.checkins where user_id=p_user and plan_id is null and local_date between p_week and p_week+6),'plans',
  coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'title',x.title,'completed',(select count(distinct local_date) from public.checkins where plan_id=x.id and status in ('stamped','makeup') and local_date between p_week and p_week+6))) from public.plans x where x.user_id=p_user),'[]'));
 select coalesce(jsonb_agg(s),'[]') into hs from (select id,summary,local_date from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') order by created_at desc limit 3) s;
 select * into suggested_plan from public.plans x where x.user_id=p_user and x.status='active' and (select count(distinct local_date) from public.checkins where plan_id=x.id and status in ('stamped','makeup') and local_date between p_week and p_week+6)<cardinality(x.weekdays) order by created_at limit 1;
 if found then sugg:=jsonb_build_object('plan_id',suggested_plan.id,'text','下周保留一个更容易开始的时段。','changes',jsonb_build_object('start_time',suggested_plan.start_time::text)); end if;
 insert into public.reports(user_id,team_id,week_start,timezone,kind,title,summary,metrics,highlights,suggestion)
 values(p_user,t,p_week,p_tz,'personal',title,'这周完成了 '||total||' 次打卡。一起看看留下的记录。',m,hs,sugg)
 on conflict(user_id,week_start) where kind='personal' do update set title=excluded.title,summary=excluded.summary,metrics=excluded.metrics,highlights=excluded.highlights,suggestion=excluded.suggestion returning id into rid;
 return rid;
end $$;

create function public.run_schedule(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p record; u record; tm record; d date; local_now timestamp; tz text; due timestamptz; rid uuid; nid uuid; cnt int:=0; begin
 perform pg_advisory_xact_lock(hashtextextended('better-together-scheduler',0));
 update public.checkins set status='incomplete' where status='redo_required' and redo_deadline<=p_now;
 for p in select x.*,app.timezone_for(x.user_id) tz,app.team_for(x.user_id) team from public.plans x loop
  local_now:=p_now at time zone p.tz; d:=local_now::date;
  if p.effective_on<=d and p.next_config is not null then
   update public.plans set title=coalesce(p.next_config->>'title',title),goal=coalesce(p.next_config->>'goal',goal),category=coalesce(p.next_config->>'category',category),
   weekdays=case when p.next_config ? 'weekdays' then array(select jsonb_array_elements_text(p.next_config->'weekdays')::int) else weekdays end,
   start_time=coalesce((p.next_config->>'start_time')::time,start_time),deadline=coalesce((p.next_config->>'deadline')::time,deadline),visibility=coalesce(p.next_config->>'visibility',visibility),status=coalesce(p.next_config->>'status',status),next_config=null,effective_on=null where id=p.id;
   select x.*,p.tz tz,p.team team into p from public.plans x where x.id=p.id;
  end if;
  if p.status<>'active' or (p.created_at at time zone p.tz)::date>d or not extract(isodow from d)::int=any(p.weekdays) or exists(select 1 from public.profiles where id=p.user_id and paused_week=date_trunc('week',d::timestamp)::date) then continue; end if;
  if exists(select 1 from public.checkins where user_id=p.user_id and plan_id=p.id and local_date=d and status in ('stamped','makeup')) then continue; end if;
  due:=least((d+time '23:30') at time zone p.tz,((d+p.deadline) at time zone p.tz)+interval '30 minutes');
  if due<=p_now and p.team is not null and p.visibility='team' then
   insert into public.overdue_feed(team_id,user_id,plan_id,local_date,deadline_at) values(p.team,p.user_id,p.id,d,(d+p.deadline) at time zone p.tz) on conflict(plan_id,local_date) do nothing returning id into nid;
   if nid is not null then cnt:=cnt+1; perform app.notify(p.user_id,'overdue','今天还有一个计划',p.title||' 尚未完成，方便时补上。',nid,'overdue:'||nid); end if;
  end if;
  if local_now::time>=p.start_time and local_now::time<p.deadline then perform app.notify(p.user_id,'reminder','计划可以开始了',p.title,p.id,'start:'||p.id||':'||d); end if;
  if local_now::time<p.deadline and p_now>=((d+p.deadline) at time zone p.tz)-interval '1 hour' then perform app.notify(p.user_id,'reminder','给今天留一点时间',p.title||' 将在一小时内截止。',p.id,'before:'||p.id||':'||d); end if;
 end loop;
 for u in select id,created_at,app.timezone_for(id) tz from public.profiles loop
  local_now:=p_now at time zone u.tz; d:=date_trunc('week',local_now)::date;
  if extract(isodow from local_now)=7 and local_now::time>='19:00' then perform app.notify(u.id,'report','今晚整理这一周','20:00 可以查看本周记录。',null,'report-preview:'||u.id||':'||d); end if;
  if local_now<(d+6+time '20:00') then d:=d-7; end if;
  if (u.created_at at time zone u.tz)::date<=d+6 and not exists(select 1 from public.reports where user_id=u.id and week_start=d and kind='personal') then
   rid:=app.build_report(u.id,d,u.tz); perform app.notify(u.id,'report','本周周报已备好','看看这一周留下了哪些记录。',rid,'report:'||rid);
   insert into public.jobs(kind,payload) values('report',jsonb_build_object('report_id',rid));
  end if;
 end loop;
 for tm in select * from public.teams where dissolved_at is null loop
  local_now:=p_now at time zone tm.timezone; d:=date_trunc('week',local_now)::date;
  if local_now<(d+6+time '20:00') then d:=d-7; end if;
  if (tm.created_at at time zone tm.timezone)::date<=d+6 then
   insert into public.reports(team_id,week_start,timezone,kind,title,summary,metrics)
   select tm.id,d,tm.timezone,'team','一起留下的记录','每个人有自己的目标，我们一起继续。',app.team_week_counts(tm.id,d)
   from public.checkins c where c.team_id=tm.id and c.visibility='team' and app.team_for(c.user_id)=tm.id and c.status in ('stamped','makeup') and c.local_date between d and d+6 and c.redo_of is null
   on conflict(team_id,week_start) where kind='team' do nothing;
  end if;
 end loop;
 return jsonb_build_object('overdue_created',cnt);
end $$;
create function public.schedule_due() returns jsonb language sql security definer set search_path='' as $$ select public.run_schedule(now()) $$;

do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('claim_jobs','finish_job','claim_push','finish_push','apply_ai_result','run_schedule','schedule_due') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
