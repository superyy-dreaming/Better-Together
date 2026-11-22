-- API keys are encrypted by the Edge Function; no client can read this table.
create table public.ai_settings (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 enabled boolean not null default false,
 base_url text not null check (char_length(base_url) between 9 and 2048),
 protocol text not null check (protocol in ('responses','chat_completions')),
 model text not null check (char_length(model) between 1 and 200),
 key_ciphertext text not null check (char_length(key_ciphertext) between 24 and 12000),
 key_iv text not null check (char_length(key_iv)=16),
 key_version integer not null default 1 check (key_version=1),
 updated_at timestamptz not null default now()
);
alter table public.ai_settings enable row level security;
revoke all on public.ai_settings from public,anon,authenticated;
grant all on public.ai_settings to service_role;

create function app.guard_ai_settings_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.profiles where id=new.user_id and deletion_requested_at is null for share;
 if not found then raise exception '账号正在删除，无法保存 AI 配置'; end if;
 return new;
end $$;
create trigger active_owner_before_ai_settings before insert or update on public.ai_settings for each row execute function app.guard_ai_settings_owner();
revoke all on function app.guard_ai_settings_owner() from public,anon,authenticated;
