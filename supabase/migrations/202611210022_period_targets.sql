-- Fixed-length completion cycles are additive. Legacy weekly_target plans keep
-- their calendar-week behavior and their historical revisions.
alter table public.plans drop constraint plans_schedule_kind_check;
alter table public.plans add constraint plans_schedule_kind_check
 check(schedule_kind in ('weekdays','weekly_target','period_target','interval'));
alter table public.plans add column period_days integer not null default 7
 check(period_days between 1 and 365),
 add column period_target_days integer not null default 3
 check(period_target_days between 1 and 365);
alter table public.plans drop constraint valid_schedule;
alter table public.plans add constraint valid_schedule check(
 (schedule_kind<>'weekly_target' or weekly_target_days is not null)
 and (schedule_kind<>'period_target' or period_target_days<=period_days)
 and (schedule_kind<>'interval' or interval_days is not null)
);

create or replace function app.record_plan_revision() returns trigger
language plpgsql security definer set search_path='' as $$
declare effective date; cfg jsonb; days int[];
begin
 cfg:=new.next_config;
 if cfg is not null then
  if coalesce(cfg->>'schedule_kind','weekdays') not in ('weekdays','weekly_target','period_target','interval')
   or (cfg->>'schedule_kind'='weekly_target' and coalesce((cfg->>'weekly_target_days')::int,0) not between 1 and 7)
   or (cfg->>'schedule_kind'='period_target' and
    (coalesce((cfg->>'period_days')::int,0) not between 1 and 365 or
     coalesce((cfg->>'period_target_days')::int,0) not between 1 and coalesce((cfg->>'period_days')::int,0)))
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
 insert into public.plan_revisions(plan_id,effective_on,config)
 values(new.id,effective,to_jsonb(new)-array['next_config','effective_on'])
 on conflict(plan_id,effective_on) do update set config=excluded.config;
 return new;
end $$;

-- run_schedule applies the existing next_config columns. This trigger copies
-- the new cycle values during that same atomic activation update.
create function app.apply_period_config() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.next_config is not null and new.next_config is null and old.effective_on is not null then
  new.period_days:=coalesce((old.next_config->>'period_days')::int,old.period_days);
  new.period_target_days:=coalesce((old.next_config->>'period_target_days')::int,old.period_target_days);
 end if;
 return new;
end $$;
create trigger apply_period_config before update of next_config on public.plans
 for each row execute function app.apply_period_config();
revoke all on function app.apply_period_config() from public,anon,authenticated;

create or replace function app.plan_due(p_plan uuid,p_day date) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=app.plan_on_day(p_plan,p_day); anchor date;
begin
 if cfg is null or cfg->>'status'<>'active' then return false; end if;
 anchor:=coalesce((cfg->>'anchor_date')::date,(cfg->>'created_at')::timestamptz::date);
 if p_day<anchor then return false; end if;
 if coalesce(cfg->>'schedule_kind','weekdays') in ('weekly_target','period_target') then return false; end if;
 if cfg->>'schedule_kind'='interval' then return (p_day-anchor)%((cfg->>'interval_days')::int)=0; end if;
 return cfg->'weekdays' @> to_jsonb(extract(isodow from p_day)::int);
end $$;

create or replace function app.period_progress(p_plan uuid,p_day date,p_public boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=app.plan_on_day(p_plan,p_day); u uuid; period int; target int; anchor date;
 cycle_start date; cycle_end date; window_start date; window_end date; done int; streak int:=0; i int;
begin
 select user_id into u from public.plans where id=p_plan;
 if cfg is null or cfg->>'schedule_kind'<>'period_target' then
  return jsonb_build_object('period_days',coalesce((cfg->>'period_days')::int,7),
   'period_target_days',coalesce((cfg->>'period_target_days')::int,3),'period_target',0,
   'period_completed',0,'period_extra_days',0,'period_streak',0,'period_start',null,'period_end',null);
 end if;
 period:=coalesce((cfg->>'period_days')::int,7);
 target:=coalesce((cfg->>'period_target_days')::int,3);
 anchor:=coalesce((cfg->>'anchor_date')::date,(cfg->>'created_at')::timestamptz::date);
 if p_day<anchor then
  return jsonb_build_object('period_days',period,'period_target_days',target,'period_target',target,
   'period_completed',0,'period_extra_days',0,'period_streak',0,'period_start',anchor,'period_end',anchor+period-1);
 end if;
 cycle_start:=anchor+(((p_day-anchor)/period)*period);
 cycle_end:=cycle_start+period-1;
 select count(distinct c.local_date)::int into done from public.checkins c
 where c.plan_id=p_plan and c.local_date between cycle_start and cycle_end
  and c.status in ('stamped','makeup') and c.redo_of is null
  and (not p_public or (c.visibility='team' and c.team_id=app.team_for(u)
   and app.in_sharing_period(c.team_id,u,c.created_at)));
 for i in 0..3650 loop
  window_start:=cycle_start-i*period;
  window_end:=window_start+period-1;
  if window_start<anchor then exit; end if;
  select count(distinct c.local_date)::int into done from public.checkins c
  where c.plan_id=p_plan and c.local_date between window_start and window_end
   and c.status in ('stamped','makeup') and c.redo_of is null
   and (not p_public or (c.visibility='team' and c.team_id=app.team_for(u)
    and app.in_sharing_period(c.team_id,u,c.created_at)));
  if done>=target then streak:=streak+1;
  elsif window_end<p_day then exit;
  end if;
 end loop;
 select count(distinct c.local_date)::int into done from public.checkins c
 where c.plan_id=p_plan and c.local_date between cycle_start and cycle_end
  and c.status in ('stamped','makeup') and c.redo_of is null
  and (not p_public or (c.visibility='team' and c.team_id=app.team_for(u)
   and app.in_sharing_period(c.team_id,u,c.created_at)));
 return jsonb_build_object('period_days',period,'period_target_days',target,'period_target',target,
  'period_completed',done,'period_extra_days',greatest(0,done-target),'period_streak',streak,
  'period_start',cycle_start,'period_end',cycle_end);
end $$;

create or replace function app.plan_week(p_plan uuid,p_day date,p_public boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w date:=date_trunc('week',p_day::timestamp)::date; d date; cfg jsonb; u uuid;
 eligible int:=0; completed int:=0; makeups int:=0; target int:=0; k text:='weekdays';
begin
 select user_id into u from public.plans where id=p_plan;
 cfg:=app.plan_on_day(p_plan,p_day); k:=coalesce(cfg->>'schedule_kind','weekdays');
 if k='period_target' then
  return jsonb_build_object('expected',0,'completed',0,'extra_days',0,'makeup',0,'schedule_kind',k);
 end if;
 if exists(select 1 from public.paused_weeks where user_id=u and week_start=w) then
  return jsonb_build_object('expected',0,'completed',0,'extra_days',0,'makeup',0,'schedule_kind',k);
 end if;
 for d in select generate_series(w::timestamp,(w+6)::timestamp,interval '1 day')::date loop
  cfg:=app.plan_on_day(p_plan,d);
  if cfg is null or cfg->>'status'<>'active' or d<coalesce((cfg->>'anchor_date')::date,w)
   or (p_public and cfg->>'visibility'<>'team') then continue; end if;
  if p_public and not exists(select 1 from public.team_members tm join public.teams t on t.id=tm.team_id
   where tm.user_id=u and tm.left_at is null and (tm.joined_at at time zone t.timezone)::date<=d) then continue; end if;
  k:=coalesce(cfg->>'schedule_kind','weekdays');
  if k<>'weekly_target' and not app.plan_due(p_plan,d) then continue; end if;
  eligible:=eligible+1; target:=coalesce((cfg->>'weekly_target_days')::int,0);
  if exists(select 1 from public.checkins c where c.plan_id=p_plan and c.local_date=d
   and c.status in ('stamped','makeup') and (not p_public or (c.visibility='team'
    and c.team_id=app.team_for(u) and app.in_sharing_period(c.team_id,u,c.created_at)))) then completed:=completed+1; end if;
  if exists(select 1 from public.checkins c where c.plan_id=p_plan and c.local_date=d and c.status='makeup'
   and (not p_public or (c.visibility='team' and c.team_id=app.team_for(u)
    and app.in_sharing_period(c.team_id,u,c.created_at)))) then makeups:=makeups+1; end if;
 end loop;
 target:=case when k='weekly_target' then least(target,eligible) else eligible end;
 return jsonb_build_object('expected',target,'completed',completed,'extra_days',greatest(0,completed-target),
  'makeup',makeups,'schedule_kind',k);
end $$;

create or replace function app.plan_progress(p_plan uuid,p_day date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare counts jsonb:=app.plan_week(p_plan,p_day); w date:=date_trunc('week',p_day::timestamp)::date;
 earliest date; n int:=0; v jsonb;
begin
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
 return jsonb_build_object('weekly_target',counts->'expected','weekly_completed',counts->'completed',
  'extra_days',counts->'extra_days','weekly_streak',n)||app.period_progress(p_plan,p_day);
end $$;

-- Keep daily plan readers and AI candidate selection aware of non-daily goals.
create or replace function public.ai_plan_candidates(p_user uuid,p_day date,p_category text default null,p_selected uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(row),'[]') from (
  select p.id,p.title,p.category,p.goal,p.visibility from public.plans p
  where p.user_id=p_user and (
   (p_selected is not null and p.id=p_selected) or
   (p_selected is null and p.status='active' and
    (app.plan_due(p.id,p_day) or (app.plan_on_day(p.id,p_day)->>'schedule_kind' in ('weekly_target','period_target')
     and coalesce((app.plan_on_day(p.id,p_day)->>'anchor_date')::date,p.anchor_date)<=p_day))
    and (p_category is null or p.category=p_category)))
  order by p.created_at,p.id limit 25
 ) row
$$;

create or replace function public.bootstrap_v2() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; zone text; d date; profile jsonb; team jsonb;
begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 t:=app.team_for(u); zone:=app.timezone_for(u); d:=(now() at time zone zone)::date;
 select to_jsonb(p)||jsonb_build_object('avatar_url',app.avatar_ref(p.id,p.avatar_url),'timezone',zone,
  'paused_week',coalesce(p.paused_week=date_trunc('week',d::timestamp)::date,false),
  'weekly_streak',app.weekly_streak(u,d),'streak',app.streak(u),
  'makeup_remaining',greatest(0,2-(select count(*) from public.checkins where user_id=u and is_makeup
   and date_trunc('month',created_at at time zone zone)=date_trunc('month',now() at time zone zone))))
 into profile from public.profiles p where id=u;
 if t is not null then
  select to_jsonb(x)||jsonb_build_object('weekly_streak',app.team_weekly_streak(t,d),'streak',app.team_streak(t),
   'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,
    'avatar_url',app.avatar_ref(p.id,p.avatar_url),'status',case app.day_outcome(p.id,d,null,true)
     when 1 then 'completed' when 2 then 'makeup' else case when exists(select 1 from public.checkins c
      where c.user_id=p.id and c.local_date=d and c.visibility='team' and app.can_checkin(c.id,u))
      then 'in_progress' else 'not_started' end end)) from public.profiles p
     join public.team_members m on m.user_id=p.id where m.team_id=t and m.left_at is null),'[]'))
  into team from public.teams x where id=t;
 end if;
 return jsonb_build_object('profile',profile,'team',team,
  'plans',coalesce((select jsonb_agg(to_jsonb(p)||coalesce(app.plan_on_day(p.id,d),'{}')||app.plan_progress(p.id,d)
   ||jsonb_build_object('streak',app.streak(u,p.id)) order by p.created_at) from public.plans p
   where p.user_id=u and p.status='active' and (app.plan_due(p.id,d) or
    (coalesce(app.plan_on_day(p.id,d)->>'schedule_kind','weekdays') in ('weekly_target','period_target')
     and coalesce((app.plan_on_day(p.id,d)->>'anchor_date')::date,d)<=d))),'[]'),
  'checkins',coalesce((select jsonb_agg(app.checkin_json(id)) from
   (select id from public.checkins where user_id=u and local_date>=date_trunc('week',d::timestamp)::date
    order by created_at desc,id desc limit 100) c),'[]'),
  'notifications',(public.read_page('{"collection":"notifications"}')->'items'),
  'unread_count',(select count(*) from public.notifications where user_id=u and not read),
  'overdue','[]'::jsonb,'reports','[]'::jsonb);
end $$;

-- All target-style plans have no per-day late cutoff.
create function app.clear_target_late_flag() returns trigger language plpgsql set search_path='' as $$
begin
 if new.plan_id is not null and app.plan_on_day(new.plan_id,new.local_date)->>'schedule_kind' in ('weekly_target','period_target') then
  new.is_late:=false;
 end if;
 return new;
end $$;
create trigger checkin_target_schedule_late before insert or update of plan_id,is_late on public.checkins
 for each row execute function app.clear_target_late_flag();
revoke all on function app.clear_target_late_flag() from public,anon,authenticated;

-- Create or update a schedule through the authenticated RPC. Edits remain
-- pending until Monday, while a changed fixed-cycle schedule starts there.
alter function public.app_action(text,jsonb) rename to app_action_before_period_target;
create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); p public.plans; plan_key uuid; kind text; cfg jsonb; today date;
 effective date; requested_anchor date; old_days int[]; requested_days int[]; schedule_changed boolean;
begin
 if p_action<>'save_plan' then return public.app_action_before_period_target(p_action,p_args); end if;
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.profiles where id=u and deletion_requested_at is not null) then
  raise exception '账号删除尚未完成，请在设置中再次删除以继续清理'; end if;
 today:=(now() at time zone app.timezone_for(u))::date;
 effective:=date_trunc('week',today::timestamp)::date+7;
 plan_key:=nullif(p_args->>'id','')::uuid;
 if plan_key is not null then
  select * into p from public.plans where id=plan_key and user_id=u for update;
  if not found then raise exception '计划不存在'; end if;
  if coalesce((p_args->>'schema_version')::int,1)<2 and
   (p.schedule_kind<>'weekdays' or coalesce(p.next_config->>'schedule_kind','weekdays')<>'weekdays') then
   raise exception '请升级 App 后编辑这种计划频率'; end if;
 end if;
 kind:=coalesce(p_args->>'schedule_kind','weekdays');
 if kind not in ('weekdays','weekly_target','period_target','interval')
  or coalesce(p_args->>'category','') not in ('study','exercise','food','sleep','water','mindfulness','custom') then
  raise exception '请选择有效分类与频率'; end if;
 if kind='weekly_target' and coalesce((p_args->>'weekly_target_days')::int,0) not between 1 and 7 then
  raise exception '每周目标需为 1 至 7 天'; end if;
 if kind='period_target' and (coalesce((p_args->>'period_days')::int,0) not between 1 and 365
  or coalesce((p_args->>'period_target_days')::int,0) not between 1 and coalesce((p_args->>'period_days')::int,0)) then
  raise exception '周期长度需为 1 至 365 天，完成天数不能超过周期长度'; end if;
 if kind='interval' and coalesce((p_args->>'interval_days')::int,0) not between 1 and 365 then
  raise exception '周期需为 1 至 365 天'; end if;
 requested_days:=array(select jsonb_array_elements_text(p_args->'weekdays')::int);
 if kind='weekdays' and (cardinality(requested_days) not between 1 and 7
  or not requested_days<@array[1,2,3,4,5,6,7]
  or cardinality(requested_days)<>(select count(distinct d) from unnest(requested_days) d)) then
  raise exception '请至少选择一个有效星期'; end if;
 requested_anchor:=coalesce(nullif(p_args->>'anchor_date','')::date,p.anchor_date,today);
 if plan_key is null then
  if requested_anchor<today then raise exception '新计划的开始日期不能早于今天'; end if;
 else
  old_days:=p.weekdays;
  schedule_changed:=kind is distinct from p.schedule_kind
   or (kind='weekdays' and requested_days is distinct from old_days)
   or (kind='weekly_target' and (p_args->>'weekly_target_days')::int is distinct from p.weekly_target_days)
   or (kind='period_target' and ((p_args->>'period_days')::int is distinct from p.period_days
     or (p_args->>'period_target_days')::int is distinct from p.period_target_days))
   or (kind='interval' and (p_args->>'interval_days')::int is distinct from p.interval_days);
  if kind='period_target' and schedule_changed and requested_anchor=p.anchor_date then
   requested_anchor:=effective;
  end if;
  if kind='period_target' and requested_anchor<effective and schedule_changed then
   raise exception '新周期开始日期不能早于生效日期';
  end if;
 end if;
 cfg:=p_args||jsonb_build_object('schedule_kind',kind,'anchor_date',requested_anchor,
  'weekdays',case when kind='weekdays' then p_args->'weekdays' else '[1,2,3,4,5,6,7]'::jsonb end);
 if plan_key is null then
  insert into public.plans(user_id,title,category,goal,weekdays,start_time,deadline,visibility,status,
   schedule_kind,weekly_target_days,period_days,period_target_days,interval_days,anchor_date)
  values(u,trim(cfg->>'title'),cfg->>'category',coalesce(cfg->>'goal',''),
   array(select jsonb_array_elements_text(cfg->'weekdays')::int),(cfg->>'start_time')::time,
   (cfg->>'deadline')::time,coalesce(cfg->>'visibility','team'),coalesce(cfg->>'status','active'),kind,
   nullif(cfg->>'weekly_target_days','')::int,coalesce(nullif(cfg->>'period_days','')::int,7),
   coalesce(nullif(cfg->>'period_target_days','')::int,3),nullif(cfg->>'interval_days','')::int,requested_anchor)
  returning id into plan_key;
 else
  update public.plans set next_config=cfg-'id',effective_on=effective where id=plan_key;
 end if;
 return jsonb_build_object('id',plan_key,'effective_on',case when p.id is null then requested_anchor else effective end);
end $$;
revoke all on function public.app_action_before_period_target(text,jsonb) from public,anon,authenticated;
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;

revoke all on function app.period_progress(uuid,date,boolean),app.plan_due(uuid,date),
 app.plan_week(uuid,date,boolean),app.plan_progress(uuid,date),app.record_plan_revision() from public,anon,authenticated;
revoke all on function public.ai_plan_candidates(uuid,date,text,uuid) from public,anon,authenticated;
grant execute on function public.ai_plan_candidates(uuid,date,text,uuid) to service_role;
