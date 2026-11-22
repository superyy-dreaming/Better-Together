alter table public.profiles add column deletion_requested_at timestamptz;
create or replace function public.prepare_account_deletion() returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 update public.profiles set deletion_requested_at=coalesce(deletion_requested_at,now()) where id=u;
 update public.team_members set left_at=now() where team_id in(select id from public.teams where owner_id=u) and left_at is null;
 update public.invites set revoked_at=now() where team_id in(select id from public.teams where owner_id=u);
 update public.teams set dissolved_at=now() where owner_id=u;
 update public.team_members set left_at=now() where user_id=u and left_at is null;
 update public.jobs set status='dead',lease_token=null,lease_until=null,last_error='ACCOUNT_DELETION' where status in ('queued','processing') and
  (payload->>'checkin_id' in(select id::text from public.checkins where user_id=u) or payload->>'report_id' in(select id::text from public.reports where user_id=u));
 update public.push_outbox set status='dead',lease_token=null,lease_until=null,error='ACCOUNT_DELETION' where user_id=u and status in ('queued','processing');
end $$;
create function app.guard_storage_owner() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_id uuid; deleting timestamptz; begin
 if new.bucket_id not in ('evidence','avatars') then return new; end if;
 owner_id:=split_part(new.name,'/',1)::uuid;
 select deletion_requested_at into deleting from public.profiles where id=owner_id for share;
 if not found or deleting is not null then raise exception '账号正在删除，无法继续上传'; end if;
 return new;
end $$;
create trigger active_owner_before_storage before insert or update on storage.objects for each row execute function app.guard_storage_owner();
create function app.guard_media_owner() returns trigger language plpgsql security definer set search_path='' as $$
declare deleting timestamptz; begin
 select deletion_requested_at into deleting from public.profiles where id=new.user_id for share;
 if not found or deleting is not null then raise exception '账号正在删除，无法继续上传'; end if;
 return new;
end $$;
create trigger active_owner_before_media before insert on public.media for each row execute function app.guard_media_owner();
revoke all on function app.guard_storage_owner(),app.guard_media_owner() from public,anon,authenticated;
