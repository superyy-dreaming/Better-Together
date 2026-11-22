alter table public.media add column cleanup_status text check(cleanup_status in ('pending','done'));
create function public.complete_media_cleanup(p_media_id uuid,p_job_id uuid,p_lease_token uuid) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 perform 1 from public.jobs where id=p_job_id and kind='cleanup' and status='processing' and lease_token=p_lease_token and lease_until>now() and payload->>'media_id'=p_media_id::text for update;
 if not found then return false; end if;
 update public.media set cleanup_status='done' where id=p_media_id and deleted_at is not null;
 return true;
end $$;
revoke all on function public.complete_media_cleanup(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.complete_media_cleanup(uuid,uuid,uuid) to service_role;
