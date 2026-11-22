\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
insert into auth.users(id) select ('70000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,6) i;
insert into public.teams(id,name,timezone,owner_id) values('71000000-0000-4000-8000-000000000001','边界测试','Asia/Shanghai','70000000-0000-4000-8000-000000000001');
insert into public.team_members(team_id,user_id,joined_at) select '71000000-0000-4000-8000-000000000001',id,now()-interval '7 days' from public.profiles where id::text like '70000000%';
insert into public.plans(user_id,title,category,start_time,deadline)
select ('70000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'截止'||i,'study','08:00',(array[time '23:00',time '23:15',time '23:30',time '23:50'])[i] from generate_series(1,4) i;
select public.run_schedule(((now() at time zone 'Asia/Shanghai')::date+time '23:29') at time zone 'Asia/Shanghai');
select pg_temp.assert_true((select count(*)=0 from public.overdue_feed),'no overdue before 23:30 for four edge deadlines');
select public.run_schedule(((now() at time zone 'Asia/Shanghai')::date+time '23:30') at time zone 'Asia/Shanghai');
select pg_temp.assert_true((select count(*)=4 from public.overdue_feed),'23:00 23:15 23:30 23:50 all cap at 23:30');
select set_config('request.jwt.claim.sub','70000000-0000-4000-8000-000000000005',true);
select public.app_action('save_plan','{"title":"早运动","category":"exercise","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"20:00"}');
select public.app_action('save_plan','{"title":"晚学习","category":"study","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"22:00"}');
select public.app_action('save_plan','{"title":"饮食","category":"food","weekdays":[1,2,3,4,5,6,7],"start_time":"00:00","deadline":"22:00"}');
insert into public.checkins(id,user_id,team_id,plan_id,batch_id,local_date,timezone,is_late,user_edited,fields,created_at)
select '73000000-0000-4000-8000-000000000001',auth.uid(),'71000000-0000-4000-8000-000000000001',id,gen_random_uuid(),(now() at time zone 'Asia/Shanghai')::date,'Asia/Shanghai',true,true,'[{"key":"calories","label":"消耗","value":450,"source":"manual"}]',((now() at time zone 'Asia/Shanghai')::date+time '21:00') at time zone 'Asia/Shanghai' from public.plans where title='早运动';
insert into public.overdue_feed(team_id,user_id,plan_id,local_date,deadline_at,status)
select '71000000-0000-4000-8000-000000000001',auth.uid(),id,(now() at time zone 'Asia/Shanghai')::date,now(),case when title='早运动' then 'resolved' else 'open' end from public.plans where user_id=auth.uid();
do $$ begin
 perform public.app_action('reclassify',jsonb_build_object('checkin_id','73000000-0000-4000-8000-000000000001','plan_id',(select id from public.plans where title='饮食')));
 raise exception 'precise calories moved into food';
 exception when raise_exception then if sqlerrm<>'这份手填纪要与目标计划不符。请先把热量改为估算区间或清空该字段，再修改分类' then raise; end if;
end $$;
select public.app_action('reclassify',jsonb_build_object('checkin_id','73000000-0000-4000-8000-000000000001','plan_id',(select id from public.plans where title='晚学习')));
select pg_temp.assert_true((select not is_late and user_edited and fields->0->>'value'='450' from public.checkins where id='73000000-0000-4000-8000-000000000001'),'reclassification recalculates lateness and preserves manual fields');
select pg_temp.assert_true((select status='open' from public.overdue_feed where plan_id=(select id from public.plans where title='早运动')),'old plan overdue reopened');
select pg_temp.assert_true((select status='resolved' from public.overdue_feed where plan_id=(select id from public.plans where title='晚学习')),'new plan overdue resolved');
select public.app_action('reclassify',jsonb_build_object('checkin_id','73000000-0000-4000-8000-000000000001','plan_id',(select id from public.plans where title='早运动')));
select pg_temp.assert_true((select is_late from public.checkins where id='73000000-0000-4000-8000-000000000001'),'reverse reassignment recalculates earlier cutoff');
-- Moving teams cannot carry old public checkin counts into a new team's report.
select public.app_action('leave_team');
insert into public.teams(id,name,timezone,owner_id) values('71000000-0000-4000-8000-000000000002','新小队','Asia/Shanghai',auth.uid());
insert into public.team_members(team_id,user_id,joined_at) values('71000000-0000-4000-8000-000000000002',auth.uid(),now()+interval '1 minute');
select pg_temp.assert_true((app.week_counts(auth.uid(),date_trunc('week',now() at time zone 'Asia/Shanghai')::date,true)->>'checkins')::int=0,'new team public report excludes old team stamps');
select pg_temp.assert_true((app.week_counts(auth.uid(),date_trunc('week',now() at time zone 'Asia/Shanghai')::date,false)->>'checkins')::int=1,'personal report retains own old stamps');
rollback;
\echo 'PASS review: deadline cap, reclassification invariants, cross-team aggregates'
