-- Keep existing invitation hashes valid. New invitations use 40 random bits
-- with an unambiguous alphabet; only hashes are stored.
create table app.invite_attempts (
 user_id uuid not null references public.profiles(id) on delete cascade,
 operation text not null check(operation in ('join_team','create_invite')),
 window_started_at timestamptz not null,
 attempts integer not null,
 primary key(user_id,operation)
);
revoke all on app.invite_attempts from public,anon,authenticated;

alter function public.app_action(text,jsonb) rename to app_action_before_short_invites;
revoke all on function public.app_action_before_short_invites(text,jsonb) from public,anon,authenticated;

create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); t uuid; token text; raw text; random_bytes bytea;
 alphabet constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
 attempts_count integer; clock_time timestamptz:=clock_timestamp();
 ttl interval; max_attempts integer; expiry timestamptz;
begin
 if p_action not in ('create_invite','join_team') then
  return public.app_action_before_short_invites(p_action,p_args);
 end if;
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if not exists(select 1 from public.profiles where id=u and deletion_requested_at is null) then
  raise exception '账号暂不可用，请先完成账号操作';
 end if;
 t:=app.team_for(u);
 if p_action='join_team' and t is not null then raise exception '你已在一个小队中'; end if;
 if p_action='create_invite' and t is null then raise exception '请先创建或加入小队'; end if;
 ttl:=case when p_action='join_team' then interval '15 minutes' else interval '1 hour' end;
 max_attempts:=case when p_action='join_team' then 10 else 30 end;
 insert into app.invite_attempts as a(user_id,operation,window_started_at,attempts)
 values(u,p_action,clock_time,1)
 on conflict(user_id,operation) do update set
  attempts=case when a.window_started_at+ttl<=clock_time then 1 else least(a.attempts+1,max_attempts+1) end,
  window_started_at=case when a.window_started_at+ttl<=clock_time then clock_time else a.window_started_at end
 returning attempts into attempts_count;
 -- Return an error envelope so denied attempts COMMIT instead of rolling back.
 -- The Edge API translates this committed result to HTTP 429 / 400.
 if attempts_count>max_attempts then
  return jsonb_build_object('error',jsonb_build_object('code','INVITE_RATE_LIMIT','message',
   case when p_action='join_team' then '尝试次数较多，请 15 分钟后再试，或核对队友发来的邀请。'
   else '邀请生成较频繁，请稍后再试。已生成的邀请仍可使用。' end,'status',429));
 end if;
 if p_action='create_invite' then
  perform 1 from public.teams where id=t and dissolved_at is null for update;
  if not found or app.team_for(u) is distinct from t then raise exception '小队状态已变化，请刷新后重试'; end if;
  expiry:=clock_time+interval '7 days';
  for retry in 1..8 loop
   random_bytes:=extensions.gen_random_bytes(8);token:='';
   for n in 0..7 loop token:=token||substr(alphabet,(get_byte(random_bytes,n)%32)+1,1); end loop;
   begin
    insert into public.invites(team_id,token_hash,expires_at,created_by)
    values(t,encode(extensions.digest(token,'sha256'),'hex'),expiry,u);
    return jsonb_build_object('token',token,'url','bettertogether://invite/'||token,'expires_at',expiry);
   exception when unique_violation then null;
   end;
  end loop;
  raise exception '暂时无法生成邀请，请重试';
 end if;
 raw:=trim(p_args->>'token');
 token:=upper(regexp_replace(raw,'[[:space:]-]','','g'));
 if token !~ '^[A-HJ-NP-Z2-9]{8}$' then
  token:=case when raw ~ '^[a-fA-F0-9]{48}$' then lower(raw) else null end;
 end if;
 select team.id into t from public.invites i join public.teams team on team.id=i.team_id
 where i.token_hash=encode(extensions.digest(token,'sha256'),'hex')
 and i.expires_at>clock_time and i.revoked_at is null and team.dissolved_at is null
 for update of team;
 if t is null or not exists(select 1 from public.invites i join public.teams team on team.id=i.team_id
  where i.team_id=t and i.token_hash=encode(extensions.digest(token,'sha256'),'hex')
  and i.expires_at>clock_timestamp() and i.revoked_at is null and team.dissolved_at is null) then
  return jsonb_build_object('error',jsonb_build_object('code','INVITE_INVALID','message','邀请码无效或已过期，请让队友重新生成邀请。','status',400));
 end if;
 if (select count(*) from public.team_members where team_id=t and left_at is null)>=5 then raise exception '小队已满 5 人'; end if;
 insert into public.team_members(team_id,user_id) values(t,u);
 return jsonb_build_object('id',t);
end $$;
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;
