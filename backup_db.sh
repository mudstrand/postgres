#!/usr/bin/env bash
set -euo pipefail

# ========= Configuration =========
# Connection (override via env if needed)
HOST="${DATABASE_HOST:-localhost}"
PORT="${DATABASE_PORT:-5432}"
BACKUP_USER="${DATABASE_USER:-postgres}"

# Output directory and retention
OUTDIR="${1:-snapshots}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Optional: explicit DB list via env, space-separated (e.g., "couch quote")
DB_LIST="${DB_LIST:-}"

# Optional: absolute paths for binaries. If not provided, auto-detect.
# For Homebrew on macOS (Apple Silicon), you can set:
#   export PSQL_BIN=/opt/homebrew/opt/libpq/bin/psql
#   export PG_DUMP_BIN=/opt/homebrew/opt/libpq/bin/pg_dump
PSQL_BIN="${PSQL_BIN:-}"
PG_DUMP_BIN="${PG_DUMP_BIN:-}"

# ========= Helpers =========
timestamp() { date +%F_%H%M%S; }
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# Resolve client binaries or fail fast
if [[ -z "$PSQL_BIN" ]]; then
    PSQL_BIN="$(command -v psql || true)"
fi
if [[ -z "$PG_DUMP_BIN" ]]; then
    PG_DUMP_BIN="$(command -v pg_dump || true)"
fi

if [[ -z "$PSQL_BIN" || -z "$PG_DUMP_BIN" ]]; then
    fail "psql/pg_dump not found in PATH. Install PostgreSQL client tools or set PSQL_BIN/PG_DUMP_BIN to absolute paths."
fi

# Ensure output directory exists
mkdir -p "${OUTDIR}"

# Discover databases if not provided:
# Excludes template0, template1, and the default 'postgres' db.
discover_databases() {
    "$PSQL_BIN" -h "$HOST" -p "$PORT" -U "$BACKUP_USER" -Atc \
        "SELECT datname
         FROM pg_database
         WHERE NOT datistemplate
           AND datname <> 'postgres'
         ORDER BY datname;"
}

# ========= Main =========
declare -a DBS
if [[ -z "${DB_LIST}" ]]; then
    log "Discovering databases on ${HOST}:${PORT} as ${BACKUP_USER}..."
    if ! mapfile -t DBS < <(discover_databases); then
        fail "Failed to discover databases. Check connectivity, credentials, and permissions."
    fi
else
    # Split DB_LIST into array
    read -r -a DBS <<< "${DB_LIST}"
fi

if [[ "${#DBS[@]}" -eq 0 ]]; then
    log "No databases found to back up. Exiting."
    exit 0
fi

log "Databases to back up: ${DBS[*]}"
STAMP="$(timestamp)"

# Perform backups
for DB in "${DBS[@]}"; do
    OUTFILE="${OUTDIR}/${DB}_${STAMP}.dump"
    log "Backing up '${DB}' → ${OUTFILE}"
    if ! "$PG_DUMP_BIN" -Fc -h "$HOST" -p "$PORT" -U "$BACKUP_USER" -d "$DB" -f "$OUTFILE"; then
        fail "Backup failed for database '${DB}'."
    fi
    log "Completed '${DB}'"
done

# Retention: delete files older than RETENTION_DAYS
log "Applying retention: keep ${RETENTION_DAYS} days in ${OUTDIR}"
find "${OUTDIR}" -type f -name '*.dump' -mtime +$((RETENTION_DAYS - 1)) -print -delete || true

log "All done."
exit 0
