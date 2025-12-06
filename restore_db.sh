#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./restore_db.sh <db_name> <db_owner_user> <dump_file> [superuser]
# Example:
#   ./restore_db.sh quote quote snapshots/quote_2025-12-05_103000.dump

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 <db_name> <db_owner_user> <dump_file> [superuser]"
    exit 1
fi

DB_NAME="$1"
DB_OWNER="$2"
DUMP_FILE="$3"
SUPERUSER="${4:-${DATABASE_USER:-postgres}}"

HOST="${DATABASE_HOST:-localhost}"
PORT="${DATABASE_PORT:-5432}"

echo "[INFO] Restoring '${DB_NAME}' from ${DUMP_FILE}"

# Ensure owner role exists (optional safety)
psql -h "$HOST" -p "$PORT" -U "$SUPERUSER" -v ON_ERROR_STOP=1 -d postgres \
    -c "DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DB_OWNER}') THEN
                RAISE NOTICE 'Role ${DB_OWNER} does not exist.';
            END IF;
        END
        \$\$;"

# Terminate connections (not ours), drop, recreate
psql -h "$HOST" -p "$PORT" -U "$SUPERUSER" -v ON_ERROR_STOP=1 -d postgres \
    -c "SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();"

dropdb   -h "$HOST" -p "$PORT" -U "$SUPERUSER" "$DB_NAME" || true
createdb -h "$HOST" -p "$PORT" -U "$SUPERUSER" -O "$DB_OWNER" "$DB_NAME"

# Restore:
#   --no-owner: make restored objects owned by the role running pg_restore (DB_OWNER)
#   -c: clean (drop) before recreating objects within the DB
pg_restore -h "$HOST" -p "$PORT" -U "$DB_OWNER" -d "$DB_NAME" -c --no-owner "$DUMP_FILE"

echo "✅ Restore complete for '${DB_NAME}'"
