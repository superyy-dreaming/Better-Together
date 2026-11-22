-- ai_plan_candidates already returns a JSON array. Never aggregate it into a second array.
create or replace function public.ai_context(p_args jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); m public.media; c public.checkins; d date; zone text; selected uuid:=nullif(p_args->>'plan_id','')::uuid; plans jsonb;
begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 if not exists(select 1 from public.profiles where id=u and deletion_requested_at is null) then raise exception using errcode='42501',message='账号正在删除'; end if;
 zone:=app.timezone_for(u); d:=(now() at time zone zone)::date;
 if nullif(p_args->>'media_id','') is not null then
  select * into m from public.media where id=(p_args->>'media_id')::uuid and user_id=u and deleted_at is null;
  if not found then raise exception using errcode='42501',message='照片已不可用'; end if;
  if m.checkin_id is null then return jsonb_build_object('awaiting_confirmation',true); end if;
  select * into c from public.checkins where id=m.checkin_id and user_id=u;
  if not found then raise exception using errcode='42501',message='记录已不可用'; end if;
  zone:=c.timezone; d:=m.local_date; selected:=c.plan_id;
 end if;
 plans:=public.ai_plan_candidates(u,coalesce(c.local_date,d),p_selected=>selected);
 if jsonb_array_length(plans)>=25 and selected is null then plans:='[]'; end if;
 return jsonb_build_object('timezone',zone,'local_date',d,'plans',plans,'checkin_id',c.id,'record_version',c.version,
 'photo_revision',coalesce((m.metadata->'byok'->>'revision')::int,0),'scope_team_id',app.team_for(u),
 'created_at',c.created_at,'source',m.source,'batch_id',m.batch_id,'result',m.metadata->'byok');
end $$;

