#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/better-together-db.XXXXXX")"
cleanup() {
  pg_ctl -D "$test_dir/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf -- "$test_dir"
}
trap cleanup EXIT
initdb -D "$test_dir/data" -A trust --no-locale >/dev/null
# A private Unix socket avoids collisions and never connects to any real project.
pg_ctl -D "$test_dir/data" -l "$test_dir/server.log" -o "-k $test_dir -h '' -p 55439" start >/dev/null
psql_args=(-h "$test_dir" -p 55439 -d postgres -v ON_ERROR_STOP=1)
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/bootstrap.sql"
for migration in "$project_root"/supabase/migrations/*.sql; do
  [[ "${migration##*/}" > "202611210019" ]] && continue
  psql "${psql_args[@]}" -q -f "$migration"
done
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/integration.sql"
if [ -f "$project_root/supabase/tests/hardening.sql" ]; then
  psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/hardening.sql"
fi
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/rules.sql"
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/review.sql"
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/ai_settings.sql"
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/direct_recognition.sql"
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/media_registration.sql"
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/short_invites.sql"
psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/flexible_schedules.sql"
bash "$project_root/supabase/tests/media_registration_concurrency.sh" "${psql_args[@]}"

# Retain historical migration checks, then validate the additive BYOK schema.
for migration in "$project_root"/supabase/migrations/*.sql; do
  [[ "${migration##*/}" < "202611210020" ]] && continue
  psql "${psql_args[@]}" -q -f "$migration"
done
for suite in integration rules review media_registration short_invites flexible_schedules byok period_targets batch_checkins; do
  if [ -f "$project_root/supabase/tests/$suite.sql" ]; then
    psql "${psql_args[@]}" -q -f "$project_root/supabase/tests/$suite.sql"
  fi
done
bash "$project_root/supabase/tests/media_registration_concurrency.sh" "${psql_args[@]}"
