\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
insert into auth.users(id) select ('16000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,7) i;
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000001',true);
select public.app_action('create_team','{"name":"短码小队","timezone":"Asia/Shanghai"}');
create temp table context as select app.team_for(auth.uid()) team_id,(public.app_action('create_invite')->>'token') token;
select pg_temp.assert_true((select token ~ '^[A-HJ-NP-Z2-9]{8}$' from context),'short unambiguous code');
select pg_temp.assert_true((select token_hash=encode(extensions.digest(token,'sha256'),'hex') from public.invites,context),'only hash stored');
insert into public.invites(team_id,token_hash,expires_at,created_by)
select team_id,encode(extensions.digest(repeat('ab',24),'sha256'),'hex'),now()+interval '1 day',auth.uid() from context;
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000002',true);
select public.app_action('join_team',jsonb_build_object('token',' '||lower(substr(token,1,4))||'-'||lower(substr(token,5))||' ')) from context;
select pg_temp.assert_true(app.team_for(auth.uid())=(select team_id from context),'formatted lowercase joins');
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000003',true);
select public.app_action('join_team',jsonb_build_object('token',repeat('ab',24)));
select pg_temp.assert_true(app.team_for(auth.uid())=(select team_id from context),'legacy invite joins');
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000004',true);
do $$ declare result jsonb; begin
 for i in 1..10 loop
  result:=public.app_action('join_team','{"token":"INVALID"}');
  perform pg_temp.assert_true(result->'error'->>'code'='INVITE_INVALID','invalid denial');
 end loop;
 result:=public.app_action('join_team',jsonb_build_object('token',(select token from context)));
 perform pg_temp.assert_true(result->'error'->>'code'='INVITE_RATE_LIMIT','attempts persist after rejection');
end $$;
select pg_temp.assert_true(app.team_for(auth.uid()) is null,'rate limited request cannot join');
update app.invite_attempts set window_started_at=now()-interval '16 minutes' where user_id=auth.uid();
select public.app_action('join_team',jsonb_build_object('token',token)) from context;
select pg_temp.assert_true(app.team_for(auth.uid())=(select team_id from context),'rate window recovers');
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000005',true);
update public.invites set expires_at=now()-interval '1 minute';
select pg_temp.assert_true((public.app_action('join_team',jsonb_build_object('token',token))->'error'->>'code')='INVITE_INVALID','expired invitation denied') from context;
update public.invites set expires_at=now()+interval '1 day',revoked_at=now();
select pg_temp.assert_true((public.app_action('join_team',jsonb_build_object('token',token))->'error'->>'code')='INVITE_INVALID','revoked invitation denied') from context;
set local role authenticated;
select pg_temp.assert_true(not has_function_privilege('authenticated','public.app_action_before_short_invites(text,jsonb)','execute'),'legacy function not callable');
reset role;
rollback;
