-- The new client confirms a batch only after the user has reviewed and edited
-- the AI groups. Keep the legacy single-record action for older clients.
alter function public.app_action(text,jsonb) rename to app_action_before_batch_checkin;

create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();
 t uuid;
 tz text;
 local_now timestamp;
 today date;
 token text;
 result jsonb;
 raw_group jsonb;
 raw_groups jsonb:=coalesce(p_args->'groups','[]'::jsonb);
 group_ids uuid[];
 all_ids uuid[]:='{}'::uuid[];
 current_batch uuid;
 batch_id uuid;
 new_checkin_id uuid;
 group_plan uuid;
 plan public.plans;
 oldid uuid;
 old_checkin public.checkins;
 target date;
 is_makeup boolean;
 summary text;
 fields jsonb;
 plan_selection text;
 user_edited boolean;
 output_ids jsonb:='[]'::jsonb;
 group_count integer:=0;
 complete boolean;
 team_size integer;
begin
 if p_action<>'submit_checkin_batch' then
  return public.app_action_before_batch_checkin(p_action,p_args);
 end if;
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 if not exists(select 1 from public.profiles where id=u and deletion_requested_at is null) then
  raise exception using errcode='42501',message='账号正在删除';
 end if;
 if jsonb_typeof(raw_groups) is distinct from 'array'
  or jsonb_array_length(raw_groups)=0
  or jsonb_array_length(raw_groups)>9 then
  raise exception '请至少保留一条打卡记录';
 end if;
 token:=coalesce(p_args->>'idempotency_key','');
 if char_length(token) not between 8 and 128 then
  raise exception '提交标识不完整，请重试';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 select s.result into result from public.submissions s
  where s.user_id=u and s.idempotency_key=token;
 if found then return result; end if;

 t:=app.team_for(u);
 tz:=app.timezone_for(u);
 local_now:=now() at time zone tz;
 today:=local_now::date;
 target:=coalesce(nullif(p_args->>'target_date','')::date,today);
 oldid:=nullif(p_args->>'redo_of','')::uuid;
 is_makeup:=char_length(trim(coalesce(p_args->>'makeup_reason','')))>0;
 team_size:=greatest(1,(select count(*) from public.team_members where team_id=t and left_at is null));

 if oldid is not null then
  if jsonb_array_length(raw_groups)<>1 then raise exception '重打只能提交一条记录'; end if;
  select * into old_checkin from public.checkins
   where id=oldid and user_id=u and status='redo_required' for update;
  if not found or old_checkin.redo_deadline is null or now()>=old_checkin.redo_deadline then
   raise exception '重打时间已结束';
  end if;
  target:=old_checkin.local_date;
 elsif target<>today then
  if target<>today-1 or local_now::time>='12:00'::time or not is_makeup then
   raise exception '请在次日 12:00 前补前一天，并写明原因';
  end if;
  if (select count(distinct batch_id) from public.checkins where user_id=u and is_makeup
    and date_trunc('month',created_at at time zone tz)=date_trunc('month',local_now))>=2 then
   raise exception '本月的 2 张补卡已用完';
  end if;
end if;

 for raw_group in select value from jsonb_array_elements(raw_groups) loop
  if jsonb_typeof(raw_group) is distinct from 'object'
   or jsonb_typeof(raw_group->'media_ids') is distinct from 'array' then
   raise exception '打卡分组格式不正确';
  end if;
  group_ids:=array(select value::uuid from jsonb_array_elements_text(raw_group->'media_ids'));
  if cardinality(group_ids) not between 1 and 9 then
   raise exception '每组需包含 1 至 9 张照片';
  end if;
  if cardinality(group_ids)<>(select count(distinct value) from unnest(group_ids) value) then
   raise exception '一条记录不能重复使用同一张照片';
  end if;
  if cardinality(all_ids)>0 and exists(select 1 from unnest(group_ids) id where id=any(all_ids)) then
   raise exception '一张照片只能归入一条记录';
  end if;
  all_ids:=all_ids||group_ids;
  if cardinality(all_ids)>9 then raise exception '每次最多提交 9 张照片'; end if;
  perform 1 from public.media where id=any(group_ids) for update;
  if (select count(*) from public.media m where m.id=any(group_ids) and m.user_id=u
    and m.checkin_id is null and m.deleted_at is null and m.local_date=today
    and m.team_id is not distinct from t
    and coalesce(m.metadata->'byok'->>'status','pending')<>'rejected')<>cardinality(group_ids) then
   raise exception '部分照片不可用，请重新选择今天的照片';
  end if;
  select m.batch_id into current_batch from public.media m where m.id=group_ids[1];
  if current_batch is null or (batch_id is not null and current_batch is distinct from batch_id)
   or exists(select 1 from public.media m where m.id=any(group_ids) and m.batch_id is distinct from current_batch) then
   raise exception '请在同一次打卡中选择照片';
  end if;
  batch_id:=current_batch;

  group_plan:=nullif(raw_group->>'plan_id','')::uuid;
  plan_selection:=coalesce(nullif(raw_group->>'plan_selection',''),case when group_plan is null then 'all' else 'ai' end);
  if plan_selection not in ('all','manual','ai') then
   raise exception '计划归属标记无效';
  end if;
  if group_plan is null and plan_selection='ai' then plan_selection:='all'; end if;
  if group_plan is not null and plan_selection='all' then raise exception '计划归属标记无效'; end if;
  user_edited:=coalesce((raw_group->>'user_edited')::boolean,false) or char_length(trim(coalesce(p_args->>'note','')))>0;
  plan:=null;
  if group_plan is not null then
   select * into plan from public.plans where id=group_plan and user_id=u and status='active';
   if not found then raise exception '请选择进行中的计划'; end if;
   if oldid is not null and group_plan is distinct from old_checkin.plan_id then
    raise exception '重打必须保留原计划';
   end if;
  elsif oldid is not null and old_checkin.plan_id is not null then
   raise exception '重打必须保留原计划';
  end if;

  -- Recognition values are re-used from the validated per-photo archive.
  -- The grouping request cannot invent screenshot/device provenance or attach
  -- a different photo's fields to this record.
  if plan_selection='ai' and exists(
    select 1 from public.media m where m.id=any(group_ids) and (
      m.metadata->'byok'->>'status' is distinct from 'ready'
      or coalesce((m.metadata->'byok'->>'confidence')::numeric,0)<0.8
      or nullif(m.metadata->'byok'->>'plan_id','')::uuid is distinct from group_plan
    )
  ) then raise exception '计划建议已变化，请重新确认分组'; end if;
  select coalesce(jsonb_agg(f.value),'[]'::jsonb) into fields
    from public.media m cross join lateral jsonb_array_elements(coalesce(m.metadata->'byok'->'fields','[]'::jsonb)) f
    where m.id=any(group_ids);
  if not app.validate_fields(fields,coalesce(plan.category,'all')) then
   raise exception '请核对字段来源，饮食热量需为估算区间';
  end if;
  select bool_and(coalesce(m.metadata->'byok'->>'status'='ready',false)) into complete
    from public.media m where m.id=any(group_ids);
  if coalesce((raw_group->>'user_edited')::boolean,false) then
   summary:=left(trim(coalesce(raw_group->>'summary','')),4000);
  else
   select left(coalesce(string_agg(nullif(trim(m.metadata->'byok'->>'summary'),''),E'\n' order by array_position(group_ids,m.id)),''),4000)
    into summary from public.media m where m.id=any(group_ids);
  end if;
  if char_length(trim(coalesce(p_args->>'note','')))>0 then
   summary:=left(concat_ws(E'\n',nullif(summary,''),trim(p_args->>'note')),4000);
  end if;
  group_count:=group_count+1;
  insert into public.checkins(
    user_id,team_id,plan_id,batch_id,local_date,timezone,status,is_makeup,is_late,
    summary,fields,memo_status,classification_pending,visibility,team_size,redo_of,
    makeup_reason,plan_selection,user_edited)
  values(
    u,t,group_plan,batch_id,target,tz,
    case when target<today and oldid is null then 'makeup' else 'stamped' end,
    target<today and oldid is null,
    oldid is null and target=today and group_plan is not null
      and local_now::time>plan.deadline,
    summary,fields,
    case when complete or user_edited then 'ready' else 'pending' end,
    false,coalesce(plan.visibility,'private'),team_size,oldid,
    case when target<today and oldid is null then nullif(trim(coalesce(p_args->>'makeup_reason','')),'') end,
    plan_selection,user_edited)
  returning id into new_checkin_id;
  update public.media set checkin_id=new_checkin_id,plan_id=group_plan where id=any(group_ids);
  output_ids:=output_ids||jsonb_build_array(new_checkin_id);
  if group_plan is not null then
   update public.overdue_feed set status='resolved'
    where user_id=u and plan_id=group_plan and local_date=target;
  end if;
 end loop;
 if group_count=0 or batch_id is null then raise exception '请至少保留一条包含照片的记录'; end if;
 if oldid is not null then
  update public.checkins set status='stamped',redo_deadline=null where id=oldid;
 end if;
 result:=jsonb_build_object('checkin_ids',output_ids,'batch_id',batch_id);
 insert into public.submissions(user_id,idempotency_key,result) values(u,token,result);
 return result;
end $$;

revoke all on function public.app_action_before_batch_checkin(text,jsonb) from public,anon,authenticated;
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;

-- A split makeup batch consumes one allowance, independent of record count.
create or replace function public.bootstrap_v2() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; zone text; d date; profile jsonb; team jsonb;
begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 t:=app.team_for(u); zone:=app.timezone_for(u); d:=(now() at time zone zone)::date;
 select to_jsonb(p)||jsonb_build_object('avatar_url',app.avatar_ref(p.id,p.avatar_url),'timezone',zone,
  'paused_week',coalesce(p.paused_week=date_trunc('week',d::timestamp)::date,false),
  'weekly_streak',app.weekly_streak(u,d),'streak',app.streak(u),
  'makeup_remaining',greatest(0,2-(select count(distinct batch_id) from public.checkins where user_id=u and is_makeup
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
