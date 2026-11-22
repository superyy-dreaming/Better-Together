-- One service-only transaction owns both the original reference and retry cache.
-- A lost HTTP response can be safely replayed with exactly the same identity.
create function public.register_direct_media(p_media jsonb,p_analysis jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 mid uuid:=(p_media->>'id')::uuid;
 owner_id uuid:=(p_media->>'user_id')::uuid;
 batch uuid:=(p_media->>'batch_id')::uuid;
 team uuid:=nullif(p_media->>'team_id','')::uuid;
 m public.media;
 expires timestamptz;
begin
 if mid is null or owner_id is null or batch is null
 or coalesce(jsonb_typeof(p_media->'metadata')<>'object',true)
 or coalesce(p_media->'metadata'->>'original_sha256' !~ '^[0-9a-f]{64}$',true)
 or coalesce(p_media->'metadata'->>'analysis_sha256' !~ '^[0-9a-f]{64}$',true)
 or p_media->'metadata'->>'image_mode' is distinct from 'direct'
 or coalesce(p_media->>'path' not in (owner_id||'/'||batch||'/'||mid||'.jpg',owner_id||'/'||batch||'/'||mid||'.png'),true)
 then raise exception using errcode='PT409',message='照片上传身份不完整'; end if;
 -- app_action/account deletion share the owner lock. A separate photo lock also
 -- serializes conflicting identities across owners without relying on a pre-read.
 perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended(mid::text,2));
 perform 1 from public.profiles where id=owner_id and deletion_requested_at is null for share;
 if not found then raise exception using errcode='PT409',message='账号正在删除，无法继续上传'; end if;
 if team is distinct from app.team_for(owner_id) then raise exception using errcode='PT409',message='小队归属已变化，请重新选择照片'; end if;
 if (p_media->>'local_date')::date is distinct from (now() at time zone app.timezone_for(owner_id))::date then
  raise exception using errcode='PT410',message='这次上传已过期';
 end if;
 select * into m from public.media where id=mid for update;
 if found then
  if m.user_id is distinct from owner_id or m.batch_id is distinct from batch
  or m.team_id is distinct from team or m.path is distinct from p_media->>'path'
  or m.source is distinct from p_media->>'source' or m.local_date is distinct from (p_media->>'local_date')::date
  or m.phash is distinct from p_media->>'phash' or m.deleted_at is not null
  or m.metadata->>'original_sha256' is distinct from p_media->'metadata'->>'original_sha256'
  or m.metadata->>'analysis_sha256' is distinct from p_media->'metadata'->>'analysis_sha256'
  then raise exception using errcode='PT409',message='照片上传标识与已有内容不符'; end if;
 else
  insert into public.media(id,user_id,team_id,batch_id,path,source,captured_at,local_date,phash,metadata,analysis_path)
  values(mid,owner_id,team,batch,p_media->>'path',p_media->>'source',(p_media->>'captured_at')::timestamptz,
   (p_media->>'local_date')::date,p_media->>'phash',p_media->'metadata',null) returning * into m;
 end if;
 -- Replays never downgrade a ready result or refresh its retention deadline.
 if not exists(select 1 from public.media_analysis where media_id=mid) then
  expires:=m.created_at+interval '24 hours';
  if expires<=now() then raise exception using errcode='PT410',message='分析缓存恢复期限已过'; end if;
  insert into public.media_analysis(media_id,user_id,data_url,result,screenshot_date,recognition_status,created_at,expires_at)
  values(mid,owner_id,p_analysis->>'data_url',nullif(p_analysis->'result','null'::jsonb),p_analysis->>'screenshot_date',
   coalesce(p_analysis->>'recognition_status','pending'),m.created_at,expires);
 end if;
 return jsonb_build_object('id',m.id,'path',m.path,'captured_at',m.captured_at,'source',m.source);
end $$;
revoke all on function public.register_direct_media(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.register_direct_media(jsonb,jsonb) to service_role;
