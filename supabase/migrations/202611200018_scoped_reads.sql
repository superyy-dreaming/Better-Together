-- Separate permission-filtered record reads from expiring media delivery URLs.
alter table public.media add column thumbnail_path text;
create index if not exists checkins_created_cursor on public.checkins(created_at desc,id desc);
create index if not exists plans_owner_cursor on public.plans(user_id,created_at desc,id desc);
create index if not exists reports_created_cursor on public.reports(generated_at desc,id desc);

create function app.avatar_ref(p_id uuid,p_path text) returns text language sql immutable set search_path='' as $$
 select case when p_path is null or p_path='' then 'preset:bear-'||lpad(((abs(hashtextextended(p_id::text,1)%12))+1)::text,2,'0') when p_path like 'preset:%' then p_path else 'avatar:'||p_id::text||':'||md5(p_path) end
$$;
create function app.checkin_json(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(c)||jsonb_build_object('nickname',p.nickname,'avatar_url',app.avatar_ref(p.id,p.avatar_url),'category',coalesce(pl.category,'all'),
 'unassigned_fields',coalesce((select fields from public.batch_field_drafts where checkin_id=c.id and user_id=auth.uid()),'[]'),
 'unassigned_summary',coalesce((select summary from public.batch_field_drafts where checkin_id=c.id and user_id=auth.uid()),''),
 'photos',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'url',case when m.deleted_at is null then 'media:'||m.id::text else '' end,'version',coalesce(m.metadata->>'original_sha256','1'),'thumbnail_available',m.thumbnail_path is not null,'cleanup_status',m.cleanup_status,'source',m.source,'captured_at',m.captured_at,'plan_id',m.plan_id,'confidence',m.confidence) order by m.created_at) from public.media m where m.checkin_id=c.id and (m.deleted_at is null or (m.user_id=auth.uid() and m.cleanup_status='pending'))),'[]'),
 'likes',(select count(*) from public.interactions where checkin_id=c.id and kind='like'),
 'liked',exists(select 1 from public.interactions where checkin_id=c.id and kind='like' and user_id=auth.uid()),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'user_id',i.user_id,'nickname',pp.nickname,'avatar_url',app.avatar_ref(pp.id,pp.avatar_url),'content',i.content,'is_challenge',i.kind='challenge','created_at',i.created_at) order by i.created_at) from public.interactions i join public.profiles pp on pp.id=i.user_id where i.checkin_id=c.id and i.kind in ('comment','challenge')),'[]'),
 'challenge_count',(select count(*) from public.interactions where checkin_id=c.id and kind='challenge'),'challenge_threshold',floor(c.team_size/2)+1)
 from public.checkins c join public.profiles p on p.id=c.user_id left join public.plans pl on pl.id=c.plan_id where c.id=p_id and app.can_checkin(c.id,auth.uid())
$$;
create function app.report_json(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select (case when r.user_id=auth.uid() or r.kind='team' then to_jsonb(r)-'public_snapshot' else r.public_snapshot end)||jsonb_build_object(
 'likes',(select count(*) from public.report_interactions where report_id=r.id and kind='like'),
 'liked',exists(select 1 from public.report_interactions where report_id=r.id and kind='like' and user_id=auth.uid()),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'user_id',i.user_id,'nickname',p.nickname,'avatar_url',app.avatar_ref(p.id,p.avatar_url),'content',i.content,'created_at',i.created_at) order by i.created_at) from public.report_interactions i join public.profiles p on p.id=i.user_id where i.report_id=r.id and i.kind='comment'),'[]')) from public.reports r where id=p_id and app.can_report(id,auth.uid())
$$;
create function public.read_page(p_args jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); kind text:=p_args->>'collection'; n int:=least(50,greatest(1,coalesce((p_args->>'limit')::int,20))); cur jsonb:=nullif(p_args->>'cursor','')::jsonb; items jsonb; more boolean; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 if kind='plans' then
 select coalesce(jsonb_agg(item),'[]') into items from (select to_jsonb(p)||coalesce(app.plan_on_day(p.id,(now() at time zone app.timezone_for(u))::date),'{}')||app.plan_progress(p.id,(now() at time zone app.timezone_for(u))::date)||jsonb_build_object('streak',app.streak(u,p.id)) item from public.plans p where p.user_id=u
 and (coalesce(p_args->>'query','')='' or position(lower(p_args->>'query') in lower(p.title))>0)
 and (coalesce(p_args->>'category','all')='all' or p.category=p_args->>'category')
 and (coalesce(p_args->>'status','all')='all' or p.status=p_args->>'status')
 and (cur is null or (p.created_at,p.id)<((cur->>0)::timestamptz,(cur->>1)::uuid)) order by p.created_at desc,p.id desc limit n+1) x;
 elsif kind in ('checkins','history') then
 select coalesce(jsonb_agg(app.checkin_json(id)),'[]') into items from (select c.id from public.checkins c left join public.plans p on p.id=c.plan_id where app.can_checkin(c.id,u)
 and (kind<>'history' or c.user_id=u)
 and (coalesce(p_args->>'month','')='' or to_char(c.local_date,'YYYY-MM')=p_args->>'month')
 and (coalesce(p_args->>'category','all')='all' or coalesce(p.category,'all')=p_args->>'category')
 and (cur is null or (c.created_at,c.id)<((cur->>0)::timestamptz,(cur->>1)::uuid)) order by c.created_at desc,c.id desc limit n+1) x;
 elsif kind='reports' then
 select coalesce(jsonb_agg(app.report_json(id)),'[]') into items from (select r.id from public.reports r where app.can_report(id,u) and (cur is null or (r.generated_at,r.id)<((cur->>0)::timestamptz,(cur->>1)::uuid)) order by r.generated_at desc,r.id desc limit n+1) x;
 elsif kind='overdue' then
 select coalesce(jsonb_agg(item),'[]') into items from (select to_jsonb(o)||jsonb_build_object('title',p.title,'nickname',pr.nickname,'poke_count',(select count(*) from public.pokes where overdue_id=o.id),'poked',exists(select 1 from public.pokes where overdue_id=o.id and user_id=u)) item from public.overdue_feed o join public.plans p on p.id=o.plan_id join public.profiles pr on pr.id=o.user_id where (o.user_id=u or (app.in_sharing_period(o.team_id,u,o.synced_at) and app.in_sharing_period(o.team_id,o.user_id,o.synced_at))) and (cur is null or (o.synced_at,o.id)<((cur->>0)::timestamptz,(cur->>1)::uuid)) order by o.synced_at desc,o.id desc limit n+1) x;
 elsif kind='notifications' then
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into items from (select * from public.notifications where user_id=u and (cur is null or (created_at,id)<((cur->>0)::timestamptz,(cur->>1)::uuid)) order by created_at desc,id desc limit n+1) x;
 else raise exception '不支持的记录类型'; end if;
 more:=jsonb_array_length(items)>n;
 if more then items:=items-n; end if;
 return jsonb_build_object('items',items,'next_cursor',case when more then jsonb_build_array(items->(n-1)->(case kind when 'reports' then 'generated_at' when 'overdue' then 'synced_at' else 'created_at' end),items->(n-1)->'id')::text end);
end $$;
create function public.get_checkin(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; begin
 if auth.uid() is null then raise exception using errcode='28000',message='请先登录'; end if;
 result:=app.checkin_json(p_id);
 if result is null then raise exception using errcode='42501',message='记录已不可见'; end if;
 return result; end $$;

create function public.bootstrap_v2() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; zone text; d date; profile jsonb; team jsonb; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 t:=app.team_for(u); zone:=app.timezone_for(u); d:=(now() at time zone zone)::date;
 select to_jsonb(p)||jsonb_build_object('avatar_url',app.avatar_ref(p.id,p.avatar_url),'timezone',zone,'paused_week',coalesce(p.paused_week=date_trunc('week',d::timestamp)::date,false),'weekly_streak',app.weekly_streak(u,d),'streak',app.streak(u),'makeup_remaining',greatest(0,2-(select count(*) from public.checkins where user_id=u and is_makeup and date_trunc('month',created_at at time zone zone)=date_trunc('month',now() at time zone zone)))) into profile from public.profiles p where id=u;
 if t is not null then
 select to_jsonb(x)||jsonb_build_object('weekly_streak',app.team_weekly_streak(t,d),'streak',app.team_streak(t),'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,'avatar_url',app.avatar_ref(p.id,p.avatar_url),'status',case app.day_outcome(p.id,d,null,true) when 1 then 'completed' when 2 then 'makeup' else case when exists(select 1 from public.checkins c where c.user_id=p.id and c.local_date=d and c.visibility='team' and app.can_checkin(c.id,u)) then 'in_progress' else 'not_started' end end)) from public.profiles p join public.team_members m on m.user_id=p.id where m.team_id=t and m.left_at is null),'[]')) into team from public.teams x where id=t;
 end if;
 return jsonb_build_object('profile',profile,'team',team,
 'plans',coalesce((select jsonb_agg(to_jsonb(p)||coalesce(app.plan_on_day(p.id,(now() at time zone app.timezone_for(u))::date),'{}')||app.plan_progress(p.id,(now() at time zone app.timezone_for(u))::date)||jsonb_build_object('streak',app.streak(u,p.id)) order by p.created_at) from public.plans p where p.user_id=u and p.status='active' and (app.plan_due(p.id,d) or (coalesce(app.plan_on_day(p.id,d)->>'schedule_kind','weekdays')='weekly_target' and coalesce((app.plan_on_day(p.id,d)->>'anchor_date')::date,d)<=d))),'[]'),
 'checkins',coalesce((select jsonb_agg(app.checkin_json(id)) from (select id from public.checkins where user_id=u and local_date>=date_trunc('week',d::timestamp)::date order by created_at desc,id desc limit 100) c),'[]'),
 'notifications',(public.read_page('{"collection":"notifications"}')->'items'),
 'unread_count',(select count(*) from public.notifications where user_id=u and not read),
 'overdue','[]'::jsonb,'reports','[]'::jsonb);
end $$;

-- A stable reference is not an authorization grant. Check every requested object.
create function public.media_access(p_refs jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); value jsonb; ref text; parts text[]; target uuid; path text; result jsonb:='[]'; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 if jsonb_typeof(p_refs)<>'array' or jsonb_array_length(p_refs)>50 then raise exception '每次最多读取50张图片'; end if;
 for value in select * from jsonb_array_elements(p_refs) loop
 ref:=value->>'ref'; parts:=string_to_array(ref,':'); path:=null;
 if parts[1]='media' then
 target:=parts[2]::uuid;
 select case when value->>'variant'='thumbnail' then coalesce(m.thumbnail_path,m.path) else m.path end into path from public.media m where m.id=target and m.deleted_at is null and m.checkin_id is not null and app.can_checkin(m.checkin_id,u);
 elsif parts[1]='avatar' then
 target:=parts[2]::uuid;
 select p.avatar_url into path from public.profiles p where p.id=target and (p.id=u or (app.team_for(p.id) is not null and app.team_for(p.id)=app.team_for(u))) and p.avatar_url not like 'preset:%' and md5(p.avatar_url)=parts[3];
 end if;
 result:=result||jsonb_build_array(jsonb_build_object('ref',ref,'variant',coalesce(value->>'variant','original'),'bucket',case when parts[1]='avatar' then 'avatars' else 'evidence' end,'path',path,'allowed',path is not null));
 end loop;
 return result; end $$;
revoke all on function public.bootstrap_v2(),public.read_page(jsonb),public.get_checkin(uuid),public.media_access(jsonb) from public,anon;
grant execute on function public.bootstrap_v2(),public.read_page(jsonb),public.get_checkin(uuid),public.media_access(jsonb) to authenticated;
revoke all on function app.avatar_ref(uuid,text),app.checkin_json(uuid),app.report_json(uuid) from public,anon,authenticated;

create function public.get_plan(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; d date:=(now() at time zone app.timezone_for(auth.uid()))::date; begin
 select to_jsonb(p)||coalesce(app.plan_on_day(p.id,d),'{}')||app.plan_progress(p.id,d) into result from public.plans p where id=p_id and user_id=auth.uid();
 if result is null then raise exception using errcode='42501',message='计划不可见'; end if; return result;
end $$;
revoke all on function public.get_plan(uuid) from public,anon;
grant execute on function public.get_plan(uuid) to authenticated;
-- Server-only bounded candidates: date first, then explicit category/selection.
create function public.ai_plan_candidates(p_user uuid,p_day date,p_category text default null,p_selected uuid default null) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(row),'[]') from (select p.id,p.title,p.category,p.goal,p.visibility from public.plans p
 where p.user_id=p_user and ((p_selected is not null and p.id=p_selected) or (p_selected is null and p.status='active' and (app.plan_due(p.id,p_day) or (app.plan_on_day(p.id,p_day)->>'schedule_kind'='weekly_target' and p.anchor_date<=p_day)) and (p_category is null or p.category=p_category)))
 order by p.created_at,p.id limit 25) row
$$;
revoke all on function public.ai_plan_candidates(uuid,date,text,uuid) from public,anon,authenticated;
grant execute on function public.ai_plan_candidates(uuid,date,text,uuid) to service_role;

-- Revocations reach remaining members even when the changed row is no longer
-- visible under RLS. The lightweight team epoch invalidates rendered bytes.
alter table public.teams add column visibility_epoch bigint not null default 0;
create function app.bump_visibility_epoch() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='checkins' then
  if new.visibility is distinct from old.visibility or new.team_id is distinct from old.team_id then
   update public.teams set visibility_epoch=visibility_epoch+1 where id in(old.team_id,new.team_id);
  end if;
 elsif tg_table_name='media' then
  if new.deleted_at is distinct from old.deleted_at then update public.teams set visibility_epoch=visibility_epoch+1 where id=old.team_id; end if;
 end if;
 return new;
end $$;
create trigger checkin_visibility_epoch after update of visibility,team_id on public.checkins for each row execute function app.bump_visibility_epoch();
create trigger media_visibility_epoch after update of deleted_at on public.media for each row execute function app.bump_visibility_epoch();
revoke all on function app.bump_visibility_epoch() from public,anon,authenticated;

-- A durable derivative job is independent from the already committed stamp.
create function app.queue_thumbnail() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.jobs(kind,payload) values('thumbnail',jsonb_build_object('media_id',new.media_id)); return new;
end $$;
create trigger enqueue_thumbnail after insert on public.media_analysis for each row execute function app.queue_thumbnail();
revoke all on function app.queue_thumbnail() from public,anon,authenticated;
