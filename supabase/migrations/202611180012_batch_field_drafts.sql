-- User edits made while ALL classification is pending have no implicit plan owner.
-- Keep one private draft rather than copying a duration into several groups.
create table public.batch_field_drafts (
 checkin_id uuid primary key references public.checkins(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 batch_id uuid not null, fields jsonb not null check(jsonb_typeof(fields)='array'), summary text not null default ''
);
alter table public.batch_field_drafts enable row level security;
grant select on public.batch_field_drafts to authenticated;
grant all on public.batch_field_drafts to service_role;
create policy batch_draft_owner on public.batch_field_drafts for select to authenticated using(user_id=auth.uid());
