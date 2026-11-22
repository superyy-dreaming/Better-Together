\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'ASSERT: %',label; end if; end $$;
insert into auth.users(id) values('73000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000001',true);
update public.profiles set timezone='America/Los_Angeles' where id=auth.uid();

insert into public.plans(id,user_id,title,category,schedule_kind,weekly_target_days,anchor_date,created_at)
values('74000000-0000-4000-8000-000000000001',auth.uid(),'旧自然周目标','study','weekly_target',3,
 (now() at time zone 'America/Los_Angeles')::date-7,now()-interval '7 days');

select public.app_action('save_plan','{"schema_version":2,"id":"74000000-0000-4000-8000-000000000001","title":"滚动周期目标","category":"study","schedule_kind":"period_target","period_days":5,"period_target_days":3,"weekdays":[1,2,3,4,5,6,7],"start_time":"08:00","deadline":"21:00","visibility":"private","status":"active"}');
select pg_temp.ok((select schedule_kind='weekly_target' and next_config->>'schedule_kind'='period_target'
 and (next_config->>'period_days')::int=5 and (next_config->>'period_target_days')::int=3
 from public.plans where id='74000000-0000-4000-8000-000000000001'),
 'edited period schedule is saved as a pending next-week revision');

select public.run_schedule(((select effective_on from public.plans where id='74000000-0000-4000-8000-000000000001')::timestamp
 +time '00:31') at time zone 'America/Los_Angeles');
select pg_temp.ok((select schedule_kind='period_target' and period_days=5 and period_target_days=3
 and next_config is null and effective_on is null
 from public.plans where id='74000000-0000-4000-8000-000000000001'),
 'scheduler activates the saved cycle length and target');
select pg_temp.ok((app.plan_on_day('74000000-0000-4000-8000-000000000001',
 (select anchor_date from public.plans where id='74000000-0000-4000-8000-000000000001'))->>'period_days')::int=5,
 'revision exposes activated cycle length');

insert into public.checkins(user_id,plan_id,batch_id,local_date,timezone,created_at)
select auth.uid(),'74000000-0000-4000-8000-000000000001',gen_random_uuid(),
 (select anchor_date from public.plans where id='74000000-0000-4000-8000-000000000001')+i,
 'America/Los_Angeles',now()+i*interval '1 minute' from generate_series(0,2)i;
select pg_temp.ok((app.period_progress('74000000-0000-4000-8000-000000000001',
 (select anchor_date+4 from public.plans where id='74000000-0000-4000-8000-000000000001'))->>'period_completed')::int=3,
 'distinct completion dates satisfy the three-of-five target');
select pg_temp.ok((app.period_progress('74000000-0000-4000-8000-000000000001',
 (select anchor_date+4 from public.plans where id='74000000-0000-4000-8000-000000000001'))->>'period_streak')::int=1,
 'cycle target contributes one completed period');
rollback;
\echo 'PASS period target save, activation and progress'
