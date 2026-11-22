-- Preserve single-record makeup and stamp-notification semantics for the new
-- multi-record transaction. This is additive; deployed migrations stay intact.
alter function public.app_action(text,jsonb) rename to app_action_before_batch_finalize;
create function public.app_action(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; cid uuid; u uuid:=auth.uid(); cached jsonb;
begin
 if p_action='submit_checkin_batch' then
  if u is null then raise exception using errcode='28000',message='请先登录'; end if;
  perform pg_advisory_xact_lock(hashtextextended(u::text,0));
  select s.result into cached from public.submissions s where s.user_id=u and s.idempotency_key=p_args->>'idempotency_key';
  if found then return cached; end if;
  if nullif(p_args->>'redo_of','') is null
   and coalesce(nullif(p_args->>'target_date','')::date,(now() at time zone app.timezone_for(u))::date)<>(now() at time zone app.timezone_for(u))::date
   and jsonb_typeof(p_args->'groups')='array'
   and exists(select 1 from jsonb_array_elements(p_args->'groups') g where nullif(g->>'plan_id','') is null)
  then raise exception '补卡时请选择原计划'; end if;
 end if;
 result:=public.app_action_before_batch_finalize(p_action,p_args);
 if p_action='submit_checkin_batch' then
  for cid in select jsonb_array_elements_text(result->'checkin_ids')::uuid loop
   perform app.notify(u,'stamp','已盖章','记录已保留，可在详情查看对应照片和纪要。',cid,'stamp:'||cid);
  end loop;
 end if;
 return result;
end $$;
revoke all on function public.app_action_before_batch_finalize(text,jsonb) from public,anon,authenticated;
revoke all on function public.app_action(text,jsonb) from public,anon;
grant execute on function public.app_action(text,jsonb) to authenticated;
