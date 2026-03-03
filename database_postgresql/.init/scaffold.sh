#!/usr/bin/env bash
set -euo pipefail
# Scaffold migrations and a robust run_migrations helper for price_history
WORKSPACE="/home/kavia/workspace/code-generation/price-comparison-hub-327751/database_postgresql"
mkdir -p "$WORKSPACE/migrations" && cd "$WORKSPACE"
# schema.sql (idempotent)
cat > "$WORKSPACE/migrations/schema.sql" <<'SQL'
BEGIN;
CREATE TABLE IF NOT EXISTS price_history (
  id SERIAL PRIMARY KEY,
  product_id TEXT NOT NULL UNIQUE,
  price NUMERIC(12,2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  recorded_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
COMMIT;
SQL
# seed.sql (idempotent)
cat > "$WORKSPACE/migrations/seed.sql" <<'SQL'
INSERT INTO price_history (product_id, price, currency) VALUES
('sku-001', 19.99, 'USD'),
('sku-002', 5.49, 'USD')
ON CONFLICT (product_id) DO NOTHING;
SQL
# run_migrations.sh helper (robust checks, idempotent)
cat > "$WORKSPACE/run_migrations.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# Robust migration runner:
# - Waits for Postgres readiness with exponential backoff
# - Checks psql exit codes and sanitizes outputs
# - Creates database if missing (requires POSTGRES_USER to have CREATE DATABASE or be superuser)
# - Applies migrations with ON_ERROR_STOP
WORKSPACE="/home/kavia/workspace/code-generation/price-comparison-hub-327751/database_postgresql"
[ -f /etc/profile.d/price_comp_dev.sh ] && source /etc/profile.d/price_comp_dev.sh
PGHOST="${PGHOST:-localhost}"; PGPORT="${PGPORT:-5432}"; PGUSER="${POSTGRES_USER:-postgres}"; PGDB="${POSTGRES_DB:-dev_db}"
# Wait for postgres readiness with exponential backoff
MAX_RETRIES=6; BASE_SLEEP=1
i=0
until pg_isready -h "$PGHOST" -p "$PGPORT" >/dev/null 2>&1; do
  i=$((i+1))
  if [ "$i" -ge "$MAX_RETRIES" ]; then
    echo "postgres not ready on $PGHOST:$PGPORT after $i attempts" >&2
    exit 2
  fi
  sleep $((BASE_SLEEP * i))
done
# Helper to run psql and capture output and exit code
run_psql() {
  local db="$1"; shift
  # Keep PGPASSWORD optional; do not persist secret here
  PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" -v ON_ERROR_STOP=1 "$@"
}
# Check database existence
COUNT_RAW=$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -t -A -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_database WHERE datname = '$PGDB';" 2>/dev/null || true)
if [ -z "${COUNT_RAW:-}" ]; then
  # If empty, treat as 0 (but ensure we surfaced psql failure earlier)
  COUNT=0
else
  COUNT=$(printf '%s' "$COUNT_RAW" | tr -d '[:space:]')
fi
if [ -z "$COUNT" ]; then COUNT=0; fi
if [ "$COUNT" -eq 0 ]; then
  # Attempt to create DB. This requires that PGUSER has CREATE DATABASE privilege or is superuser.
  if ! PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$PGDB\";" 2>/dev/null; then
    echo "failed to create database $PGDB (ensure $PGUSER has CREATE DATABASE privilege or run as superuser)" >&2
    exit 4
  fi
fi
# Apply schema then seed with ON_ERROR_STOP
if ! PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 -f "$WORKSPACE/migrations/schema.sql"; then
  echo "applying schema failed" >&2
  exit 5
fi
if ! PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 -f "$WORKSPACE/migrations/seed.sql"; then
  echo "applying seed failed" >&2
  exit 6
fi
echo "migrations applied to $PGDB@${PGHOST}:${PGPORT}"
BASH
chmod +x "$WORKSPACE/run_migrations.sh"

# Ensure migrations and helper exist and are executable
ls -l "$WORKSPACE/migrations" || true
ls -l "$WORKSPACE/run_migrations.sh" || true
