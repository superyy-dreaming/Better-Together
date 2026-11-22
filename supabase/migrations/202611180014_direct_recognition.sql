-- Only the backend can read temporary analysis pixels or verified AI results.
create table public.media_analysis (
 media_id uuid primary key references public.media(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 data_url text check (data_url is null or (octet_length(data_url)<=3*1024*1024 and data_url ~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$')),
 result jsonb check (result is null or coalesce(jsonb_typeof(result)='object' and jsonb_typeof(result->'assignments')='array' and jsonb_typeof(result->'groups')='array',false)),
 screenshot_date text check (screenshot_date is null or screenshot_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
 recognition_status text not null default 'pending' check (recognition_status in ('pending','ready','rejected')),
 expires_at timestamptz not null default now()+interval '24 hours',
 created_at timestamptz not null default now(),
 check (expires_at>created_at and expires_at<=created_at+interval '24 hours'),
 check (recognition_status<>'ready' or result is not null)
);
alter table public.media_analysis enable row level security;
revoke all on public.media_analysis from public,anon,authenticated;
grant select,insert,update,delete on public.media_analysis to service_role;
create index media_analysis_expiry on public.media_analysis(expires_at) where data_url is not null;

create function app.guard_media_analysis_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.media_id<>old.media_id or new.user_id<>old.user_id or new.created_at<>old.created_at or new.expires_at<>old.expires_at) then
  raise exception '分析缓存归属和有效期不可更改';
 end if;
 -- Retiring pixels is always permitted; dependency outages or account deletion
 -- must not prevent expiration. All other writes recheck the live owner.
 if tg_op='UPDATE' and new.data_url is null and (to_jsonb(new)-'data_url')=(to_jsonb(old)-'data_url') then return new; end if;
 perform 1 from public.profiles where id=new.user_id and deletion_requested_at is null for share;
 if not found then raise exception '账号正在删除，无法保存分析缓存'; end if;
 perform 1 from public.media where id=new.media_id and user_id=new.user_id and deleted_at is null for share;
 if not found then raise exception '分析缓存与照片归属不符或照片已删除'; end if;
 if new.created_at>now()+interval '1 minute' then raise exception '分析缓存创建时间无效'; end if;
 if new.data_url is not null and new.expires_at<=now() then raise exception '分析图已过期，请重新选择照片'; end if;
 return new;
end $$;
create trigger live_owner_before_media_analysis before insert or update on public.media_analysis for each row execute function app.guard_media_analysis_owner();
revoke all on function app.guard_media_analysis_owner() from public,anon,authenticated;

-- delete_photo is a soft delete, so an FK alone would retain the pixel cache.
create function app.remove_deleted_media_analysis() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.deleted_at is not null and old.deleted_at is null then delete from public.media_analysis where media_id=new.id; end if;
 return new;
end $$;
create trigger clear_deleted_media_analysis after update of deleted_at on public.media for each row execute function app.remove_deleted_media_analysis();
revoke all on function app.remove_deleted_media_analysis() from public,anon,authenticated;

create function public.clear_expired_media_analysis() returns integer language plpgsql security definer set search_path='' as $$
declare cleared integer; begin
 update public.media_analysis set data_url=null where data_url is not null and expires_at<=now();
 get diagnostics cleared=row_count;
 return cleared;
end $$;
revoke all on function public.clear_expired_media_analysis() from public,anon,authenticated;
grant execute on function public.clear_expired_media_analysis() to service_role;

-- pHash protects visually equal supplied analysis images; the original hash
-- separately prevents resubmitting the same original with a different thumbnail.
alter table public.media add constraint media_original_sha256_format check (
 not (metadata ? 'original_sha256') or
 (jsonb_typeof(metadata->'original_sha256')='string' and metadata->>'original_sha256' ~ '^[0-9a-f]{64}$')
);
create unique index evidence_team_original_sha256 on public.media(coalesce(team_id,user_id),(metadata->>'original_sha256')) where metadata ? 'original_sha256';

-- A tied/unclassified batch stays private until its owner confirms a plan.
create or replace function public.apply_ai_result(p_checkin_id uuid,p_result jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.checkins; a jsonb; g jsonb; pid uuid; newid uuid; groupids uuid[]:='{}'; memo_fields jsonb; category text; target record; assigned uuid[]; grouped uuid[]; defer_fields boolean:=false; defer_summary boolean:=false; direct_batch boolean:=false; partial_result boolean:=false; private_result boolean:=false; begin
 select * into c from public.checkins where id=p_checkin_id for update;
 if not found then return jsonb_build_object('applied',false,'reason','missing'); end if;
 if c.version<>coalesce((p_result->>'version')::int,0) or (c.user_edited and not c.classification_pending) or (c.memo_status<>'pending' and not c.classification_pending) then return jsonb_build_object('applied',false,'reason','version_changed'); end if;
 if not exists(select 1 from public.jobs where id=(p_result->>'job_id')::uuid and lease_token=(p_result->>'lease_token')::uuid and status='processing' and lease_until>now() and payload->>'checkin_id'=c.id::text and kind='ai') then return jsonb_build_object('applied',false,'reason','lease_changed'); end if;
 direct_batch:=exists(select 1 from public.media m join public.media_analysis ma on ma.media_id=m.id where m.checkin_id=c.id and m.deleted_at is null);
 partial_result:=direct_batch and coalesce((p_result->>'partial')::boolean,false);
 private_result:=direct_batch and c.plan_id is null and (coalesce((p_result->>'privacy_required')::boolean,false) or exists(
  select 1 from public.media m join public.media_analysis ma on ma.media_id=m.id cross join lateral jsonb_array_elements(ma.result->'assignments') cached_assignment
  join public.plans p on p.id::text=cached_assignment->>'plan_id' where m.checkin_id=c.id and m.deleted_at is null and p.visibility='private'
 ));
 if jsonb_typeof(p_result->'assignments') is distinct from 'array' or jsonb_typeof(p_result->'groups') is distinct from 'array' then raise exception 'AI assignments schema mismatch'; end if;
 assigned:=array(select (value->>'photo_id')::uuid from jsonb_array_elements(p_result->'assignments'));
 if cardinality(assigned)<>(select count(distinct x) from unnest(assigned) x) or cardinality(assigned)<>(select count(*) from public.media where checkin_id=c.id and deleted_at is null)
 or exists(select 1 from unnest(assigned) x where not exists(select 1 from public.media where id=x and checkin_id=c.id and deleted_at is null)) then raise exception 'AI assignments must cover every photo exactly once'; end if;
 for a in select value from jsonb_array_elements(p_result->'assignments') loop
  pid:=nullif(a->>'plan_id','')::uuid;
  if c.plan_id is not null and pid is distinct from c.plan_id then raise exception 'AI cannot override selected plan'; end if;
  if partial_result and c.plan_id is null and pid is not null then raise exception 'Partial recognition must remain ALL'; end if;
  if pid is not null and not exists(select 1 from public.plans where id=pid and user_id=c.user_id) then raise exception 'AI plan not owned by member'; end if;
  if (a->>'confidence')::numeric not between 0 and 1 then raise exception 'AI confidence outside range'; end if;
  update public.media set plan_id=pid,confidence=(a->>'confidence')::numeric where id=(a->>'photo_id')::uuid and checkin_id=c.id;
 end loop;
 if direct_batch and jsonb_array_length(p_result->'groups')<>1 then raise exception 'Direct recognition must produce one aggregate group'; end if;
 grouped:=array(select jsonb_array_elements_text(value->'photo_ids')::uuid from jsonb_array_elements(p_result->'groups'));
 if cardinality(grouped)<>cardinality(assigned) or cardinality(grouped)<>(select count(distinct x) from unnest(grouped) x) or not grouped @> assigned then raise exception 'AI groups must cover every photo exactly once'; end if;
 if (select count(*) from jsonb_array_elements(p_result->'groups'))<>(select count(distinct coalesce(value->>'plan_id','ALL')) from jsonb_array_elements(p_result->'groups')) then raise exception 'AI groups must be unique by plan'; end if;
 defer_fields:=c.user_edited and jsonb_array_length(c.fields)>0 and jsonb_array_length(p_result->'groups')>1;
 -- A later pass must not mistake a partial AI summary for the original note.
 defer_summary:=c.plan_id is null and char_length(trim(c.summary))>0 and (not direct_batch or c.memo_status='pending' or c.user_edited);
 for g in select value from jsonb_array_elements(p_result->'groups') loop
  pid:=nullif(g->>'plan_id','')::uuid;
  if exists(select 1 from jsonb_array_elements_text(g->'photo_ids') photo where not exists(select 1 from public.media where id=photo::uuid and checkin_id=c.id and plan_id is not distinct from pid)) then raise exception 'AI group conflicts with assignment'; end if;
 end loop;
 for target in select distinct m.plan_id from public.media m where m.checkin_id=c.id and m.deleted_at is null loop
  pid:=target.plan_id;
  if cardinality(groupids)=0 then newid:=c.id;
  else
   insert into public.checkins(user_id,team_id,plan_id,batch_id,local_date,timezone,status,is_makeup,is_late,summary,fields,memo_status,visibility,team_size,created_at)
   values(c.user_id,c.team_id,pid,c.batch_id,c.local_date,c.timezone,c.status,c.is_makeup,c.is_late,'','[]','pending','private',c.team_size,c.created_at) returning id into newid;
  end if;
  update public.media set checkin_id=newid where checkin_id=c.id and plan_id is not distinct from pid;
  select value into g from jsonb_array_elements(p_result->'groups') where nullif(value->>'plan_id','')::uuid is not distinct from pid;
  category:=coalesce((select p.category from public.plans p where id=pid),'all');
  if c.user_edited and not app.validate_fields(c.fields,category) then defer_fields:=true; end if;
  memo_fields:=case when c.user_edited and defer_fields then '[]'::jsonb when c.user_edited then c.fields else g->'fields' end;
  if not app.validate_fields(memo_fields,category) then raise exception 'AI fields violate source/range rules'; end if;
  update public.checkins set plan_id=pid,visibility=case when private_result then 'private' else coalesce((select visibility from public.plans where id=pid),'private') end,
   is_late=case when c.redo_of is null and not c.is_makeup and pid is not null then (c.created_at at time zone c.timezone)::time>(select deadline from public.plans where id=pid) else c.is_late end,
   summary=case when c.user_edited and not defer_summary then c.summary else left(coalesce(g->>'summary',''),4000) end,fields=memo_fields,user_edited=c.user_edited,memo_status='ready',classification_pending=partial_result or pid is null,version=version+case when partial_result then 0 else 1 end where id=newid;
  update public.overdue_feed set status='resolved' where plan_id=pid and local_date=c.local_date and user_id=c.user_id;
  groupids:=array_append(groupids,newid);
 end loop;
 if defer_fields or defer_summary then
  insert into public.batch_field_drafts(checkin_id,user_id,batch_id,fields,summary)
  values(c.id,c.user_id,c.batch_id,case when defer_fields then c.fields else '[]'::jsonb end,case when defer_summary then c.summary else '' end)
  on conflict(checkin_id) do update set fields=excluded.fields,summary=excluded.summary where not direct_batch;
 end if;
 return jsonb_build_object('applied',true,'checkin_ids',to_jsonb(groupids));
end $$;
