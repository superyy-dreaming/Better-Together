-- Apply only after deploying worker and setting JOB_SECRET in Edge Function secrets.
-- Add Vault entries better_together_url and better_together_job_secret in Dashboard.
-- Their values never belong in this file. See docs/backend-runbook.md.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
do $$ begin
 if not exists(select 1 from vault.decrypted_secrets where name='better_together_url') or not exists(select 1 from vault.decrypted_secrets where name='better_together_job_secret') then
  raise exception 'Configure Better Together URL and job secret in Vault first';
 end if;
end $$;
select cron.schedule('better-together-worker','* * * * *',$job$
 select net.http_post(
  url:=(select decrypted_secret from vault.decrypted_secrets where name='better_together_url')||'/functions/v1/worker',
  headers:=jsonb_build_object('Content-Type','application/json','x-job-secret',(select decrypted_secret from vault.decrypted_secrets where name='better_together_job_secret')),
  body:='{"kind":"all"}'::jsonb,
  timeout_milliseconds:=120000
 );
$job$);
