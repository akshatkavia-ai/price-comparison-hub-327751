#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/price-comparison-hub-327751/database_postgresql"
cd "$WORKSPACE"
# Ensure package.json exists
if [ ! -f "$WORKSPACE/package.json" ]; then
  cat > "$WORKSPACE/package.json" <<'JSON'
{ "name":"db-dev", "private":true }
JSON
fi
# Verify psql/pg_isready presence (env step dependency expects these)
if ! command -v psql >/dev/null 2>&1 || ! command -v pg_isready >/dev/null 2>&1; then
  echo "psql or pg_isready missing" >&2; exit 11
fi
# Check node/npm versions (fail fast if missing)
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "node or npm missing from image" >&2; exit 12
fi
# Parse semver-like numeric major versions (best-effort)
NODE_VER_RAW=$(node -v 2>/dev/null || echo "")
NPM_VER_RAW=$(npm -v 2>/dev/null || echo "")
# Strip leading 'v' from node
NODE_MAJOR=$(printf "%s" "$NODE_VER_RAW" | sed -E 's/^v?([0-9]+).*/\1/') || NODE_MAJOR=0
NPM_MAJOR=$(printf "%s" "$NPM_VER_RAW" | sed -E 's/^v?([0-9]+).*/\1/') || NPM_MAJOR=0
# Enforce minimums: node>=18, npm>=9 if npm version is parseable
if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
  echo "node version too old: $NODE_VER_RAW (require >=18)" >&2; exit 12
fi
if [ -n "${NPM_VER_RAW}" ] && [ "${NPM_MAJOR:-0}" -gt 0 ] && [ "${NPM_MAJOR:-0}" -lt 9 ]; then
  echo "warning: npm version is <9: $NPM_VER_RAW (recommended >=9)" >&2
fi
# Install @supabase/cli locally only if no supabase on PATH
if ! command -v supabase >/dev/null 2>&1; then
  # Use npm user-level install into workspace (local node_modules) - fail fast on errors
  npm i --no-audit --no-fund --silent @supabase/cli@latest || { echo "npm install @supabase/cli failed" >&2; exit 13; }
  PROFILE_FILE="/etc/profile.d/price_comp_dev.sh"
  # Use escaped $PATH in the file so we don't bake current PATH
  PATH_LINE="export PATH=\"$WORKSPACE/node_modules/.bin:\\$PATH\""
  # Write idempotent entry
  if [ -f "$PROFILE_FILE" ]; then
    if ! grep -Fxq "$PATH_LINE" "$PROFILE_FILE" 2>/dev/null; then
      sudo sh -c "printf '\n# include local node bin\n%s\n' '$PATH_LINE' >> $PROFILE_FILE"
      sudo chmod 644 "$PROFILE_FILE"
    fi
  else
    sudo sh -c "printf '%s\n' '# include local node bin' '$PATH_LINE' > $PROFILE_FILE"
    sudo chmod 644 "$PROFILE_FILE"
  fi
  # Source the profile to make supabase available in current shell
  # shellcheck disable=SC1091,SC1090
  source "$PROFILE_FILE"
fi
# Verify supabase is runnable (if available)
if command -v supabase >/dev/null 2>&1; then
  supabase --version >/dev/null 2>&1 || true
fi
echo "dependencies install: OK"
