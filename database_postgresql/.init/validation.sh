#!/usr/bin/env bash
set -euo pipefail
# validation - apply migrations, run smoke test, and show concise evidence
WORKSPACE="/home/kavia/workspace/code-generation/price-comparison-hub-327751/database_postgresql"
# load non-secret defaults if present
[ -f /etc/profile.d/price_comp_dev.sh ] && source /etc/profile.d/price_comp_dev.sh
# verify required tools
command -v psql >/dev/null 2>&1 || { echo "psql not found" >&2; exit 10; }
command -v pg_isready >/dev/null 2>&1 || { echo "pg_isready not found" >&2; exit 11; }
PGHOST="${PGHOST:-localhost}"; PGPORT="${PGPORT:-5432}"; PGUSER="${POSTGRES_USER:-postgres}"; PGDB="${POSTGRES_DB:-dev_db}"
# Ensure migrations helper exists and is executable
if [ -x "${WORKSPACE}/run_migrations.sh" ]; then
  bash "${WORKSPACE}/run_migrations.sh"
else
  echo "run_migrations.sh missing or not executable" >&2; exit 30
fi
# Run canonical smoke test: prefer ${WORKSPACE}/test
if [ -x "${WORKSPACE}/test" ]; then
  bash "${WORKSPACE}/test"
elif [ -f "${WORKSPACE}/test" ]; then
  bash "${WORKSPACE}/test"
else
  echo "smoke test script not found at ${WORKSPACE}/test" >&2; exit 40
fi
# Print concise machine-readable evidence (top 3 rows). Requires POSTGRES_PASSWORD env if DB requires it.
PSQL_CMD=(psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDB}" -t -A -c)
# run query, propagate exit code on failure
PGPASSWORD="${POSTGRES_PASSWORD:-}" "${PSQL_CMD[@]}" "SELECT id||','||product_id||','||price||','||recorded_at FROM price_history ORDER BY recorded_at DESC LIMIT 3;" || { echo "validation evidence query failed" >&2; exit 31; }
echo "validation: OK"
