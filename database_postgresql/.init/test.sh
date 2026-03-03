#!/usr/bin/env bash
set -euo pipefail
# concise psql smoke test for connectivity and numeric-safe CRUD
WORKSPACE="/home/kavia/workspace/code-generation/price-comparison-hub-327751/database_postgresql"
[ -f /etc/profile.d/price_comp_dev.sh ] && source /etc/profile.d/price_comp_dev.sh
PGHOST="${PGHOST:-localhost}"; PGPORT="${PGPORT:-5432}"; PGUSER="${POSTGRES_USER:-postgres}"; PGDB="${POSTGRES_DB:-dev_db}"
if [ -z "${POSTGRES_PASSWORD:-}" ]; then echo "POSTGRES_PASSWORD must be set in environment for non-interactive auth" >&2; exit 20; fi
RETRIES=6; SLEEP=1
for i in $(seq 1 $RETRIES); do
  pg_isready -h "$PGHOST" -p "$PGPORT" >/dev/null 2>&1 && break || sleep $((SLEEP * i))
done
pg_isready -h "$PGHOST" -p "$PGPORT" >/dev/null 2>&1 || { echo "postgres not ready on $PGHOST:$PGPORT" >&2; exit 21; }
# Apply migrations (must exist in workspace)
if [ ! -x "$WORKSPACE/run_migrations.sh" ]; then
  if [ -f "$WORKSPACE/run_migrations.sh" ]; then
    bash "$WORKSPACE/run_migrations.sh"
  else
    echo "run_migrations.sh not found in workspace: $WORKSPACE" >&2
    exit 26
  fi
else
  bash "$WORKSPACE/run_migrations.sh"
fi
# Perform CRUD with numeric-safe comparisons
TEST_PRODUCT="smoke-$$"
ID=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -t -A -v ON_ERROR_STOP=1 -c "INSERT INTO price_history (product_id, price, currency) VALUES ('$TEST_PRODUCT', 1.23, 'USD') RETURNING id;")
[ -n "$ID" ] || { echo "insert failed" >&2; exit 22; }
OK=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -t -A -c "SELECT (price = CAST('1.23' AS NUMERIC))::text FROM price_history WHERE id=$ID;")
[ "${OK:-}" = "t" ] || { echo "select numeric mismatch: $OK" >&2; exit 23; }
PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 -c "UPDATE price_history SET price=2.34 WHERE id=$ID;" >/dev/null
OK2=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -t -A -c "SELECT (price = CAST('2.34' AS NUMERIC))::text FROM price_history WHERE id=$ID;")
[ "${OK2:-}" = "t" ] || { echo "update numeric mismatch: $OK2" >&2; exit 24; }
PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 -c "DELETE FROM price_history WHERE id=$ID;" >/dev/null
COUNT=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -t -A -c "SELECT count(*) FROM price_history WHERE id=$ID;")
[ "${COUNT:-0}" = "0" ] || { echo "delete failed" >&2; exit 25; }
echo "psql smoke test: OK"
