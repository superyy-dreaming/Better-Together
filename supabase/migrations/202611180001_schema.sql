create extension if not exists pgcrypto with schema extensions;
create schema if not exists app;
revoke all on schema app from public;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 nickname text not null default '新同伴' check (char_length(nickname) between 1 and 40),
 avatar_url text, timezone text not null default 'Asia/Shanghai',
 notification_preferences jsonb not null default '{"all":true,"poke":true,"overdue":true,"report":true,"interaction":true,"challenge":true}',
 paused_week date, created_at timestamptz not null default now()
);
create table public.teams (
 id uuid primary key default gen_random_uuid(), name text not null check(char_length(name) between 1 and 60),
 timezone text not null, owner_id uuid not null references public.profiles(id),
 dissolved_at timestamptz, created_at timestamptz not null default now()
);
create table public.team_members (
 id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(), left_at timestamptz
);
create unique index one_active_team on public.team_members(user_id) where left_at is null;
create unique index one_active_membership on public.team_members(team_id,user_id) where left_at is null;
create table public.invites (
 id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id) on delete cascade,
 token_hash text not null unique, expires_at timestamptz not null, created_by uuid not null references public.profiles(id), revoked_at timestamptz
);
create table public.plans (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check(char_length(title) between 1 and 100), category text not null check(category in ('study','food','exercise','custom')),
 goal text not null default '', weekdays int[] not null default '{1,2,3,4,5,6,7}' check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[1,2,3,4,5,6,7]),
 start_time time not null default '08:00', deadline time not null default '21:00',
 visibility text not null default 'team' check(visibility in ('team','private')),
 status text not null default 'active' check(status in ('active','paused','ended')),
 next_config jsonb, effective_on date, created_at timestamptz not null default now(), check(start_time <= deadline)
);
create table public.checkins (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 team_id uuid references public.teams(id), plan_id uuid references public.plans(id), batch_id uuid not null,
 local_date date not null, timezone text not null,
 status text not null default 'stamped' check(status in ('stamped','redo_required','makeup','incomplete')),
 is_makeup boolean not null default false, is_late boolean not null default false,
 summary text not null default '', fields jsonb not null default '[]',
 memo_status text not null default 'pending' check(memo_status in ('pending','ready','unavailable')),
 user_edited boolean not null default false, version integer not null default 1,
 classification_pending boolean not null default false,
 redo_of uuid references public.checkins(id), redo_deadline timestamptz,
 frozen_plan_streak integer, frozen_user_streak integer,
 makeup_reason text, timer_seconds integer check(timer_seconds between 0 and 86400),
 visibility text not null default 'team' check(visibility in ('team','private')),
 team_size integer not null default 1, created_at timestamptz not null default now()
);
create index checkin_user_day on public.checkins(user_id,local_date);
create index checkin_team_day on public.checkins(team_id,local_date);
create table public.media (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 team_id uuid references public.teams(id), batch_id uuid not null, path text not null unique,
 source text not null check(source in ('camera','album','screenshot')),
 captured_at timestamptz not null, local_date date not null, phash text not null,
 checkin_id uuid references public.checkins(id) on delete cascade,
 plan_id uuid references public.plans(id), confidence numeric check(confidence between 0 and 1),
 deleted_at timestamptz, created_at timestamptz not null default now()
);
create unique index evidence_team_hash on public.media(coalesce(team_id,user_id),phash);
create table public.submissions (
 user_id uuid not null references public.profiles(id) on delete cascade, idempotency_key text not null,
 result jsonb not null, created_at timestamptz not null default now(), primary key(user_id,idempotency_key)
);
create table public.interactions (
 id uuid primary key default gen_random_uuid(), checkin_id uuid not null references public.checkins(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('like','comment','challenge')), content text not null default '',
 local_date date not null, created_at timestamptz not null default now(),
 check(kind='like' or char_length(trim(content)) between 1 and 2000)
);
create unique index one_like_or_challenge on public.interactions(checkin_id,user_id,kind) where kind in ('like','challenge');
create table public.overdue_feed (
 id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id),
 user_id uuid not null references public.profiles(id) on delete cascade, plan_id uuid not null references public.plans(id),
 local_date date not null, deadline_at timestamptz not null, synced_at timestamptz not null default now(),
 status text not null default 'open' check(status in ('open','resolved')), unique(plan_id,local_date)
);
create table public.pokes (
 overdue_id uuid not null references public.overdue_feed(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade, created_at timestamptz not null default now(), primary key(overdue_id,user_id)
);
create table public.reports (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id) on delete cascade,
 team_id uuid references public.teams(id), week_start date not null, timezone text not null,
 kind text not null check(kind in ('personal','team')), title text not null default '', summary text not null default '',
 metrics jsonb not null default '{}', highlights jsonb not null default '[]', suggestion jsonb not null default '{}',
 shared boolean not null default false, image_shared boolean not null default false, refreshed boolean not null default false,
 generated_at timestamptz not null default now(), shared_at timestamptz,
 check((kind='personal' and user_id is not null) or (kind='team' and team_id is not null))
);
create unique index report_personal_week on public.reports(user_id,week_start) where kind='personal';
create unique index report_team_week on public.reports(team_id,week_start) where kind='team';
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null, title text not null, body text not null, target_id uuid,
 read boolean not null default false, dedupe_key text not null unique, created_at timestamptz not null default now()
);
create table public.devices (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 platform text not null check(platform in ('ios','android')), provider text not null check(provider in ('apns','jpush')),
 token text not null unique, updated_at timestamptz not null default now()
);
create table public.jobs (
 id uuid primary key default gen_random_uuid(), kind text not null, payload jsonb not null,
 status text not null default 'queued' check(status in ('queued','processing','done','dead')),
 attempts integer not null default 0, available_at timestamptz not null default now(), lease_until timestamptz,
 last_error text, created_at timestamptz not null default now()
);
create table public.push_outbox (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 notification_id uuid references public.notifications(id) on delete cascade, payload jsonb not null,
 status text not null default 'queued' check(status in ('queued','processing','done','dead')),
 attempts integer not null default 0, available_at timestamptz not null default now(), lease_until timestamptz, error text,
 created_at timestamptz not null default now()
);
create table public.tag_changes (
 id uuid primary key default gen_random_uuid(), checkin_id uuid not null references public.checkins(id) on delete cascade,
 old_plan_id uuid, new_plan_id uuid not null, created_at timestamptz not null default now()
);

create or replace function app.create_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,nickname) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'nickname',''),'新同伴'),40));
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function app.create_profile();

create function app.team_for(p_user uuid) returns uuid language sql stable security definer set search_path='' as $$
 select team_id from public.team_members where user_id=p_user and left_at is null limit 1
$$;
create function app.timezone_for(p_user uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce((select t.timezone from public.teams t where t.id=app.team_for(p_user)),(select timezone from public.profiles where id=p_user),'Asia/Shanghai')
$$;
create function app.can_checkin(p_id uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.checkins c where c.id=p_id and (c.user_id=p_user or (c.visibility='team' and c.team_id=app.team_for(p_user) and c.team_id=app.team_for(c.user_id))))
$$;
create function app.can_team(p_team uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$ select p_team=app.team_for(p_user) $$;
grant usage on schema app to authenticated;
grant execute on function app.team_for(uuid), app.can_checkin(uuid,uuid), app.can_team(uuid,uuid) to authenticated;

do $$ declare t text; begin
 foreach t in array array['profiles','teams','team_members','invites','plans','checkins','media','submissions','interactions','overdue_feed','pokes','reports','notifications','devices','jobs','push_outbox','tag_changes'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or (app.team_for(id) is not null and app.team_for(id)=app.team_for(auth.uid())));
create policy teams_read on public.teams for select to authenticated using(app.can_team(id,auth.uid()));
create policy members_read on public.team_members for select to authenticated using(user_id=auth.uid() or app.can_team(team_id,auth.uid()));
create policy plans_read on public.plans for select to authenticated using(user_id=auth.uid());
create policy checkins_read on public.checkins for select to authenticated using(app.can_checkin(id,auth.uid()));
create policy media_read on public.media for select to authenticated using(user_id=auth.uid() or app.can_checkin(checkin_id,auth.uid()));
create policy interactions_read on public.interactions for select to authenticated using(app.can_checkin(checkin_id,auth.uid()));
create policy overdue_read on public.overdue_feed for select to authenticated using(user_id=auth.uid() or (app.can_team(team_id,auth.uid()) and app.can_team(team_id,user_id)));
create policy pokes_read on public.pokes for select to authenticated using(exists(select 1 from public.overdue_feed o where o.id=overdue_id));
create policy reports_read on public.reports for select to authenticated using(user_id=auth.uid() or (app.can_team(team_id,auth.uid()) and (kind='team' or (shared and app.can_team(team_id,user_id)))));
create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy devices_read on public.devices for select to authenticated using(user_id=auth.uid());
create policy tag_changes_read on public.tag_changes for select to authenticated using(app.can_checkin(checkin_id,auth.uid()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('evidence','evidence',false,20971520,array['image/jpeg','image/png','image/webp','image/heic','image/heif']),
 ('avatars','avatars',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy avatars_owner_upload on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy avatars_owner_update on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy avatars_read on storage.objects for select to authenticated using(bucket_id='avatars' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.profiles p where p.id::text=(storage.foldername(name))[1])));
-- Evidence writes and signed reads happen only through JWT-verified functions.
