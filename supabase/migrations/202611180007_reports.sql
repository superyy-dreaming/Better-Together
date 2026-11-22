create function app.week_counts(p_user uuid,p_week date,p_public boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare expected int:=0; completed int:=0; makeups int:=0; total int; d date; p record; cfg jsonb; plans jsonb:='[]'; pe int; pc int; pm int; begin
 for p in select id,title from public.plans where user_id=p_user loop
  pe:=0; pc:=0; pm:=0;
  for d in select generate_series(p_week::timestamp,(p_week+6)::timestamp,interval '1 day')::date loop
   cfg:=app.plan_on_day(p.id,d);
   if cfg is null or cfg->>'status'<>'active' or (p_public and cfg->>'visibility'<>'team') or not cfg->'weekdays' @> to_jsonb(extract(isodow from d)::int)
    or exists(select 1 from public.paused_weeks where user_id=p_user and week_start=p_week) then continue; end if;
   if p_public and not exists(select 1 from public.team_members tm join public.teams t on t.id=tm.team_id where tm.user_id=p_user and tm.left_at is null and (tm.joined_at at time zone t.timezone)::date<=d) then continue; end if;
   pe:=pe+1;
   if exists(select 1 from public.checkins where plan_id=p.id and local_date=d and status in ('stamped','makeup') and (not p_public or (visibility='team' and team_id=app.team_for(p_user) and app.in_sharing_period(team_id,p_user,created_at)))) then pc:=pc+1; end if;
   if exists(select 1 from public.checkins where plan_id=p.id and local_date=d and is_makeup and status='makeup' and (not p_public or (visibility='team' and team_id=app.team_for(p_user) and app.in_sharing_period(team_id,p_user,created_at)))) then pm:=pm+1; end if;
  end loop;
  expected:=expected+pe; completed:=completed+pc; makeups:=makeups+pm;
  if pe>0 then plans:=plans||jsonb_build_array(jsonb_build_object('id',p.id,'title',p.title,'expected',pe,'completed',pc,'makeup',pm,'completion_rate',pc::numeric/pe)); end if;
 end loop;
 select count(*) into total from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') and redo_of is null and (not p_public or (visibility='team' and team_id=app.team_for(p_user) and app.in_sharing_period(team_id,p_user,created_at)));
 return jsonb_build_object('checkins',total,'completed',completed,'expected',expected,'makeup',makeups,'completion_rate',case when expected=0 then 0 else completed::numeric/expected end,'plans',plans,
  'unclassified',(select count(*) from public.checkins where user_id=p_user and plan_id is null and local_date between p_week and p_week+6 and status in ('stamped','makeup') and (not p_public or (visibility='team' and team_id=app.team_for(p_user) and app.in_sharing_period(team_id,p_user,created_at)))));
end $$;

create function app.team_week_counts(p_team uuid,p_week date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m record; counts jsonb; expected int:=0; completed int:=0; total int:=0; members int:=0; begin
 for m in select user_id from public.team_members where team_id=p_team and left_at is null loop
  counts:=app.week_counts(m.user_id,p_week,true); expected:=expected+(counts->>'expected')::int; completed:=completed+(counts->>'completed')::int; total:=total+(counts->>'checkins')::int; members:=members+1;
 end loop;
 return jsonb_build_object('expected',expected,'completed',completed,'checkins',total,'members',members,'completion_rate',case when expected=0 then 0 else completed::numeric/expected end);
end $$;
create function app.award_counts(p_user uuid,p_week date,p_team uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb:=app.week_counts(p_user,p_week,true); previous jsonb:=app.week_counts(p_user,p_week-7,true); begin
 return m||jsonb_build_object('comments',(select count(*) from public.interactions i join public.checkins c on c.id=i.checkin_id where i.user_id=p_user and i.kind='comment' and c.user_id<>p_user and c.team_id=p_team and c.visibility='team' and app.team_for(c.user_id)=p_team and i.local_date between p_week and p_week+6),
  'received',(select count(*) from public.interactions i join public.checkins c on c.id=i.checkin_id where c.user_id=p_user and i.user_id<>p_user and i.kind in ('like','comment') and c.visibility='team' and c.team_id=p_team and app.team_for(i.user_id)=p_team and i.local_date between p_week and p_week+6),
  'pokes',(select count(*) from public.pokes k join public.overdue_feed o on o.id=k.overdue_id where o.user_id=p_user and o.team_id=p_team and o.local_date between p_week and p_week+6 and app.team_for(k.user_id)=p_team),
  'improvement',case when (previous->>'expected')::int>0 then (m->>'completion_rate')::numeric-(previous->>'completion_rate')::numeric else 0 end);
end $$;
create function app.week_award(p_user uuid,p_week date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t uuid:=app.team_for(p_user); mine jsonb; other jsonb; key text; title text:=''; m record; winner boolean; value numeric; begin
 if t is null then return '{}'; end if;
 mine:=app.award_counts(p_user,p_week,t);
 -- One main title: progress, full attendance, pokes, received, comments, checkins.
 foreach key in array array['improvement','attendance','pokes','received','comments','checkins'] loop
  if key='attendance' then
   if (mine->>'expected')::int>0 and (mine->>'completed')::int=(mine->>'expected')::int and (mine->>'makeup')::int=0 then return jsonb_build_object('key',key,'count',(mine->>'completed')::int,'title','最稳的一个，零漏打'); end if;
   continue;
  end if;
  value:=(mine->>key)::numeric; if coalesce(value,0)<=0 then continue; end if; winner:=true;
  for m in select user_id from public.team_members where team_id=t and left_at is null and user_id<>p_user loop
   other:=app.award_counts(m.user_id,p_week,t);
   if (other->>key)::numeric>value or ((other->>key)::numeric=value and (other->>'checkins')::int>(mine->>'checkins')::int) then winner:=false; exit; end if;
  end loop;
  if winner then
   title:=case key when 'improvement' then '进步最大的人' when 'pokes' then '全队都在等你，你被戳了 '||value::int||' 次' when 'received' then '本周同伴盯着你打了 '||value::int||' 次卡' when 'comments' then '你是本周的点评家' else '你是这周打卡最积极的人' end;
   return jsonb_build_object('key',key,'count',value,'title',title);
  end if;
 end loop;
 return '{}';
end $$;
create or replace function app.build_report(p_user uuid,p_week date,p_tz text) returns uuid
language plpgsql security definer set search_path='' as $$
declare rid uuid; t uuid:=app.team_for(p_user); m jsonb:=app.week_counts(p_user,p_week); award jsonb:=app.week_award(p_user,p_week); hs jsonb; suggestion jsonb:='{}'; item jsonb; p public.plans; new_days int[]; begin
 select coalesce(jsonb_agg(s),'[]') into hs from (select id,summary,local_date from public.checkins where user_id=p_user and local_date between p_week and p_week+6 and status in ('stamped','makeup') and redo_of is null order by created_at desc limit 3) s;
 m:=m||jsonb_build_object('streak',app.streak(p_user),'award',award);
 for item in select value from jsonb_array_elements(m->'plans') loop
  select * into p from public.plans where id=(item->>'id')::uuid and status='active';
  if found and (item->>'expected')::int=cardinality(p.weekdays) and (item->>'completed')::int<cardinality(p.weekdays) and cardinality(p.weekdays)>1 then
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
-- Suggestions cite actual completed/expected counts; they never invent reasons.
alter table public.reports add column public_snapshot jsonb not null default '{}', add column evidence jsonb not null default '[]';
drop policy reports_read on public.reports;
create policy reports_read on public.reports for select to authenticated using(user_id=auth.uid() or (kind='team' and app.can_team(team_id,auth.uid())));
create table public.report_interactions (
 id uuid primary key default gen_random_uuid(), report_id uuid not null references public.reports(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade, kind text not null check(kind in ('like','comment')),
 content text not null default '', created_at timestamptz not null default now(), check(kind='like' or char_length(trim(content)) between 1 and 2000)
);
create unique index one_report_like on public.report_interactions(report_id,user_id) where kind='like';
alter table public.report_interactions enable row level security;
grant all on public.report_interactions to service_role;
grant select on public.report_interactions to authenticated;
create function app.can_report(p_id uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reports r where r.id=p_id and (r.user_id=p_user or (r.team_id=app.team_for(p_user) and (r.kind='team' or (r.shared and app.team_for(r.user_id)=r.team_id)))))
$$;
create policy report_interactions_read on public.report_interactions for select to authenticated using(app.can_report(report_id,auth.uid()));
alter function public.app_action(text,jsonb) rename to app_action_core;
revoke all on function public.app_action_core(text,jsonb) from public,anon,authenticated;
create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); r public.reports; result jsonb; m jsonb; new_id uuid; teammate record; original public.checkins; target public.checkins; pending_fields jsonb; pending_summary text; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.profiles where id=u and deletion_requested_at is not null) then raise exception '账号删除尚未完成，请在设置中再次删除以继续清理'; end if;
 if p_action='assign_batch_fields' then
  select * into original from public.checkins where id=(p_args->>'checkin_id')::uuid and user_id=u for update;
  select fields,summary into pending_fields,pending_summary from public.batch_field_drafts where checkin_id=original.id and user_id=u for update;
  if pending_fields is null or (jsonb_array_length(pending_fields)=0 and char_length(pending_summary)=0) then raise exception '没有待归属的手填内容'; end if;
  select * into target from public.checkins where id=(p_args->>'target_checkin_id')::uuid and user_id=u and batch_id=original.batch_id for update;
  if not found then raise exception '请选择本次打卡中的计划'; end if;
  if not app.validate_fields(pending_fields,coalesce((select category from public.plans where id=target.plan_id),'all')) then raise exception '手填字段不适用于这个计划，请选择相符的计划'; end if;
  update public.checkins set fields=coalesce((select jsonb_agg(value) from jsonb_array_elements(target.fields) f where not exists(select 1 from jsonb_array_elements(pending_fields) x where x->>'key'=f->>'key')),'[]')||pending_fields,
   summary=case when char_length(pending_summary)>0 then pending_summary else target.summary end,user_edited=true,version=version+1 where id=target.id;
  delete from public.batch_field_drafts where checkin_id=original.id;
  return jsonb_build_object('updated',true);
 end if;
 if p_action='interact_report' then
  select * into r from public.reports where id=(p_args->>'report_id')::uuid for update;
  if not found or not app.can_report(r.id,u) or r.team_id is distinct from app.team_for(u) or (r.kind='personal' and not r.shared) then raise exception '这份周报暂不能互动'; end if;
  if p_args->>'kind'='like' and exists(select 1 from public.report_interactions where report_id=r.id and user_id=u and kind='like') then delete from public.report_interactions where report_id=r.id and user_id=u and kind='like'; return jsonb_build_object('liked',false); end if;
  insert into public.report_interactions(report_id,user_id,kind,content) values(r.id,u,p_args->>'kind',coalesce(p_args->>'content','')) returning id into new_id;
  if r.user_id<>u then perform app.notify(r.user_id,'interaction','周报有新回应',case when p_args->>'kind'='like' then '队友给你的周报点了赞。' else left(p_args->>'content',200) end,r.id,'report-interaction:'||new_id); end if;
  return jsonb_build_object('updated',true);
 end if;
 result:=public.app_action_core(p_action,p_args);
 if p_action in ('share_report','refresh_report') then
  select * into r from public.reports where id=(p_args->>'report_id')::uuid and user_id=u;
  if found and r.shared then
   m:=app.week_counts(u,r.week_start,true);
   update public.reports set public_snapshot=jsonb_build_object('id',r.id,'user_id',u,'team_id',r.team_id,'week_start',r.week_start,'kind','personal','shared',true,'refreshed',r.refreshed,'title',r.title,'summary','本周留下了 '||(m->>'checkins')||' 次公开给小队的记录。','metrics',m,'highlights','[]'::jsonb,'suggestion','{}'::jsonb) where id=r.id;
   if p_action='share_report' and p_args->>'method'='feed' then
    for teammate in select user_id from public.team_members where team_id=r.team_id and left_at is null and user_id<>u loop
     perform app.notify(teammate.user_id,'report','队友分享了周报','一起看看这一周留下的记录。',r.id,'report-share:'||r.id||':'||teammate.user_id);
    end loop;
   end if;
  end if;
 end if;
 return result;
end $$;
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;
create function public.apply_report_result(p_report_id uuid,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.reports; begin
 select * into r from public.reports where id=p_report_id for update;
 if not found or r.metrics is distinct from p_result->'metrics' or r.refreshed is distinct from (p_result->>'refreshed')::boolean then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 if not exists(select 1 from public.jobs where id=(p_result->>'job_id')::uuid and lease_token=(p_result->>'lease_token')::uuid and status='processing' and lease_until>now() and payload->>'report_id'=r.id::text and kind='report') then return jsonb_build_object('applied',false,'reason','lease_changed'); end if;
 if jsonb_typeof(p_result->'evidence') is distinct from 'array' or char_length(p_result->>'summary')>4000 then raise exception 'Report result schema mismatch'; end if;
 update public.reports set summary=p_result->>'summary',evidence=p_result->'evidence' where id=r.id;
 return jsonb_build_object('applied',true);
end $$;
revoke all on function public.apply_report_result(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.apply_report_result(uuid,jsonb) to service_role;
revoke all on all functions in schema app from public,anon;
grant execute on function app.team_for(uuid),app.can_checkin(uuid,uuid),app.can_team(uuid,uuid),app.can_report(uuid,uuid) to authenticated;
