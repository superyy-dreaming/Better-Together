\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'ASSERT: %',label; end if; end $$;
insert into auth.users(id) values('71000000-0000-4000-8000-000000000001'),('71000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
update public.profiles set timezone='America/Los_Angeles',created_at='2026-10-01' where id=auth.uid();
insert into public.plans(id,user_id,title,category,schedule_kind,weekly_target_days,anchor_date,created_at)
values('72000000-0000-4000-8000-000000000001',auth.uid(),'周末开始','water','weekly_target',5,'2026-10-31','2026-10-31T12:00:00Z');
select pg_temp.ok((app.plan_week('72000000-0000-4000-8000-000000000001','2026-10-31')->>'expected')::int=2,'first partial week capped at 2 days');
select pg_temp.ok(not app.plan_due('72000000-0000-4000-8000-000000000001','2026-11-01'),'weekly never daily due');
insert into public.checkins(user_id,plan_id,batch_id,local_date,timezone,created_at)
select auth.uid(),'72000000-0000-4000-8000-000000000001',gen_random_uuid(),'2026-10-31','America/Los_Angeles','2026-10-31T20:00:00Z' from generate_series(1,3);
select pg_temp.ok((app.plan_week('72000000-0000-4000-8000-000000000001','2026-10-31')->>'completed')::int=1,'multiple independent records count one date');
insert into public.plans(id,user_id,title,category,schedule_kind,interval_days,anchor_date,created_at)
values('72000000-0000-4000-8000-000000000002',auth.uid(),'隔天冥想','mindfulness','interval',2,'2026-10-31','2026-10-31T12:00:00Z');
select pg_temp.ok(app.plan_due('72000000-0000-4000-8000-000000000002','2026-11-02'),'interval crosses month and DST using dates');
select pg_temp.ok(not app.plan_due('72000000-0000-4000-8000-000000000002','2026-11-01'),'interval rest day');
select pg_temp.ok(not app.plan_due('72000000-0000-4000-8000-000000000002','2026-10-29'),'no dates before anchor');
do $$ begin
 perform public.app_action('save_plan','{"id":"72000000-0000-4000-8000-000000000002","title":"legacy","category":"study","weekdays":[1],"start_time":"08:00","deadline":"21:00"}');
 raise exception 'legacy editor overwrote interval';
exception when raise_exception then if sqlerrm<>'请升级 App 后编辑这种计划频率' then raise; end if; end $$;
select public.app_action('save_plan','{"schema_version":2,"id":"72000000-0000-4000-8000-000000000002","title":"新周期","category":"mindfulness","schedule_kind":"interval","interval_days":3,"weekdays":[1],"anchor_date":"2026-10-31","start_time":"08:00","deadline":"21:00"}');
select pg_temp.ok((app.plan_on_day('72000000-0000-4000-8000-000000000002','2026-11-02')->>'interval_days')::int=2,'edit cannot rewrite old schedule');
-- A complete week can exceed its target, while total completion remains capped.
insert into public.plans(id,user_id,title,category,schedule_kind,weekly_target_days,anchor_date,created_at)
values('72000000-0000-4000-8000-000000000003',auth.uid(),'每周两天','sleep','weekly_target',2,'2026-11-02','2026-11-02T12:00:00Z');
insert into public.checkins(user_id,plan_id,batch_id,local_date,timezone,created_at)
select auth.uid(),'72000000-0000-4000-8000-000000000003',gen_random_uuid(),'2026-11-02'::date+i,'America/Los_Angeles','2026-11-02T20:00:00Z'::timestamptz+i*interval '1 day' from generate_series(0,2)i;
select pg_temp.ok((app.plan_progress('72000000-0000-4000-8000-000000000003','2026-11-08')->>'extra_days')::int=1,'extra day reported separately');
select pg_temp.ok((app.plan_progress('72000000-0000-4000-8000-000000000003','2026-11-08')->>'weekly_streak')::int=1,'weekly achievement distinct from daily streak');
select pg_temp.ok((app.week_counts(auth.uid(),'2026-11-02')->>'completion_rate')::numeric<=1,'completion never over 100 percent');
select public.run_schedule('2026-11-09T04:00:00Z');
select pg_temp.ok((select stage='phase' from public.reports where user_id=auth.uid() and week_start='2026-11-02'),'Sunday stage report');
select public.run_schedule('2026-11-09T20:05:00Z');
select public.run_schedule('2026-11-09T20:06:00Z');
select pg_temp.ok((select count(*)=1 and bool_and(stage='final') from public.reports where user_id=auth.uid() and week_start='2026-11-02'),'Monday same report finalized once');
select pg_temp.ok(jsonb_array_length(public.read_page('{"collection":"plans","category":"water"}')->'items')=1,'server category filtering');
select pg_temp.ok(jsonb_array_length(public.read_page('{"collection":"plans","query":"冥想"}')->'items')=1,'server title search');
select pg_temp.ok(public.bootstrap_v2()->'profile'->>'avatar_url' like 'preset:bear-%','default avatar stable reference');
select pg_temp.ok(public.get_profile()->'paused_week'='false'::jsonb,'profile refresh returns false for no paused week');
update public.profiles set paused_week=date_trunc('week',now() at time zone app.timezone_for(auth.uid()))::date where id=auth.uid();
select pg_temp.ok(public.get_profile()->'paused_week'='true'::jsonb,'profile refresh keeps current pause state boolean');
update public.profiles set paused_week=paused_week-7 where id=auth.uid();
select pg_temp.ok(public.get_profile()->'paused_week'='false'::jsonb,'profile refresh expires old paused week');
select public.app_action('create_team','{"name":"跨时区资料验证","timezone":"Asia/Shanghai"}');
select pg_temp.ok(public.get_profile()->>'timezone'='Asia/Shanghai','profile refresh preserves effective team timezone');
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000002',true);
select pg_temp.ok(jsonb_array_length(public.read_page('{"collection":"history"}')->'items')=0,'history account isolation');
select pg_temp.ok(jsonb_array_length(public.read_page('{"collection":"plans"}')->'items')=0,'plans account isolation');
do $$ begin perform public.get_plan('72000000-0000-4000-8000-000000000001'); raise exception 'foreign plan returned'; exception when insufficient_privilege then null; end $$;
select pg_temp.ok((public.media_access('[{"ref":"avatar:71000000-0000-4000-8000-000000000001:no","variant":"original"}]')->0->>'allowed')::boolean=false,'foreign avatar denied');
rollback;
\echo 'PASS flexible schedule, weekly report lifecycle and scoped reads'
