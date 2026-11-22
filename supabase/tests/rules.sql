\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
insert into auth.users(id) select ('80000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,3) i;
update public.profiles set created_at='2026-11-01T00:00:00Z' where id::text like '80000000%';
insert into public.teams(id,name,timezone,owner_id,created_at) values('81000000-0000-4000-8000-000000000001','称号测试','Asia/Shanghai','80000000-0000-4000-8000-000000000001','2026-11-01T00:00:00Z');
insert into public.team_members(team_id,user_id,joined_at) select '81000000-0000-4000-8000-000000000001',id,'2026-11-01T00:00:00Z' from public.profiles where id::text like '80000000%';
insert into public.plans(id,user_id,title,category,created_at) select ('82000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('80000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'计划'||i,'study','2026-11-02T00:00:00Z' from generate_series(1,2) i;
insert into public.checkins(id,user_id,team_id,plan_id,batch_id,local_date,timezone,created_at)
select ('83000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001',gen_random_uuid(),'2026-11-02'::date+i-1,'Asia/Shanghai','2026-11-02T01:00:00Z'::timestamptz+interval '1 day'*(i-1) from generate_series(1,2) i;
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000001','2026-11-02')->>'key'='checkins','real count active title');
insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,created_at)
select '80000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000002',gen_random_uuid(),'2026-11-02'::date+i-1,'Asia/Shanghai','2026-11-02T01:00:00Z'::timestamptz+interval '1 day'*(i-1) from generate_series(1,2) i;
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000002','2026-11-02')->>'key'='checkins','tied count both awarded');
insert into public.interactions(checkin_id,user_id,kind,content,local_date) values('83000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000002','comment','继续','2026-11-02');
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000002','2026-11-02')->>'key'='comments','comment title uses non-challenge count');
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000001','2026-11-02')->>'key'='received','received interactions title');
insert into public.overdue_feed(id,team_id,user_id,plan_id,local_date,deadline_at) values('84000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','2026-11-04','2026-11-04T13:00:00Z');
insert into public.pokes(overdue_id,user_id) values('84000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000002');
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000001','2026-11-02')->>'key'='pokes','poke title only positive count');
insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,created_at)
select '80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001',gen_random_uuid(),'2026-11-02'::date+i-1,'Asia/Shanghai','2026-11-02T01:00:00Z'::timestamptz+interval '1 day'*(i-1) from generate_series(3,7) i;
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000001','2026-11-02')->>'key'='attendance','full attendance without makeup');
update public.plan_revisions set effective_on='2026-10-26',config=jsonb_set(config,'{anchor_date}','"2026-10-26"');
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000001','2026-11-02')->>'key'='improvement','largest rate improvement');
select pg_temp.assert_true(app.week_award('80000000-0000-4000-8000-000000000003','2026-11-02')='{}','no artificial title for zero activity');
select app.build_report('80000000-0000-4000-8000-000000000002','2026-11-02','Asia/Shanghai');
select pg_temp.assert_true((select suggestion ? 'basis' and jsonb_array_length(suggestion->'changes'->'weekdays')=2 from public.reports),'suggestion cites actual 2 of 7 completion');
select public.run_schedule('2026-11-08T12:01:00Z');
select public.run_schedule('2026-11-08T12:02:00Z');
select pg_temp.assert_true((select count(*)=1 from public.reports where kind='team' and week_start='2026-11-02'),'Sunday team report idempotent');
select pg_temp.assert_true((select (metrics->>'expected')::int=14 and (metrics->>'completed')::int=9 from public.reports where kind='team' and week_start='2026-11-02'),'team report has expected and completed public totals');
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000002',true);
select public.app_action('leave_team');
insert into public.team_members(team_id,user_id,joined_at) values('81000000-0000-4000-8000-000000000001',auth.uid(),'2026-11-09T00:00:00Z');
set local role authenticated;
select pg_temp.assert_true((select count(*)=2 from public.checkins),'rejoining sees own old history only');
reset role;
rollback;
\echo 'PASS rules: six award types, ties, empty awards, report totals and rejoin privacy'
