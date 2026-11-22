-- Media metadata is only trusted after the media function inspects the bytes.
-- A client must not invoke a timestamp/hash reservation RPC directly.
revoke all on function public.reserve_photo(uuid,uuid,text,text,text,timestamptz,text,jsonb) from authenticated;

alter table public.teams alter column owner_id drop not null;
alter table public.teams drop constraint teams_owner_id_fkey;
alter table public.teams add constraint teams_owner_id_fkey foreign key(owner_id) references public.profiles(id) on delete set null;
alter table public.invites drop constraint invites_created_by_fkey;
alter table public.invites add constraint invites_created_by_fkey foreign key(created_by) references public.profiles(id) on delete cascade;

create function public.prepare_account_deletion() returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); begin
 if u is null then raise exception using errcode='28000',message='请先登录'; end if;
 update public.team_members set left_at=now() where team_id in(select id from public.teams where owner_id=u) and left_at is null;
 update public.invites set revoked_at=now() where team_id in(select id from public.teams where owner_id=u);
 update public.teams set dissolved_at=now() where owner_id=u;
 update public.team_members set left_at=now() where user_id=u and left_at is null;
end $$;
revoke all on function public.prepare_account_deletion() from public,anon;
grant execute on function public.prepare_account_deletion() to authenticated;
