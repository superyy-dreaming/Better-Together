-- Durable rule history keeps next-week edits from rewriting previous statistics.
create function app.guard_media_batch() returns trigger language plpgsql security definer set search_path='' as $$ begin
 perform pg_advisory_xact_lock(hashtextextended(new.batch_id::text,1));
 if (select count(*) from public.media where user_id=new.user_id and batch_id=new.batch_id and deleted_at is null)>=9 then raise exception '每次最多 9 张照片'; end if;
 return new;
end $$;
create trigger media_batch_limit before insert on public.media for each row execute function app.guard_media_batch();
create table public.plan_revisions (
 id uuid primary key default gen_random_uuid(), plan_id uuid not null references public.plans(id) on delete cascade,
 effective_on date not null, config jsonb not null, unique(plan_id,effective_on)
);
create table public.paused_weeks (
 user_id uuid not null references public.profiles(id) on delete cascade, week_start date not null,
 primary key(user_id,week_start)
);
alter table public.plan_revisions enable row level security;
alter table public.paused_weeks enable row level security;
grant all on public.plan_revisions,public.paused_weeks to service_role;
create function app.record_plan_revision() returns trigger language plpgsql security definer set search_path='' as $$
declare effective date; cfg jsonb; days int[]; begin
 cfg:=new.next_config;
 if cfg is not null then
  days:=array(select jsonb_array_elements_text(cfg->'weekdays')::int);
  if coalesce(char_length(trim(cfg->>'title')),0) not between 1 and 100
   or coalesce(cfg->>'category','') not in ('study','exercise','food','custom')
   or coalesce(cfg->>'status','active') not in ('active','paused','ended')
   or coalesce(cfg->>'visibility','team') not in ('team','private')
   or cardinality(days) not between 1 and 7 or not days<@array[1,2,3,4,5,6,7]
   or cardinality(days)<>(select count(distinct d) from unnest(days) d)
   or (cfg->>'start_time') is null or (cfg->>'deadline') is null
   or (cfg->>'start_time')::time>(cfg->>'deadline')::time then raise exception '请核对计划名称、频率、状态与时段'; end if;
  if coalesce(cfg->>'status','active')='active' and (select count(*) from public.plans where user_id=new.user_id and id<>new.id and coalesce(next_config->>'status',status)='active')>=3 then raise exception '最多同时进行 3 个计划'; end if;
 end if;
 if (select count(distinct d) from unnest(new.weekdays) d)<>cardinality(new.weekdays) then raise exception '每周日期不能重复'; end if;
 if tg_op='INSERT' then effective:=(new.created_at at time zone app.timezone_for(new.user_id))::date;
 elsif (to_jsonb(new)-array['next_config','effective_on']) is not distinct from (to_jsonb(old)-array['next_config','effective_on']) then return new;
 else effective:=coalesce(old.effective_on,(now() at time zone app.timezone_for(new.user_id))::date); end if;
 insert into public.plan_revisions(plan_id,effective_on,config) values(new.id,effective,to_jsonb(new)-array['next_config','effective_on'])
 on conflict(plan_id,effective_on) do update set config=excluded.config;
 return new;
end $$;
create trigger plan_rule_history after insert or update on public.plans for each row execute function app.record_plan_revision();
insert into public.plan_revisions(plan_id,effective_on,config) select id,(created_at at time zone app.timezone_for(user_id))::date,to_jsonb(p)-array['next_config','effective_on'] from public.plans p;
create function app.record_pause() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if new.paused_week is not null then insert into public.paused_weeks values(new.id,new.paused_week) on conflict do nothing;
 elsif old.paused_week=date_trunc('week',now() at time zone app.timezone_for(new.id))::date then delete from public.paused_weeks where user_id=new.id and week_start=old.paused_week; end if;
 return new;
end $$;
create trigger pause_history after update of paused_week on public.profiles for each row execute function app.record_pause();
create function app.plan_on_day(p_plan uuid,p_day date) returns jsonb language sql stable security definer set search_path='' as $$
 select config from public.plan_revisions where plan_id=p_plan and effective_on<=p_day order by effective_on desc limit 1
$$;
-- -1 rest; 0 incomplete; 1 all due plans completed; 2 preserved by makeup/redo.
create function app.day_outcome(p_user uuid,p_day date,p_plan uuid default null,p_public boolean default false) returns int
language plpgsql stable security definer set search_path='' as $$
declare p record; cfg jsonb; due_count int:=0; frozen boolean:=false; begin
 if exists(select 1 from public.paused_weeks where user_id=p_user and week_start=date_trunc('week',p_day::timestamp)::date) then return -1; end if;
 for p in select id from public.plans where user_id=p_user and (p_plan is null or id=p_plan) loop
  cfg:=app.plan_on_day(p.id,p_day);
  if cfg is null or cfg->>'status'<>'active' or (p_public and cfg->>'visibility'<>'team') or not (cfg->'weekdays') @> to_jsonb(extract(isodow from p_day)::int) then continue; end if;
  due_count:=due_count+1;
  if exists(select 1 from public.checkins where plan_id=p.id and local_date=p_day and status in ('makeup','redo_required')) then frozen:=true;
  elsif not exists(select 1 from public.checkins where plan_id=p.id and local_date=p_day and status='stamped' and not is_late) then return 0; end if;
 end loop;
 if due_count=0 then return -1; end if;
 return case when frozen then 2 else 1 end;
end $$;
create or replace function app.streak(p_user uuid,p_plan uuid default null) returns int language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone app.timezone_for(p_user))::date; d date; earliest date; outcome int; total int:=0; frozen int; begin
 select case when p_plan is null then frozen_user_streak else frozen_plan_streak end into frozen from public.checkins where user_id=p_user and (p_plan is null or plan_id=p_plan) and status='redo_required' order by created_at desc limit 1;
 if frozen is not null then return frozen; end if;
 select min(r.effective_on) into earliest from public.plan_revisions r join public.plans p on p.id=r.plan_id where p.user_id=p_user and (p_plan is null or p.id=p_plan);
 if earliest is null then return 0; end if;
 d:=today;
 while d>=earliest loop
  outcome:=app.day_outcome(p_user,d,p_plan);
  if outcome=0 and d<>today then exit; end if;
  if outcome=1 then total:=total+1; end if;
  d:=d-1;
 end loop;
 return total;
end $$;
create function app.team_streak(p_team uuid) returns int language plpgsql stable security definer set search_path='' as $$
declare today date; d date; earliest date; outcome int; total int:=0; m record; any_due boolean; incomplete boolean; frozen boolean; begin
 select (now() at time zone timezone)::date,created_at::date into today,earliest from public.teams where id=p_team;
 d:=today;
 while d>=earliest loop
  any_due:=false; incomplete:=false; frozen:=false;
  for m in select user_id from public.team_members tm join public.teams t on t.id=tm.team_id where tm.team_id=p_team and tm.left_at is null and (tm.joined_at at time zone t.timezone)::date<=d loop
   outcome:=app.day_outcome(m.user_id,d,null,true);
   any_due:=any_due or outcome<>-1; incomplete:=incomplete or outcome=0; frozen:=frozen or outcome=2;
  end loop;
  if incomplete and d<>today then exit; end if;
  if any_due and not incomplete and not frozen then total:=total+1; end if;
  d:=d-1;
 end loop;
 return total;
end $$;

create or replace function public.apply_ai_result(p_checkin_id uuid,p_result jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.checkins; a jsonb; g jsonb; pid uuid; newid uuid; groupids uuid[]:='{}'; memo_fields jsonb; category text; target record; assigned uuid[]; grouped uuid[]; defer_fields boolean:=false; defer_summary boolean:=false; begin
 select * into c from public.checkins where id=p_checkin_id for update;
 if not found then return jsonb_build_object('applied',false,'reason','missing'); end if;
 if c.version<>coalesce((p_result->>'version')::int,0) or (c.user_edited and not c.classification_pending) or (c.memo_status<>'pending' and not c.classification_pending) then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 if not exists(select 1 from public.jobs where id=(p_result->>'job_id')::uuid and lease_token=(p_result->>'lease_token')::uuid and status='processing' and lease_until>now() and payload->>'checkin_id'=c.id::text and kind='ai') then return jsonb_build_object('applied',false,'reason','lease_changed'); end if;
 if jsonb_typeof(p_result->'assignments') is distinct from 'array' or jsonb_typeof(p_result->'groups') is distinct from 'array' then raise exception 'AI assignments schema mismatch'; end if;
 assigned:=array(select (value->>'photo_id')::uuid from jsonb_array_elements(p_result->'assignments'));
 if cardinality(assigned)<>(select count(distinct x) from unnest(assigned) x) or cardinality(assigned)<>(select count(*) from public.media where checkin_id=c.id and deleted_at is null)
 or exists(select 1 from unnest(assigned) x where not exists(select 1 from public.media where id=x and checkin_id=c.id and deleted_at is null)) then raise exception 'AI assignments must cover every photo exactly once'; end if;
 for a in select value from jsonb_array_elements(p_result->'assignments') loop
  pid:=nullif(a->>'plan_id','')::uuid;
  if c.plan_id is not null and pid is distinct from c.plan_id then raise exception 'AI cannot override selected plan'; end if;
  if pid is not null and not exists(select 1 from public.plans where id=pid and user_id=c.user_id) then raise exception 'AI plan not owned by member'; end if;
  if (a->>'confidence')::numeric not between 0 and 1 then raise exception 'AI confidence outside range'; end if;
  update public.media set plan_id=pid,confidence=(a->>'confidence')::numeric where id=(a->>'photo_id')::uuid and checkin_id=c.id;
 end loop;
 grouped:=array(select jsonb_array_elements_text(value->'photo_ids')::uuid from jsonb_array_elements(p_result->'groups'));
 if cardinality(grouped)<>cardinality(assigned) or cardinality(grouped)<>(select count(distinct x) from unnest(grouped) x) or not grouped @> assigned then raise exception 'AI groups must cover every photo exactly once'; end if;
 if (select count(*) from jsonb_array_elements(p_result->'groups'))<>(select count(distinct coalesce(value->>'plan_id','ALL')) from jsonb_array_elements(p_result->'groups')) then raise exception 'AI groups must be unique by plan'; end if;
 defer_fields:=c.user_edited and jsonb_array_length(c.fields)>0 and jsonb_array_length(p_result->'groups')>1;
 defer_summary:=c.plan_id is null and char_length(trim(c.summary))>0;
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
  update public.checkins set plan_id=pid,visibility=coalesce((select visibility from public.plans where id=pid),'team'),
   is_late=case when c.redo_of is null and not c.is_makeup and pid is not null then (c.created_at at time zone c.timezone)::time>(select deadline from public.plans where id=pid) else c.is_late end,
   summary=case when c.user_edited and not defer_summary then c.summary else left(coalesce(g->>'summary',''),4000) end,fields=memo_fields,user_edited=c.user_edited,memo_status='ready',classification_pending=false,version=version+1 where id=newid;
  update public.overdue_feed set status='resolved' where plan_id=pid and local_date=c.local_date and user_id=c.user_id;
  groupids:=array_append(groupids,newid);
 end loop;
 if defer_fields or defer_summary then
  insert into public.batch_field_drafts(checkin_id,user_id,batch_id,fields,summary)
  values(c.id,c.user_id,c.batch_id,case when defer_fields then c.fields else '[]'::jsonb end,case when defer_summary then c.summary else '' end)
  on conflict(checkin_id) do update set fields=excluded.fields,summary=excluded.summary;
 end if;
 return jsonb_build_object('applied',true,'checkin_ids',to_jsonb(groupids));
end $$;
revoke all on all functions in schema app from public,anon;
grant execute on function app.team_for(uuid),app.can_checkin(uuid,uuid),app.can_team(uuid,uuid) to authenticated;
