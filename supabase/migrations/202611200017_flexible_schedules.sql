-- Additive schedules; existing clients retain weekday behavior and history.
alter table public.plans drop constraint plans_category_check;
alter table public.plans add constraint plans_category_check check(category in ('study','food','exercise','sleep','water','mindfulness','custom'));
alter table public.plans add column schedule_kind text not null default 'weekdays' check(schedule_kind in ('weekdays','weekly_target','interval')),
 add column weekly_target_days integer check(weekly_target_days between 1 and 7),
 add column interval_days integer check(interval_days between 1 and 365),
 add column anchor_date date;
update public.plans set anchor_date=(created_at at time zone app.timezone_for(user_id))::date;
alter table public.plans alter column anchor_date set not null;
create function app.default_plan_anchor() returns trigger language plpgsql set search_path='' as $$ begin
 if new.anchor_date is null then new.anchor_date:=(new.created_at at time zone app.timezone_for(new.user_id))::date; end if; return new;
end $$;
create trigger plan_anchor_default before insert on public.plans for each row execute function app.default_plan_anchor();
revoke all on function app.default_plan_anchor() from public,anon,authenticated;
alter table public.plans add constraint valid_schedule check((schedule_kind<>'weekly_target' or weekly_target_days is not null) and (schedule_kind<>'interval' or interval_days is not null));
alter table public.reports add column stage text not null default 'phase' check(stage in ('phase','final')),
 add column finalized_at timestamptz;
alter table public.overdue_feed add column schedule_kind text not null default 'weekdays';

create or replace function app.record_plan_revision() returns trigger language plpgsql security definer set search_path='' as $$
declare effective date; cfg jsonb; days int[]; begin
 cfg:=new.next_config;
 if cfg is not null then
  if coalesce(cfg->>'schedule_kind','weekdays') not in ('weekdays','weekly_target','interval')
   or (cfg->>'schedule_kind'='weekly_target' and coalesce((cfg->>'weekly_target_days')::int,0) not between 1 and 7)
   or (cfg->>'schedule_kind'='interval' and coalesce((cfg->>'interval_days')::int,0) not between 1 and 365)
   then raise exception '请核对计划频率'; end if;
  days:=array(select jsonb_array_elements_text(cfg->'weekdays')::int);
  if coalesce(char_length(trim(cfg->>'title')),0) not between 1 and 100
   or coalesce(cfg->>'category','') not in ('study','exercise','food','sleep','water','mindfulness','custom')
   or coalesce(cfg->>'status','active') not in ('active','paused','ended')
   or coalesce(cfg->>'visibility','team') not in ('team','private')
   or cardinality(days) not between 1 and 7 or not days<@array[1,2,3,4,5,6,7]
   or cardinality(days)<>(select count(distinct d) from unnest(days) d)
   or (cfg->>'start_time') is null or (cfg->>'deadline') is null
   or (cfg->>'start_time')::time>(cfg->>'deadline')::time then raise exception '请核对计划名称、频率、状态与时段'; end if;
 end if;
 if (select count(distinct d) from unnest(new.weekdays) d)<>cardinality(new.weekdays) then raise exception '每周日期不能重复'; end if;
 if tg_op='INSERT' then effective:=(new.created_at at time zone app.timezone_for(new.user_id))::date;
 elsif (to_jsonb(new)-array['next_config','effective_on']) is not distinct from (to_jsonb(old)-array['next_config','effective_on']) then return new;
 else effective:=coalesce(old.effective_on,(now() at time zone app.timezone_for(new.user_id))::date); end if;
 insert into public.plan_revisions(plan_id,effective_on,config) values(new.id,effective,to_jsonb(new)-array['next_config','effective_on'])
 on conflict(plan_id,effective_on) do update set config=excluded.config;
 return new;
end $$;
create or replace function app.plan_on_day(p_plan uuid,p_day date) returns jsonb language sql stable security definer set search_path='' as $$
 select config from (select effective_on,config from public.plan_revisions where plan_id=p_plan and effective_on<=p_day
 union all select effective_on,next_config from public.plans where id=p_plan and next_config is not null and effective_on<=p_day) c order by effective_on desc limit 1
$$;
create function app.plan_due(p_plan uuid,p_day date) returns boolean language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=app.plan_on_day(p_plan,p_day); anchor date; begin
 if cfg is null or cfg->>'status'<>'active' then return false; end if;
 anchor:=coalesce((cfg->>'anchor_date')::date,(cfg->>'created_at')::timestamptz::date);
 if p_day<anchor then return false; end if;
 if coalesce(cfg->>'schedule_kind','weekdays')='weekly_target' then return false; end if;
 if cfg->>'schedule_kind'='interval' then return (p_day-anchor)%((cfg->>'interval_days')::int)=0; end if;
 return cfg->'weekdays' @> to_jsonb(extract(isodow from p_day)::int);
end $$;
-- One completed date per plan, regardless of independent evidence records.
create function app.plan_week(p_plan uuid,p_day date,p_public boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w date:=date_trunc('week',p_day::timestamp)::date; d date; cfg jsonb; u uuid; eligible int:=0; completed int:=0; makeups int:=0; target int:=0; k text:='weekdays'; begin
 select user_id into u from public.plans where id=p_plan;
 if exists(select 1 from public.paused_weeks where user_id=u and week_start=w) then return jsonb_build_object('expected',0,'completed',0,'extra_days',0,'makeup',0,'schedule_kind',k); end if;
 for d in select generate_series(w::timestamp,(w+6)::timestamp,interval '1 day')::date loop
  cfg:=app.plan_on_day(p_plan,d);
  if cfg is null or cfg->>'status'<>'active' or d<coalesce((cfg->>'anchor_date')::date,w) or (p_public and cfg->>'visibility'<>'team') then continue; end if;
  if p_public and not exists(select 1 from public.team_members tm join public.teams t on t.id=tm.team_id where tm.user_id=u and tm.left_at is null and (tm.joined_at at time zone t.timezone)::date<=d) then continue; end if;
  k:=coalesce(cfg->>'schedule_kind','weekdays');
  if k<>'weekly_target' and not app.plan_due(p_plan,d) then continue; end if;
  eligible:=eligible+1; target:=coalesce((cfg->>'weekly_target_days')::int,0);
  if exists(select 1 from public.checkins c where c.plan_id=p_plan and c.local_date=d and c.status in ('stamped','makeup') and (not p_public or (c.visibility='team' and c.team_id=app.team_for(u) and app.in_sharing_period(c.team_id,u,c.created_at)))) then completed:=completed+1; end if;
  if exists(select 1 from public.checkins c where c.plan_id=p_plan and c.local_date=d and c.status='makeup' and (not p_public or (c.visibility='team' and c.team_id=app.team_for(u) and app.in_sharing_period(c.team_id,u,c.created_at)))) then makeups:=makeups+1; end if;
 end loop;
 target:=case when k='weekly_target' then least(target,eligible) else eligible end;
 return jsonb_build_object('expected',target,'completed',completed,'extra_days',greatest(0,completed-target),'makeup',makeups,'schedule_kind',k);
end $$;
create function app.plan_progress(p_plan uuid,p_day date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare counts jsonb:=app.plan_week(p_plan,p_day); w date:=date_trunc('week',p_day::timestamp)::date; earliest date; n int:=0; v jsonb; begin
 if counts->>'schedule_kind'='weekly_target' then
  select min(effective_on) into earliest from public.plan_revisions where plan_id=p_plan;
  while w+6>=earliest loop
   v:=app.plan_week(p_plan,w);
   if v->>'schedule_kind'<>'weekly_target' then exit; end if;
   if (v->>'expected')::int>0 then
    if (v->>'completed')::int>=(v->>'expected')::int then n:=n+1;
    elsif w<>date_trunc('week',p_day::timestamp)::date then exit; end if;
   end if;
   w:=w-7;
  end loop;
 end if;
 return jsonb_build_object('weekly_target',counts->'expected','weekly_completed',counts->'completed','extra_days',counts->'extra_days','weekly_streak',n);
end $$;

create or replace function app.day_outcome(p_user uuid,p_day date,p_plan uuid default null,p_public boolean default false) returns int
language plpgsql stable security definer set search_path='' as $$
declare p record; cfg jsonb; due_count int:=0; frozen boolean:=false; begin
 if exists(select 1 from public.paused_weeks where user_id=p_user and week_start=date_trunc('week',p_day::timestamp)::date) then return -1; end if;
 for p in select id from public.plans where user_id=p_user and (p_plan is null or id=p_plan) loop
  cfg:=app.plan_on_day(p.id,p_day);
  if cfg is null or cfg->>'status'<>'active' or (p_public and cfg->>'visibility'<>'team') or not app.plan_due(p.id,p_day) then continue; end if;
  due_count:=due_count+1;
  if exists(select 1 from public.checkins where plan_id=p.id and local_date=p_day and status='stamped' and not is_late) then null;
  elsif exists(select 1 from public.checkins where plan_id=p.id and local_date=p_day and status in ('makeup','redo_required')) then frozen:=true;
  else return 0; end if;
 end loop;
 if due_count=0 then return -1; end if;
 return case when frozen then 2 else 1 end;
end $$;

create or replace function app.week_counts(p_user uuid,p_week date,p_public boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare expected int:=0; completed int:=0; extra int:=0; makeups int:=0; total int; p record; v jsonb; plans jsonb:='[]'; pe int; pc int; begin
 for p in select id,title from public.plans where user_id=p_user loop
  v:=app.plan_week(p.id,p_week,p_public); pe:=(v->>'expected')::int; pc:=(v->>'completed')::int;
  expected:=expected+pe; completed:=completed+least(pc,pe); extra:=extra+(v->>'extra_days')::int; makeups:=makeups+(v->>'makeup')::int;
  if pe>0 then plans:=plans||jsonb_build_array(v||jsonb_build_object('id',p.id,'title',p.title,'completion_rate',least(1,pc::numeric/pe))); end if;
 end loop;
 select count(*) into total from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') and redo_of is null and (not p_public or (visibility='team' and team_id=app.team_for(p_user) and app.in_sharing_period(team_id,p_user,created_at)));
 return jsonb_build_object('checkins',total,'completed',completed,'expected',expected,'extra_days',extra,'makeup',makeups,'completion_rate',case when expected=0 then 0 else least(1,completed::numeric/expected) end,'plans',plans,
 'unclassified',(select count(*) from public.checkins where user_id=p_user and plan_id is null and local_date between p_week and p_week+6 and status in ('stamped','makeup') and (not p_public or (visibility='team' and team_id=app.team_for(p_user) and app.in_sharing_period(team_id,p_user,created_at)))));
end $$;

create or replace function public.app_action_core(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; tz text; today date; local_now timestamp; p public.plans; c public.checkins; o public.overdue_feed; r public.reports;
 rec record; result jsonb; token text; n int; cnt int; mid uuid; ids uuid[]; bid uuid; target date; oldid uuid; chosen uuid; planid uuid;
begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 t:=app.team_for(u); tz:=app.timezone_for(u); local_now:=now() at time zone tz; today:=local_now::date;
 case p_action
 when 'save_profile' then
  if p_args ? 'notification_preferences' and (jsonb_typeof(p_args->'notification_preferences') is distinct from 'object' or exists(select 1 from jsonb_each(p_args->'notification_preferences') x where x.key not in ('all','poke','overdue','report','interaction','challenge') or jsonb_typeof(x.value)<>'boolean')) then raise exception '通知设置需使用开关值'; end if;
  if p_args ? 'avatar_url' and p_args->>'avatar_url' is not null and p_args->>'avatar_url' not like 'preset:%' and p_args->>'avatar_url' not like u::text||'/%' then raise exception '请选择自己的头像'; end if;
  if p_args ? 'timezone' and t is not null then raise exception '小队时区创建后固定'; end if;
  if p_args ? 'timezone' and not exists(select 1 from pg_timezone_names where name=p_args->>'timezone') then raise exception '请选择有效时区'; end if;
  update public.profiles set nickname=coalesce(nullif(trim(p_args->>'nickname'),''),nickname),avatar_url=case when p_args ? 'avatar_url' then p_args->>'avatar_url' else avatar_url end,
   notification_preferences=notification_preferences||coalesce(p_args->'notification_preferences','{}'),timezone=coalesce(p_args->>'timezone',timezone) where id=u;
  return jsonb_build_object('updated',true);
 when 'create_team' then
  if t is not null then raise exception '请先退出当前小队'; end if;
  if not exists(select 1 from pg_timezone_names where name=p_args->>'timezone') then raise exception '请选择有效时区'; end if;
  insert into public.teams(name,timezone,owner_id) values(trim(p_args->>'name'),p_args->>'timezone',u) returning id into t;
  insert into public.team_members(team_id,user_id) values(t,u); return jsonb_build_object('id',t);
 when 'create_invite' then
  if t is null then raise exception '请先创建或加入小队'; end if;
  token:=encode(extensions.gen_random_bytes(24),'hex');
  insert into public.invites(team_id,token_hash,expires_at,created_by) values(t,encode(extensions.digest(token,'sha256'),'hex'),now()+interval '7 days',u);
  return jsonb_build_object('token',token,'url','bettertogether://invite/'||token);
 when 'join_team' then
  if t is not null then raise exception '你已在一个小队中'; end if;
  select i.team_id into t from public.invites i join public.teams team on team.id=i.team_id where i.token_hash=encode(extensions.digest(p_args->>'token','sha256'),'hex') and i.expires_at>now() and i.revoked_at is null and team.dissolved_at is null;
  if t is null then raise exception '邀请已失效，请让队友重新邀请'; end if;
  perform 1 from public.teams where id=t for update;
  if (select count(*) from public.team_members where team_id=t and left_at is null)>=5 then raise exception '小队已满 5 人'; end if;
  insert into public.team_members(team_id,user_id) values(t,u); return jsonb_build_object('id',t);
 when 'leave_team' then
  if exists(select 1 from public.teams where id=t and owner_id=u) then raise exception '队长请先解散小队'; end if;
  update public.team_members set left_at=now() where team_id=t and user_id=u and left_at is null;
  return jsonb_build_object('left',true);
 when 'manage_team' then
  if not exists(select 1 from public.teams where id=t and owner_id=u and dissolved_at is null) then raise exception '仅队长可进行此操作'; end if;
  if p_args->>'operation'='rename' then update public.teams set name=trim(p_args->>'name') where id=t;
  elsif p_args->>'operation'='remove' then
   if (p_args->>'member_id')::uuid=u then raise exception '请使用解散小队'; end if;
   update public.team_members set left_at=now() where team_id=t and user_id=(p_args->>'member_id')::uuid and left_at is null;
  elsif p_args->>'operation'='dissolve' then
   update public.teams set dissolved_at=now() where id=t;
   update public.team_members set left_at=now() where team_id=t and left_at is null;
   update public.invites set revoked_at=now() where team_id=t;
  else raise exception '不支持的小队操作'; end if;
  return jsonb_build_object('updated',true);
 when 'save_plan' then
  planid:=nullif(p_args->>'id','')::uuid;
  if planid is not null then
   select * into p from public.plans where id=planid and user_id=u for update;
   if not found then raise exception '计划不存在'; end if;
  end if;
  if planid is null then
   insert into public.plans(user_id,title,category,goal,weekdays,start_time,deadline,visibility,status)
   values(u,trim(p_args->>'title'),p_args->>'category',coalesce(p_args->>'goal',''),array(select jsonb_array_elements_text(p_args->'weekdays')::int),
    (p_args->>'start_time')::time,(p_args->>'deadline')::time,coalesce(p_args->>'visibility','team'),coalesce(p_args->>'status','active')) returning id into planid;
  else
   if char_length(trim(p_args->>'title')) not between 1 and 100 or (p_args->>'start_time')::time>(p_args->>'deadline')::time or not (p_args->>'category'=any(array['study','food','exercise','custom'])) then raise exception '请核对计划名称、品类与时段'; end if;
   update public.plans set next_config=p_args-'id',effective_on=date_trunc('week',today::timestamp)::date+7 where id=planid;
  end if;
  return jsonb_build_object('id',planid,'effective_on',case when p_args ? 'id' then date_trunc('week',today::timestamp)::date+7 else today end);
 when 'pause_week' then
  update public.profiles set paused_week=case when (p_args->>'paused')::boolean then date_trunc('week',today::timestamp)::date else null end where id=u;
  return jsonb_build_object('updated',true);
 when 'submit_checkin' then
  if char_length(coalesce(p_args->>'idempotency_key','')) not between 8 and 128 then raise exception '提交标识不完整，请重试'; end if;
  select s.result into result from public.submissions s where s.user_id=u and s.idempotency_key=p_args->>'idempotency_key'; if found then return result; end if;
  ids:=array(select jsonb_array_elements_text(p_args->'media_ids')::uuid);
  if cardinality(ids) not between 1 and 9 or cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception '每次请选择 1–9 张照片'; end if;
  perform 1 from public.media where id=any(ids) for update;
  if (select count(*) from public.media where id=any(ids) and user_id=u and checkin_id is null and deleted_at is null and local_date=today and team_id is not distinct from t)<>cardinality(ids) then raise exception '部分照片不可用，请重新选择今天的照片'; end if;
  if (select count(distinct batch_id) from public.media where id=any(ids))<>1 then raise exception '请在同一次打卡中选择照片'; end if;
  select batch_id into bid from public.media where id=ids[1];
  planid:=nullif(p_args->>'plan_id','')::uuid;
  if planid is not null then select * into p from public.plans where id=planid and user_id=u and status='active'; if not found then raise exception '请选择进行中的计划'; end if; end if;
  target:=coalesce(nullif(p_args->>'target_date','')::date,today); oldid:=nullif(p_args->>'redo_of','')::uuid;
  if oldid is not null then
   select * into c from public.checkins where id=oldid and user_id=u and status='redo_required' for update;
   if not found or now()>=c.redo_deadline then raise exception '重打时间已结束'; end if;
   target:=c.local_date; planid:=c.plan_id;
  elsif target<>today then
   if target<>today-1 or local_now::time>='12:00'::time or char_length(trim(coalesce(p_args->>'makeup_reason','')))=0 then raise exception '请在次日 12:00 前补前一天，并写明原因'; end if;
   if (select count(*) from public.checkins where user_id=u and is_makeup and date_trunc('month',created_at at time zone tz)=date_trunc('month',local_now))>=2 then raise exception '本月的 2 张补卡已用完'; end if;
   if planid is null then raise exception '补卡时请选择原计划'; end if;
  end if;
  if planid is not null then select * into p from public.plans where id=planid; end if;
  insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,status,is_makeup,is_late,summary,makeup_reason,timer_seconds,visibility,team_size,redo_of)
  values(u,t,planid,bid,target,tz,case when target<today and oldid is null then 'makeup' else 'stamped' end,target<today and oldid is null,
   oldid is null and target=today and planid is not null and coalesce(app.plan_on_day(planid,target)->>'schedule_kind','weekdays')<>'weekly_target' and local_now::time>p.deadline,
   coalesce(p_args->>'note',''),p_args->>'makeup_reason',nullif(p_args->>'timer_seconds','')::integer,coalesce(p.visibility,'private'),
   greatest(1,(select count(*) from public.team_members where team_id=t and left_at is null)),oldid) returning id into mid;
  update public.media set checkin_id=mid,plan_id=planid where id=any(ids);
  update public.checkins set classification_pending=planid is null where id=mid;
  if oldid is not null then update public.checkins set status='stamped',redo_deadline=null where id=oldid; end if;
  update public.overdue_feed set status='resolved' where user_id=u and plan_id=planid and local_date=target;
  insert into public.jobs(kind,payload) values('ai',jsonb_build_object('checkin_id',mid,'version',1));
  perform app.notify(u,'stamp','已盖章','纪要正在整理，稍后会补齐。',mid,'stamp:'||mid);
  result:=jsonb_build_object('checkin_ids',jsonb_build_array(mid));
  insert into public.submissions(user_id,idempotency_key,result) values(u,p_args->>'idempotency_key',result); return result;
 when 'edit_memo' then
  select * into c from public.checkins where id=(p_args->>'checkin_id')::uuid and user_id=u for update; if not found then raise exception '记录不存在'; end if;
  if not app.validate_fields(coalesce(p_args->'fields','[]'),coalesce((select category from public.plans where id=c.plan_id),'all')) then raise exception '请核对字段来源，饮食热量需为估算区间'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_args->'fields','[]')) f where f->>'source'<>'manual' and not exists(select 1 from jsonb_array_elements(c.fields) original where original=f)) then raise exception '修改后的字段请标注为手填'; end if;
  update public.checkins set summary=left(coalesce(p_args->>'summary',''),4000),fields=coalesce(p_args->'fields','[]'),user_edited=true,version=version+1,memo_status='ready' where id=c.id;
  if c.classification_pending then insert into public.jobs(kind,payload) values('ai',jsonb_build_object('checkin_id',c.id,'version',c.version+1)); end if;
  return jsonb_build_object('updated',true);
 when 'reclassify' then
  select * into c from public.checkins where id=(p_args->>'checkin_id')::uuid and user_id=u for update;
  if not found or now()>c.created_at+interval '24 hours' or c.status not in ('stamped','makeup') then raise exception '请在盖章后 24 小时内修改分类'; end if;
  select * into p from public.plans where id=(p_args->>'plan_id')::uuid and user_id=u;
  if not found then raise exception '计划不存在'; end if;
  if c.user_edited and not app.validate_fields(c.fields,p.category) then raise exception '这份手填纪要与目标计划不符。请先把热量改为估算区间或清空该字段，再修改分类'; end if;
  insert into public.tag_changes(checkin_id,old_plan_id,new_plan_id) values(c.id,c.plan_id,p.id);
  update public.checkins set plan_id=p.id,visibility=p.visibility,version=version+1,classification_pending=false,
   is_late=case when is_makeup or redo_of is not null then is_late else (created_at at time zone timezone)::time>coalesce((app.plan_on_day(p.id,c.local_date)->>'deadline')::time,p.deadline) end,
   memo_status=case when user_edited then memo_status else 'pending' end where id=c.id;
  update public.media set plan_id=p.id where checkin_id=c.id;
  insert into public.jobs(kind,payload) values('ai',jsonb_build_object('checkin_id',c.id,'version',c.version+1));
  update public.overdue_feed set status='resolved' where plan_id=p.id and local_date=c.local_date;
  if c.plan_id is not null and c.plan_id<>p.id and not exists(select 1 from public.checkins where plan_id=c.plan_id and local_date=c.local_date and status in ('stamped','makeup')) then
   update public.overdue_feed set status='open' where plan_id=c.plan_id and local_date=c.local_date;
   select * into p from public.plans where id=c.plan_id;
   if c.team_id is not null and p.visibility='team' and c.local_date=today and app.plan_due(p.id,today)
    and now()>=least((today+time '23:30') at time zone tz,((today+p.deadline) at time zone tz)+interval '30 minutes') then
    insert into public.overdue_feed(team_id,user_id,plan_id,local_date,deadline_at) values(c.team_id,u,p.id,today,(today+p.deadline) at time zone tz) on conflict(plan_id,local_date) do update set status='open';
   end if;
  end if;
  return jsonb_build_object('updated',true);
 when 'interact' then
  select * into c from public.checkins where id=(p_args->>'checkin_id')::uuid for update;
  if not found or not app.can_checkin(c.id,u) or c.team_id is null or c.status not in ('stamped','makeup') then raise exception '这条记录暂不能互动'; end if;
  if p_args->>'kind'='challenge' then
   if c.user_id=u then raise exception '不能质疑自己的记录'; end if;
   if char_length(trim(coalesce(p_args->>'content','')))=0 then raise exception '请写一句具体理由'; end if;
   if exists(select 1 from public.interactions where checkin_id=c.id and user_id=u and kind='challenge') then return jsonb_build_object('updated',true); end if;
   if (select count(*) from public.interactions where user_id=u and kind='challenge' and local_date=today)>=2 then raise exception '今天已经提出 2 次质疑'; end if;
  elsif p_args->>'kind'='like' and exists(select 1 from public.interactions where checkin_id=c.id and user_id=u and kind='like') then
   delete from public.interactions where checkin_id=c.id and user_id=u and kind='like'; return jsonb_build_object('liked',false);
  end if;
  insert into public.interactions(checkin_id,user_id,kind,content,local_date) values(c.id,u,p_args->>'kind',coalesce(p_args->>'content',''),today) returning id into mid;
  if p_args->>'kind'='challenge' then
   select count(*) into cnt from public.interactions i where i.checkin_id=c.id and i.kind='challenge' and app.team_for(i.user_id)=c.team_id;
   select count(*) into n from public.team_members where team_id=c.team_id and left_at is null;
   update public.checkins set team_size=n where id=c.id;
   if cnt>n/2 then
    update public.checkins set frozen_plan_streak=app.streak(c.user_id,c.plan_id),frozen_user_streak=app.streak(c.user_id),status='redo_required',redo_deadline=(((now() at time zone c.timezone)::date+1)::timestamp+interval '12 hours') at time zone c.timezone where id=c.id;
    perform app.notify(c.user_id,'challenge','请重新打卡','队友质疑已过半，连续记录已冻结。请在次日 12:00 前补充证据。',c.id,'redo:'||c.id);
   end if;
  end if;
  if c.user_id<>u then perform app.notify(c.user_id,case when p_args->>'kind'='challenge' then 'challenge' else 'interaction' end,'队友有新回应',case when p_args->>'kind'='like' then '队友给你的记录点了赞。' else left(p_args->>'content',200) end,c.id,'interaction:'||mid); end if;
  return jsonb_build_object('updated',true);
 when 'poke' then
  select * into o from public.overdue_feed where id=(p_args->>'overdue_id')::uuid for update;
  if not found or o.user_id=u or o.team_id is distinct from t or app.team_for(o.user_id) is distinct from t or o.status<>'open' then raise exception '这条提醒暂不能戳'; end if;
  insert into public.pokes(overdue_id,user_id) values(o.id,u) on conflict do nothing;
  if found then
   select count(*) into cnt from public.pokes where overdue_id=o.id;
   mid:=app.notify(o.user_id,'poke','队友戳了你一下',cnt||' 位队友在等你，方便时补上今天的计划。',o.id,'poke:'||o.id,interval '60 seconds');
   update public.notifications set body=cnt||' 位队友在等你，方便时补上今天的计划。',read=false where dedupe_key='poke:'||o.id;
   update public.push_outbox set payload=jsonb_set(payload,'{body}',to_jsonb(cnt||' 位队友在等你，方便时补上今天的计划。')) where notification_id=(select id from public.notifications where dedupe_key='poke:'||o.id) and status='queued';
  end if; return jsonb_build_object('updated',true);
 when 'mark_notifications' then
  update public.notifications set read=true where user_id=u and (coalesce((p_args->>'all')::boolean,false) or id in (select jsonb_array_elements_text(p_args->'ids')::uuid)); return jsonb_build_object('updated',true);
 when 'register_device' then
  insert into public.devices(user_id,platform,provider,token) values(u,p_args->>'platform',p_args->>'provider',p_args->>'token')
  on conflict on constraint devices_token_key do update set user_id=u,platform=excluded.platform,provider=excluded.provider,updated_at=now(); return jsonb_build_object('updated',true);
 when 'unregister_device' then
  delete from public.devices d where d.user_id=u and d.token=p_args->>'token'; return jsonb_build_object('updated',true);
 when 'share_report' then
  select * into r from public.reports where id=(p_args->>'report_id')::uuid and (user_id=u or (kind='team' and team_id=t)); if not found then raise exception '周报不存在'; end if;
  if p_args->>'method' not in ('feed','image') or (p_args->>'method'='image' and r.kind<>'personal') then raise exception '分享图片仅包含本人周报'; end if;
  update public.reports set shared=shared or p_args->>'method'='feed',image_shared=image_shared or p_args->>'method'='image',shared_at=now() where id=r.id; return jsonb_build_object('updated',true);
 when 'refresh_report' then
  select * into r from public.reports where id=(p_args->>'report_id')::uuid and user_id=u for update;
  if not found or r.refreshed or now()>r.generated_at+interval '24 hours' then raise exception '周报仅能在生成后 24 小时内刷新一次'; end if;
  perform app.build_report(u,r.week_start,r.timezone); update public.reports set refreshed=true where id=r.id;
  insert into public.jobs(kind,payload) values('report',jsonb_build_object('report_id',r.id)); return jsonb_build_object('updated',true);
 when 'accept_suggestion' then
  select * into r from public.reports where id=(p_args->>'report_id')::uuid and user_id=u;
  if not found or not(r.suggestion ? 'plan_id') then raise exception '本周没有需要调整的计划'; end if;
  if r.week_start<>date_trunc('week',today::timestamp)::date and today<>r.week_start+7 then raise exception '这份建议已过期，请参考最新周报'; end if;
  update public.plans set next_config=coalesce(next_config,to_jsonb(public.plans))||coalesce(r.suggestion->'changes','{}'),effective_on=greatest(r.week_start+7,today) where id=(r.suggestion->>'plan_id')::uuid and user_id=u;
  return jsonb_build_object('updated',true);
 when 'delete_photo' then
  select * into rec from public.media where id=(p_args->>'photo_id')::uuid and user_id=u for update;
  if not found then raise exception '照片不存在'; end if;
  if rec.deleted_at is null then
   update public.media set deleted_at=now(),cleanup_status='pending' where id=rec.id;
   insert into public.jobs(kind,payload) values('cleanup',jsonb_build_object('media_id',rec.id,'user_id',u,'bucket','evidence','paths',to_jsonb(array_remove(array[rec.path,rec.analysis_path],null))));
  end if;
  return jsonb_build_object('deleted',true,'cleanup_status',case when rec.deleted_at is null then 'pending' else rec.cleanup_status end);
 else raise exception '不支持的操作';
 end case;
end $$;
alter function public.app_action(text,jsonb) rename to app_action_before_flexible;
revoke all on function public.app_action_before_flexible(text,jsonb) from public,anon,authenticated;
create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); p public.plans; cfg jsonb; plan_key uuid; today date; kind text; result jsonb; cid uuid; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.profiles where public.profiles.id=u and deletion_requested_at is not null) then raise exception '账号删除尚未完成，请在设置中再次删除以继续清理'; end if;
 today:=(now() at time zone app.timezone_for(u))::date;
 if p_action='save_plan' then
  plan_key:=nullif(p_args->>'id','')::uuid;
  if plan_key is not null then
   select * into p from public.plans where public.plans.id=plan_key and user_id=u for update;
   if not found then raise exception '计划不存在'; end if;
   if coalesce((p_args->>'schema_version')::int,1)<2 and (p.schedule_kind<>'weekdays' or coalesce(p.next_config->>'schedule_kind','weekdays')<>'weekdays') then raise exception '请升级 App 后编辑这种计划频率'; end if;
  end if;
  kind:=coalesce(p_args->>'schedule_kind','weekdays');
  if kind not in ('weekdays','weekly_target','interval') or coalesce(p_args->>'category','') not in ('study','exercise','food','sleep','water','mindfulness','custom') then raise exception '请选择有效分类与频率'; end if;
  if kind='weekly_target' and coalesce((p_args->>'weekly_target_days')::int,0) not between 1 and 7 then raise exception '每周目标需为 1 至 7 天'; end if;
  if kind='interval' and coalesce((p_args->>'interval_days')::int,0) not between 1 and 365 then raise exception '周期需为 1 至 365 天'; end if;
  cfg:=p_args||jsonb_build_object('schedule_kind',kind,'anchor_date',coalesce(nullif(p_args->>'anchor_date','')::date,p.anchor_date,today),'weekdays',case when kind='weekdays' then p_args->'weekdays' else '[1,2,3,4,5,6,7]'::jsonb end);
  if plan_key is null then
   if (cfg->>'anchor_date')::date<today then raise exception '新计划的开始日期不能早于今天'; end if;
   insert into public.plans(user_id,title,category,goal,weekdays,start_time,deadline,visibility,status,schedule_kind,weekly_target_days,interval_days,anchor_date)
   values(u,trim(cfg->>'title'),cfg->>'category',coalesce(cfg->>'goal',''),array(select jsonb_array_elements_text(cfg->'weekdays')::int),(cfg->>'start_time')::time,(cfg->>'deadline')::time,coalesce(cfg->>'visibility','team'),coalesce(cfg->>'status','active'),kind,(cfg->>'weekly_target_days')::int,(cfg->>'interval_days')::int,(cfg->>'anchor_date')::date) returning public.plans.id into plan_key;
  else
   update public.plans set next_config=cfg-'id',effective_on=date_trunc('week',today::timestamp)::date+7 where public.plans.id=plan_key;
  end if;
  return jsonb_build_object('id',plan_key,'effective_on',case when p.id is null then (cfg->>'anchor_date')::date else date_trunc('week',today::timestamp)::date+7 end);
 end if;
 result:=public.app_action_before_flexible(p_action,p_args);
 if p_action in ('submit_checkin','reclassify') then
  for cid in select jsonb_array_elements_text(coalesce(result->'checkin_ids',jsonb_build_array(p_args->>'checkin_id')))::uuid loop
   if cid is null then continue; end if;
   update public.checkins c set is_late=false where c.id=cid and app.plan_on_day(c.plan_id,c.local_date)->>'schedule_kind'='weekly_target';
  end loop;
 end if;
 return result;
end $$;
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;

create or replace function public.run_schedule(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare stage_value text; w date; progress jsonb; rr record; p record; u record; tm record; d date; local_now timestamp; tz text; due timestamptz; rid uuid; nid uuid; cnt int:=0; begin
 perform pg_advisory_xact_lock(hashtextextended('better-together-scheduler',0));
 update public.checkins set status='incomplete' where status='redo_required' and redo_deadline<=p_now;
 for p in select x.*,app.timezone_for(x.user_id) tz,app.team_for(x.user_id) team from public.plans x loop
  local_now:=p_now at time zone p.tz; d:=local_now::date;
  if p.effective_on<=d and p.next_config is not null then
   update public.plans set title=coalesce(p.next_config->>'title',title),goal=coalesce(p.next_config->>'goal',goal),category=coalesce(p.next_config->>'category',category),
   weekdays=case when p.next_config ? 'weekdays' then array(select jsonb_array_elements_text(p.next_config->'weekdays')::int) else weekdays end,
   start_time=coalesce((p.next_config->>'start_time')::time,start_time),deadline=coalesce((p.next_config->>'deadline')::time,deadline),visibility=coalesce(p.next_config->>'visibility',visibility),status=coalesce(p.next_config->>'status',status),schedule_kind=coalesce(p.next_config->>'schedule_kind',schedule_kind),weekly_target_days=(p.next_config->>'weekly_target_days')::int,interval_days=(p.next_config->>'interval_days')::int,anchor_date=coalesce((p.next_config->>'anchor_date')::date,anchor_date),next_config=null,effective_on=null where id=p.id;
   select x.*,p.tz tz,p.team team into p from public.plans x where x.id=p.id;
  end if;
  -- Weekly goals settle once per week, not as daily missed records.
  w:=date_trunc('week',d::timestamp)::date-7;
  if local_now>=w+7+time '00:30' and p.team is not null and p.visibility='team'
   and app.plan_on_day(p.id,w+6)->>'schedule_kind'='weekly_target' then
   progress:=app.plan_week(p.id,w);
   if (progress->>'expected')::int>0 then
    if (progress->>'completed')::int<(progress->>'expected')::int then
     insert into public.overdue_feed(team_id,user_id,plan_id,local_date,deadline_at,schedule_kind)
     values(p.team,p.user_id,p.id,w+6,(w+7+time '00:30') at time zone p.tz,'weekly_target')
     on conflict(plan_id,local_date) do update set status='open';
    else update public.overdue_feed set status='resolved' where plan_id=p.id and local_date=w+6 and schedule_kind='weekly_target'; end if;
   end if;
  end if;
  if p.status<>'active'  or (p.created_at at time zone p.tz)::date>d or not app.plan_due(p.id,d) or exists(select 1 from public.profiles where id=p.user_id and paused_week=date_trunc('week',d::timestamp)::date) then continue; end if;
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
 -- Finalize the same report after the last Sunday makeup window closes.
 for rr in select * from public.reports where stage='phase' and p_now >= (week_start+7+time '12:05') at time zone timezone loop
  if rr.kind='personal' then
   perform app.build_report(rr.user_id,rr.week_start,rr.timezone);
   progress:=app.week_counts(rr.user_id,rr.week_start,true);
   update public.reports set stage='final',finalized_at=p_now,generated_at=p_now,
    public_snapshot=case when shared then public_snapshot||jsonb_build_object('metrics',progress,'stage','final','generated_at',p_now,'summary','本周留下了 '||(progress->>'checkins')||' 次公开给小队的记录。') else public_snapshot end where id=rr.id;
   insert into public.jobs(kind,payload) values('report',jsonb_build_object('report_id',rr.id));
  else update public.reports set metrics=app.team_week_counts(rr.team_id,rr.week_start),stage='final',finalized_at=p_now,generated_at=p_now where id=rr.id; end if;
 end loop;
 return jsonb_build_object('overdue_created',cnt);
end $$;

create or replace function public.apply_ai_result(p_checkin_id uuid,p_result jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.checkins; a jsonb; g jsonb; pid uuid; newid uuid; groupids uuid[]:='{}'; memo_fields jsonb; category text; target record; assigned uuid[]; grouped uuid[]; defer_fields boolean:=false; defer_summary boolean:=false; direct_batch boolean:=false; partial_result boolean:=false; private_result boolean:=false; begin
 select * into c from public.checkins where id=p_checkin_id for update;
 if not found then return jsonb_build_object('applied',false,'reason','missing'); end if;
 if c.version<>coalesce((p_result->>'version')::int,0) or (c.user_edited and not c.classification_pending) or (c.memo_status<>'pending' and not c.classification_pending) then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 if not exists(select 1 from public.jobs where id=(p_result->>'job_id')::uuid and lease_token=(p_result->>'lease_token')::uuid and status='processing' and lease_until>now() and payload->>'checkin_id'=c.id::text and kind='ai') then return jsonb_build_object('applied',false,'reason','lease_changed'); end if;
 direct_batch:=exists(select 1 from public.media m join public.media_analysis ma on ma.media_id=m.id where m.checkin_id=c.id and m.deleted_at is null);
 partial_result:=direct_batch and coalesce((p_result->>'partial')::boolean,false);
 private_result:=direct_batch and c.plan_id is null and (coalesce((p_result->>'privacy_required')::boolean,false) or exists(
  select 1 from public.media m join public.media_analysis ma on ma.media_id=m.id cross join lateral jsonb_array_elements(ma.result->'assignments') cached_assignment
  join public.plans p on p.id::text=cached_assignment->>'plan_id' where m.checkin_id=c.id and m.deleted_at is null and p.visibility='private'
 ));
 if jsonb_typeof(p_result->'assignments') is distinct from 'array' or jsonb_typeof(p_result->'groups') is distinct from 'array' then raise exception 'AI assignments schema mismatch'; end if;
 assigned:=array(select (value->>'photo_id')::uuid from jsonb_array_elements(p_result->'assignments'));
 if cardinality(assigned)<>(select count(distinct x) from unnest(assigned) x) or cardinality(assigned)<>(select count(*) from public.media where checkin_id=c.id and deleted_at is null)
 or exists(select 1 from unnest(assigned) x where not exists(select 1 from public.media where id=x and checkin_id=c.id and deleted_at is null)) then raise exception 'AI assignments must cover every photo exactly once'; end if;
 for a in select value from jsonb_array_elements(p_result->'assignments') loop
  pid:=nullif(a->>'plan_id','')::uuid;
  if c.plan_id is not null and pid is distinct from c.plan_id then raise exception 'AI cannot override selected plan'; end if;
  if partial_result and c.plan_id is null and pid is not null then raise exception 'Partial recognition must remain ALL'; end if;
  if pid is not null and not exists(select 1 from public.plans where id=pid and user_id=c.user_id) then raise exception 'AI plan not owned by member'; end if;
  if (a->>'confidence')::numeric not between 0 and 1 then raise exception 'AI confidence outside range'; end if;
  update public.media set plan_id=pid,confidence=(a->>'confidence')::numeric where id=(a->>'photo_id')::uuid and checkin_id=c.id;
 end loop;
 if direct_batch and jsonb_array_length(p_result->'groups')<>1 then raise exception 'Direct recognition must produce one aggregate group'; end if;
 grouped:=array(select jsonb_array_elements_text(value->'photo_ids')::uuid from jsonb_array_elements(p_result->'groups'));
 if cardinality(grouped)<>cardinality(assigned) or cardinality(grouped)<>(select count(distinct x) from unnest(grouped) x) or not grouped @> assigned then raise exception 'AI groups must cover every photo exactly once'; end if;
 if (select count(*) from jsonb_array_elements(p_result->'groups'))<>(select count(distinct coalesce(value->>'plan_id','ALL')) from jsonb_array_elements(p_result->'groups')) then raise exception 'AI groups must be unique by plan'; end if;
 defer_fields:=c.user_edited and jsonb_array_length(c.fields)>0 and jsonb_array_length(p_result->'groups')>1;
 -- A later pass must not mistake a partial AI summary for the original note.
 defer_summary:=c.plan_id is null and char_length(trim(c.summary))>0 and (not direct_batch or c.memo_status='pending' or c.user_edited);
 for g in select value from jsonb_array_elements(p_result->'groups') loop
  pid:=nullif(g->>'plan_id','')::uuid;
  if exists(select 1 from jsonb_array_elements_text(g->'photo_ids') photo where not exists(select 1 from public.media where id=photo::uuid and checkin_id=c.id and plan_id is not distinct from pid)) then raise exception 'AI group conflicts with assignment'; end if;
 end loop;
 for target in select distinct m.plan_id from public.media m where m.checkin_id=c.id and m.deleted_at is null loop
  pid:=target.plan_id;
  if cardinality(groupids)=0 then newid:=c.id;
  else
   insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,status,is_makeup,is_late,summary,fields,memo_status,visibility,team_size,created_at)
   values(c.user_id,c.team_id,pid,c.batch_id,c.local_date,c.timezone,c.status,c.is_makeup,c.is_late,'','[]','pending','private',c.team_size,c.created_at) returning id into newid;
  end if;
  update public.media set checkin_id=newid where checkin_id=c.id and plan_id is not distinct from pid;
  select value into g from jsonb_array_elements(p_result->'groups') where nullif(value->>'plan_id','')::uuid is not distinct from pid;
  category:=coalesce((select p.category from public.plans p where id=pid),'all');
  if c.user_edited and not app.validate_fields(c.fields,category) then defer_fields:=true; end if;
  memo_fields:=case when c.user_edited and defer_fields then '[]'::jsonb when c.user_edited then c.fields else g->'fields' end;
  if not app.validate_fields(memo_fields,category) then raise exception 'AI fields violate source/range rules'; end if;
  update public.checkins set plan_id=pid,visibility=case when private_result then 'private' else coalesce((select visibility from public.plans where id=pid),'private') end,
   is_late=case when c.redo_of is null and not c.is_makeup and pid is not null and coalesce(app.plan_on_day(pid,c.local_date)->>'schedule_kind','weekdays')<>'weekly_target' then (c.created_at at time zone c.timezone)::time>(select deadline from public.plans where id=pid) else c.is_late end,
   summary=case when c.user_edited and not defer_summary then c.summary else left(coalesce(g->>'summary',''),4000) end,fields=memo_fields,user_edited=c.user_edited,memo_status='ready',classification_pending=partial_result or pid is null,version=version+case when partial_result then 0 else 1 end where id=newid;
  update public.overdue_feed set status='resolved' where plan_id=pid and local_date=c.local_date and user_id=c.user_id;
  groupids:=array_append(groupids,newid);
 end loop;
 if defer_fields or defer_summary then
  insert into public.batch_field_drafts(checkin_id,user_id,batch_id,fields,summary)
  values(c.id,c.user_id,c.batch_id,case when defer_fields then c.fields else '[]'::jsonb end,case when defer_summary then c.summary else '' end)
  on conflict(checkin_id) do update set fields=excluded.fields,summary=excluded.summary where not direct_batch;
 end if;
 return jsonb_build_object('applied',true,'checkin_ids',to_jsonb(groupids));
end $$;

revoke all on function app.plan_due(uuid,date),app.plan_week(uuid,date,boolean),app.plan_progress(uuid,date) from public,anon,authenticated;

create or replace function app.build_report(p_user uuid,p_week date,p_tz text) returns uuid
language plpgsql security definer set search_path='' as $$
declare rid uuid; t uuid:=app.team_for(p_user); m jsonb:=app.week_counts(p_user,p_week); award jsonb:=app.week_award(p_user,p_week); hs jsonb; suggestion jsonb:='{}'; item jsonb; p public.plans; new_days int[]; begin
 select coalesce(jsonb_agg(s),'[]') into hs from (select id,summary,local_date from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') and redo_of is null order by created_at desc limit 3) s;
 m:=m||jsonb_build_object('streak',app.streak(p_user),'award',award);
 for item in select value from jsonb_array_elements(m->'plans') loop
  select * into p from public.plans where id=(item->>'id')::uuid and status='active';
  if found and p.schedule_kind='weekdays' and (item->>'expected')::int=cardinality(p.weekdays) and (item->>'completed')::int<cardinality(p.weekdays) and cardinality(p.weekdays)>1 then
   new_days:=p.weekdays[1:greatest(1,(item->>'completed')::int)];
   suggestion:=jsonb_build_object('plan_id',p.id,'text','本周「'||p.title||'」完成 '||(item->>'completed')||'/'||(item->>'expected')||' 天。可先把下周调整为 '||cardinality(new_days)||' 天，之后随时编辑。','changes',jsonb_build_object('weekdays',to_jsonb(new_days)),'basis',jsonb_build_object('completed',item->'completed','expected',item->'expected'));
   exit;
  end if;
 end loop;
 insert into public.reports(user_id,team_id,week_start,timezone,kind,title,summary,metrics,highlights,suggestion)
 values(p_user,t,p_week,p_tz,'personal',coalesce(award->>'title',''),'这周完成了 '||(m->>'checkins')||' 次打卡。一起看看留下的记录。',m,hs,suggestion)
 on conflict(user_id,week_start) where kind='personal' do update set title=excluded.title,summary=excluded.summary,metrics=excluded.metrics,highlights=excluded.highlights,suggestion=excluded.suggestion returning id into rid;
 return rid;
end $$;

create function app.weekly_streak(p_user uuid,p_day date,p_public boolean default false) returns int language plpgsql stable security definer set search_path='' as $$
declare w date:=date_trunc('week',p_day::timestamp)::date; first_day date; n int:=0; p record; v jsonb; has_target boolean; incomplete boolean; begin
 select min(r.effective_on) into first_day from public.plan_revisions r join public.plans owned on owned.id=r.plan_id where owned.user_id=p_user;
 while w+6>=first_day loop
  has_target:=false; incomplete:=false;
  for p in select id from public.plans where user_id=p_user loop
   v:=app.plan_week(p.id,w,p_public);
   if v->>'schedule_kind'='weekly_target' and (v->>'expected')::int>0 then
    has_target:=true; incomplete:=incomplete or (v->>'completed')::int<(v->>'expected')::int;
   end if;
  end loop;
  if has_target and not incomplete then n:=n+1;
  elsif has_target and w<>date_trunc('week',p_day::timestamp)::date then exit; end if;
  w:=w-7;
 end loop; return n;
end $$;
create function app.team_weekly_streak(p_team uuid,p_day date) returns int language plpgsql stable security definer set search_path='' as $$
declare w date:=date_trunc('week',p_day::timestamp)::date; first_day date; n int:=0; p record; v jsonb; has_target boolean; incomplete boolean; begin
 select (created_at at time zone timezone)::date into first_day from public.teams where id=p_team;
 while w+6>=first_day loop
  has_target:=false; incomplete:=false;
  for p in select pl.id from public.plans pl join public.team_members m on m.user_id=pl.user_id where m.team_id=p_team and m.left_at is null loop
   v:=app.plan_week(p.id,w,true);
   if v->>'schedule_kind'='weekly_target' and (v->>'expected')::int>0 then has_target:=true; incomplete:=incomplete or (v->>'completed')::int<(v->>'expected')::int; end if;
  end loop;
  if has_target and not incomplete then n:=n+1;
  elsif has_target and w<>date_trunc('week',p_day::timestamp)::date then exit; end if;
  w:=w-7;
 end loop; return n;
end $$;
revoke all on function app.weekly_streak(uuid,date,boolean),app.team_weekly_streak(uuid,date) from public,anon,authenticated;
