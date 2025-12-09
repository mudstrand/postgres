#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <host> <port> <admin_user> <admin_password> <value>"
    exit 1
fi

PGHOST="$1"
PGPORT="$2"
PGUSER="$3"
PGPASSWORD="$4"
VALUE="$5"
export PGHOST PGPORT PGUSER PGPASSWORD

if [[ ! "$VALUE" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Error: <value> must be a valid SQL identifier (letters/digits/_ and not starting with a digit)."
    exit 2
fi

DB="$VALUE"
PW="$VALUE"

PSQLOPTS="-v ON_ERROR_STOP=1 -X -q"

# 1) Role: create if not exists (supported in PG 9.6+), then ensure LOGIN + password
# If your server is older than 9.6, the CREATE ROLE IF NOT EXISTS will fail; the || true will swallow only that failure.
psql $PSQLOPTS -d postgres <<SQL || true
CREATE ROLE "$VALUE";
SQL

# Ensure LOGIN + password and membership
psql $PSQLOPTS -d postgres <<SQL
ALTER ROLE "$VALUE" LOGIN PASSWORD '$PW';
SQL

# 2) Database: create if not exists, then ensure owner
psql $PSQLOPTS -d postgres <<SQL || true
CREATE DATABASE "$DB" OWNER "$VALUE";
SQL

psql $PSQLOPTS -d postgres <<SQL
ALTER DATABASE "$DB" OWNER TO "$VALUE";
SQL

# 3) Schema + grants + default privileges in the target DB
# Create schema; ignore error if exists, then ensure owner
psql $PSQLOPTS -d "$DB" <<SQL || true
CREATE SCHEMA "$VALUE" AUTHORIZATION "$VALUE";
SQL

psql $PSQLOPTS -d "$DB" <<SQL
ALTER SCHEMA "$VALUE" OWNER TO "$VALUE";

GRANT USAGE, CREATE ON SCHEMA "$VALUE" TO "$VALUE";
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA "$VALUE" TO "$VALUE";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA "$VALUE" TO "$VALUE";
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA "$VALUE" TO "$VALUE";

SET ROLE "$VALUE";
ALTER DEFAULT PRIVILEGES IN SCHEMA "$VALUE" GRANT ALL ON TABLES    TO "$VALUE";
ALTER DEFAULT PRIVILEGES IN SCHEMA "$VALUE" GRANT ALL ON SEQUENCES TO "$VALUE";
ALTER DEFAULT PRIVILEGES IN SCHEMA "$VALUE" GRANT ALL ON FUNCTIONS TO "$VALUE";
RESET ROLE;
SQL

echo "Done.
-    Database: $DB
-    Role/User: $VALUE (password: $PW)
-    Schema: $VALUE (owned by $VALUE)
"
