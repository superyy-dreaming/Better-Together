-- Leaving ends the sharing period permanently, even if a person later rejoins.
create function app.in_sharing_period(p_team uuid,p_user uuid,p_at timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.team_members where team_id=p_team and user_id=p_user and left_at is null and joined_at<=p_at)
$$;
create or replace function app.can_checkin(p_id uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.checkins c where c.id=p_id and (c.user_id=p_user or (c.visibility='team' and app.in_sharing_period(c.team_id,p_user,c.created_at) and app.in_sharing_period(c.team_id,c.user_id,c.created_at))))
$$;
create or replace function app.can_report(p_id uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reports r where r.id=p_id and (r.user_id=p_user or (app.in_sharing_period(r.team_id,p_user,r.generated_at) and (r.kind='team' or (r.shared and app.in_sharing_period(r.team_id,r.user_id,r.generated_at))))))
$$;
drop policy reports_read on public.reports;
create policy reports_read on public.reports for select to authenticated using(user_id=auth.uid() or (kind='team' and app.can_report(id,auth.uid())));
drop policy overdue_read on public.overdue_feed;
create policy overdue_read on public.overdue_feed for select to authenticated using(user_id=auth.uid() or (app.in_sharing_period(team_id,auth.uid(),synced_at) and app.in_sharing_period(team_id,user_id,synced_at)));
revoke all on function app.in_sharing_period(uuid,uuid,timestamptz) from public,anon;
grant execute on function app.in_sharing_period(uuid,uuid,timestamptz) to authenticated;
drop policy avatars_read on storage.objects;
create policy avatars_read on storage.objects for select to authenticated using(bucket_id='avatars' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.profiles p where p.id::text=(storage.foldername(name))[1] and app.team_for(p.id)=app.team_for(auth.uid()))));
