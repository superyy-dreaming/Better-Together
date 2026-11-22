create function public.bootstrap() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; tz text; d date; profile jsonb; team jsonb; begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 t:=app.team_for(u); tz:=app.timezone_for(u); d:=(now() at time zone tz)::date;
 select to_jsonb(p)||jsonb_build_object('timezone',tz,'paused_week_start',p.paused_week,'paused_week',coalesce(p.paused_week=date_trunc('week',d::timestamp)::date,false),'streak',app.streak(u),'makeup_remaining',greatest(0,2-(select count(*) from public.checkins where user_id=u and is_makeup and date_trunc('month',created_at at time zone tz)=date_trunc('month',now() at time zone tz)))) into profile from public.profiles p where id=u;
 if t is not null then
 select to_jsonb(x)||jsonb_build_object('streak',app.team_streak(t),'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,'avatar_url',p.avatar_url,'status',case
 when exists(select 1 from public.checkins c where c.user_id=p.id and c.local_date=d and c.status='makeup' and c.visibility='team') then '已补卡'
 when exists(select 1 from public.plans pl where pl.user_id=p.id and pl.status='active' and pl.visibility='team') and not exists(select 1 from public.plans pl where pl.user_id=p.id and pl.status='active' and pl.visibility='team' and extract(isodow from d)::int=any(pl.weekdays) and not exists(select 1 from public.checkins c where c.plan_id=pl.id and c.local_date=d and c.status in ('stamped','makeup'))) then '已完成'
 when exists(select 1 from public.checkins c where c.user_id=p.id and c.local_date=d and c.visibility='team') then '进行中' else '未开始' end)) from public.profiles p join public.team_members m on m.user_id=p.id where m.team_id=t and m.left_at is null),'[]')) into team from public.teams x where id=t;
 end if;
 return jsonb_build_object('profile',profile,'team',team,
 'plans',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('streak',app.streak(u,p.id)) order by p.created_at) from public.plans p where user_id=u),'[]'),
 'checkins',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select c.*,pr.nickname,coalesce(pl.category,'all') category,
  coalesce((select fields from public.batch_field_drafts where checkin_id=c.id and user_id=u),'[]') unassigned_fields,
  coalesce((select summary from public.batch_field_drafts where checkin_id=c.id and user_id=u),'') unassigned_summary,
  coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'url',case when m.deleted_at is null then m.path else '' end,'cleanup_status',m.cleanup_status,'source',m.source,'captured_at',m.captured_at,'plan_id',m.plan_id,'confidence',m.confidence) order by m.created_at) from public.media m where m.checkin_id=c.id and (m.deleted_at is null or (m.user_id=u and m.cleanup_status='pending'))),'[]') photos,
  (select count(*) from public.interactions where checkin_id=c.id and kind='like') likes,
  exists(select 1 from public.interactions where checkin_id=c.id and kind='like' and user_id=u) liked,
  coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'user_id',i.user_id,'nickname',pp.nickname,'content',i.content,'is_challenge',i.kind='challenge','created_at',i.created_at) order by i.created_at) from public.interactions i join public.profiles pp on pp.id=i.user_id where i.checkin_id=c.id and i.kind in ('comment','challenge')),'[]') comments,
  (select count(*) from public.interactions where checkin_id=c.id and kind='challenge') challenge_count,
  floor(c.team_size/2)+1 challenge_threshold
 from public.checkins c join public.profiles pr on pr.id=c.user_id left join public.plans pl on pl.id=c.plan_id where app.can_checkin(c.id,u) order by c.created_at desc limit 250) x),'[]'),
 'overdue',coalesce((select jsonb_agg(to_jsonb(x) order by x.deadline_at desc) from (select o.*,p.title,pr.nickname,(select count(*) from public.pokes where overdue_id=o.id) poke_count,exists(select 1 from public.pokes where overdue_id=o.id and user_id=u) poked from public.overdue_feed o join public.plans p on p.id=o.plan_id join public.profiles pr on pr.id=o.user_id where o.user_id=u or (app.in_sharing_period(o.team_id,u,o.synced_at) and app.in_sharing_period(o.team_id,o.user_id,o.synced_at))) x),'[]'),
 'reports',coalesce((select jsonb_agg((case when r.user_id=u or r.kind='team' then to_jsonb(r)-'public_snapshot' else r.public_snapshot end)||jsonb_build_object(
  'likes',(select count(*) from public.report_interactions where report_id=r.id and kind='like'),
  'liked',exists(select 1 from public.report_interactions where report_id=r.id and kind='like' and user_id=u),
  'comments',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'user_id',i.user_id,'nickname',p.nickname,'content',i.content,'created_at',i.created_at) order by i.created_at) from public.report_interactions i join public.profiles p on p.id=i.user_id where i.report_id=r.id and i.kind='comment'),'[]')) order by r.week_start desc) from public.reports r where app.can_report(r.id,u)),'[]'),
 'notifications',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.notifications where user_id=u order by created_at desc limit 100) x),'[]'));
end $$;
revoke all on function public.bootstrap() from public,anon;
grant execute on function public.bootstrap() to authenticated;

-- Default EXECUTE is public in PostgreSQL: private helpers are not RPC surfaces.
revoke all on all functions in schema app from public,anon;
grant execute on function app.team_for(uuid),app.can_checkin(uuid,uuid),app.can_team(uuid,uuid) to authenticated;
