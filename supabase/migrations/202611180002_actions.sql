create function app.notify(p_user uuid,p_kind text,p_title text,p_body text,p_target uuid,p_key text,p_delay interval default interval '0') returns uuid
language plpgsql security definer set search_path='' as $$
declare n uuid; prefs jsonb; begin
 insert into public.notifications(user_id,kind,title,body,target_id,dedupe_key)
 values(p_user,p_kind,p_title,p_body,p_target,p_key) on conflict(dedupe_key) do nothing returning id into n;
 select notification_preferences into prefs from public.profiles where id=p_user;
 if n is not null and coalesce((prefs->>'all')::boolean,true) and coalesce((prefs->>p_kind)::boolean,true) then
 insert into public.push_outbox(user_id,notification_id,payload,available_at) values(p_user,n,jsonb_build_object('title',p_title,'body',p_body,'kind',p_kind,'target_id',p_target),now()+p_delay);
 end if; return n;
end $$;

create function app.streak(p_user uuid,p_plan uuid default null) returns int language plpgsql stable security definer set search_path='' as $$
declare d date := (now() at time zone app.timezone_for(p_user))::date; total int:=0; found_day boolean:=false; c record; begin
 for c in select distinct local_date,status,is_late from public.checkins where user_id=p_user and (p_plan is null or plan_id=p_plan) order by local_date desc loop
  if c.local_date > d then continue; end if;
  if not found_day and c.local_date=d-1 then d:=d-1; end if;
  if c.local_date<d then
   if p_plan is not null and not exists(select 1 from public.plans where id=p_plan and extract(isodow from d)::int=any(weekdays)) then d:=d-1; end if;
  end if;
  if c.local_date<d then exit; end if;
  if c.local_date=d then
   found_day:=true;
   if c.status in ('makeup','redo_required') then d:=d-1;
   elsif c.status='stamped' and not c.is_late then total:=total+1; d:=d-1;
   elsif d=(now() at time zone app.timezone_for(p_user))::date then d:=d-1;
   else exit; end if;
  end if;
 end loop; return total;
end $$;

create function app.validate_fields(p_fields jsonb,p_category text) returns boolean language plpgsql immutable set search_path='' as $$
declare f jsonb; begin
 if jsonb_typeof(p_fields) is distinct from 'array' then return false; end if;
 for f in select value from jsonb_array_elements(p_fields) loop
  if not (f ? 'key' and f ? 'label' and f ? 'value' and f ? 'source') or (f->>'source') not in ('ai','screenshot','timer','health','manual') then return false; end if;
  if p_category='exercise' and f->>'key' in ('duration','duration_minutes','duration_seconds','calories','distance','distance_km') and f->>'source'='ai' then return false; end if;
  if p_category in ('food','all') and f->>'key' in ('calories','calorie_range') then
   if jsonb_typeof(f->'value')<>'object' or not (f->'value' ? 'min' and f->'value' ? 'max') or coalesce((f->'value'->>'estimated')::boolean,false)=false
    or (f->'value'->>'min')::numeric<0 or (f->'value'->>'max')::numeric<=(f->'value'->>'min')::numeric then return false; end if;
  end if;
 end loop; return true;
exception when others then return false;
end $$;

create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb
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
  if coalesce(p_args->>'status','active')='active' and (select count(*) from public.plans where user_id=u and (status='active' or coalesce(next_config->>'status','')='active') and id<>coalesce(planid,'00000000-0000-0000-0000-000000000000'))>=3 then raise exception '最多同时进行 3 个计划'; end if;
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
  if planid is not null and oldid is null and exists(select 1 from public.checkins where user_id=u and plan_id=planid and local_date=target and status in ('stamped','makeup')) then raise exception '这个计划今天已经盖章'; end if;
  if planid is not null then select * into p from public.plans where id=planid; end if;
  insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,status,is_makeup,is_late,summary,makeup_reason,timer_seconds,visibility,team_size,redo_of)
  values(u,t,planid,bid,target,tz,case when target<today and oldid is null then 'makeup' else 'stamped' end,target<today and oldid is null,
   oldid is null and target=today and planid is not null and local_now::time>p.deadline,
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
   if c.team_id is not null and p.visibility='team' and c.local_date=today and extract(isodow from today)::int=any(p.weekdays)
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
  update public.notifications set read=true where user_id=u and id in (select jsonb_array_elements_text(p_args->'ids')::uuid); return jsonb_build_object('updated',true);
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
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;
