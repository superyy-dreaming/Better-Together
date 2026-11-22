-- Summary completion is independent of the number of detail records downloaded.
create function app.plan_view(p_id uuid,p_day date) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(p)||coalesce(app.plan_on_day(p.id,p_day),'{}')||app.plan_progress(p.id,p_day)||jsonb_build_object(
 'streak',app.streak(p.user_id,p.id),
 'today_record_count',(select count(*) from public.checkins c where c.plan_id=p.id and c.local_date=p_day and c.status in ('stamped','makeup')),
 'today_checkin_id',(select c.id from public.checkins c where c.plan_id=p.id and c.local_date=p_day and c.status in ('stamped','makeup') order by c.created_at desc,c.id desc limit 1))
 from public.plans p where p.id=p_id
$$;
revoke all on function app.plan_view(uuid,date) from public,anon,authenticated;
alter function public.bootstrap_v2() rename to scoped_bootstrap_base;
revoke all on function public.scoped_bootstrap_base() from public,anon,authenticated;
create function public.bootstrap_v2() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:=public.scoped_bootstrap_base(); d date:=(now() at time zone app.timezone_for(auth.uid()))::date; begin
 return jsonb_set(result,'{plans}',coalesce((select jsonb_agg(app.plan_view((item->>'id')::uuid,d)) from jsonb_array_elements(result->'plans') item),'[]'));
end $$;
alter function public.read_page(jsonb) rename to scoped_read_page_base;
revoke all on function public.scoped_read_page_base(jsonb) from public,anon,authenticated;
create function public.read_page(p_args jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:=public.scoped_read_page_base(p_args); d date:=(now() at time zone app.timezone_for(auth.uid()))::date; begin
 if p_args->>'collection'='plans' then
  result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(app.plan_view((item->>'id')::uuid,d)) from jsonb_array_elements(result->'items') item),'[]'));
 elsif p_args->>'collection'='history' then
  result:=result||jsonb_build_object('calendar',coalesce((select jsonb_object_agg(local_date,n) from (select local_date,count(*) n from public.checkins where user_id=auth.uid() and local_date between d-27 and d and status in ('stamped','makeup') group by local_date) counts),'{}'));
 end if; return result;
end $$;
create or replace function public.get_plan(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.plans where id=p_id and user_id=auth.uid()) then raise exception using errcode='42501',message='计划不可见'; end if;
 return app.plan_view(p_id,(now() at time zone app.timezone_for(auth.uid()))::date);
end $$;
create function public.get_profile() returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object(
  'avatar_url',app.avatar_ref(p.id,p.avatar_url),
  'timezone',app.timezone_for(p.id),
  'paused_week',coalesce(p.paused_week=date_trunc('week',now() at time zone app.timezone_for(p.id))::date,false)
 ) from public.profiles p where id=auth.uid()
$$;
revoke all on function public.bootstrap_v2(),public.read_page(jsonb),public.get_profile() from public,anon;
grant execute on function public.bootstrap_v2(),public.read_page(jsonb),public.get_profile() to authenticated;
