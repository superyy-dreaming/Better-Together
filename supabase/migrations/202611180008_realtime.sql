-- Supabase creates this publication. Plain PostgreSQL tests intentionally omit it.
do $$ declare tab text; begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  foreach tab in array array['profiles','teams','team_members','plans','checkins','media','interactions','report_interactions','overdue_feed','pokes','reports','notifications'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=tab) then
    execute format('alter publication supabase_realtime add table public.%I',tab);
   end if;
  end loop;
 end if;
end $$;
