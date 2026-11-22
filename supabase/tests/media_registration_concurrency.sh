#!/usr/bin/env bash
# Called only by run.sh against its private, temporary PostgreSQL cluster.
set -euo pipefail
test_outputs="$(mktemp -d "${TMPDIR:-/tmp}/media-registration-race.XXXXXX")"
trap 'rm -rf -- "$test_outputs"' EXIT
psql "$@" -q <<'SQL'
insert into auth.users(id) values ('d0000000-0000-4000-8000-000000000001');
create table public.registration_race_input as select jsonb_build_object(
 'id','d1000000-0000-4000-8000-000000000001','user_id','d0000000-0000-4000-8000-000000000001','batch_id','d2000000-0000-4000-8000-000000000001',
 'team_id',null,'path','d0000000-0000-4000-8000-000000000001/d2000000-0000-4000-8000-000000000001/d1000000-0000-4000-8000-000000000001.jpg',
 'source','camera','captured_at',now(),'local_date',(now() at time zone 'Asia/Shanghai')::date,'phash','race-test-1',
 'metadata',jsonb_build_object('original_sha256',repeat('a',64),'analysis_sha256',repeat('b',64),'image_mode','direct')) media,
 jsonb_build_object('data_url','data:image/jpeg;base64,/9j/2Q==','recognition_status','pending') analysis;
SQL
registration_sql="begin; select public.register_direct_media(media,analysis) from public.registration_race_input; select pg_sleep(0.15); commit;"
psql "$@" -q -c "$registration_sql" > "$test_outputs/same-a.log" 2>&1 &
first_pid=$!
psql "$@" -q -c "$registration_sql" > "$test_outputs/same-b.log" 2>&1 &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
psql "$@" -q <<'SQL'
do $$ begin
 if (select count(*) from public.media where id='d1000000-0000-4000-8000-000000000001')<>1
 or (select count(*) from public.media_analysis where media_id='d1000000-0000-4000-8000-000000000001')<>1
 then raise exception 'Same identity race did not converge'; end if;
end $$;
delete from public.media where id='d1000000-0000-4000-8000-000000000001';
SQL
psql "$@" -q -v VERBOSITY=verbose -c "$registration_sql" > "$test_outputs/conflict-a.log" 2>&1 &
first_pid=$!
psql "$@" -q -v VERBOSITY=verbose -c "begin; select public.register_direct_media(jsonb_set(media,'{metadata,original_sha256}',to_jsonb(repeat('c',64))),analysis) from public.registration_race_input; select pg_sleep(0.15); commit;" > "$test_outputs/conflict-b.log" 2>&1 &
second_pid=$!
first_status=0
second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
if ! { [[ "$first_status" == 0 && "$second_status" != 0 ]] || [[ "$first_status" != 0 && "$second_status" == 0 ]]; }; then
  cat "$test_outputs/conflict-a.log" "$test_outputs/conflict-b.log"
  exit 1
fi
if ! rg -q 'PT409' "$test_outputs/conflict-a.log" "$test_outputs/conflict-b.log"; then
  cat "$test_outputs/conflict-a.log" "$test_outputs/conflict-b.log"
  exit 1
fi
psql "$@" -q <<'SQL'
do $$ begin
 if (select count(*) from public.media where id='d1000000-0000-4000-8000-000000000001')<>1
 or (select count(*) from public.media_analysis where media_id='d1000000-0000-4000-8000-000000000001')<>1
 then raise exception 'Conflicting race damaged the winner'; end if;
end $$;
drop table public.registration_race_input;
delete from auth.users where id='d0000000-0000-4000-8000-000000000001';
SQL
echo 'Concurrent media registration database tests passed'
