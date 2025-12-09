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

# Validate identifier
if [[ ! "$VALUE" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Error: <value> must be a valid SQL identifier (letters/digits/_ and not starting with a digit)."
    exit 2
fi

DB="$VALUE"
PW="$VALUE"

PSQLOPTS="-v ON_ERROR_STOP=1 -X -q"

# 1) Create or alter role
psql $PSQLOPTS -d postgres \
    --set=val="$VALUE" \
    --set=pw="$PW" <<'SQL'
DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_setting('psql.val')) THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L',
                       current_setting('psql.val'),
                       current_setting('psql.pw'));
    ELSE
        EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L',
                       current_setting('psql.val'),
                       current_setting('psql.pw'));
    END IF;
END
$do$;
SQL

# 2) Create database owned by the role
psql $PSQLOPTS -d postgres --set=val="$VALUE" <<'SQL'
DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = current_setting('psql.val')) THEN
        EXECUTE format('CREATE DATABASE %I OWNER %I',
                       current_setting('psql.val'),
                       current_setting('psql.val'));
    ELSE
        EXECUTE format('ALTER DATABASE %I OWNER TO %I',
                       current_setting('psql.val'),
                       current_setting('psql.val'));
    END IF;
END
$do$;
SQL

# 3) Inside that database: create schema + grants + defaults
psql $PSQLOPTS -d "$DB" --set=val="$VALUE" --set=pw="$PW" <<'SQL'
DO $do$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.schemata
        WHERE schema_name = current_setting('psql.val')
    ) THEN
        EXECUTE format('CREATE SCHEMA %I AUTHORIZATION %I',
                       current_setting('psql.val'),
                       current_setting('psql.val'));
    ELSE
        EXECUTE format('ALTER SCHEMA %I OWNER TO %I',
                       current_setting('psql.val'),
                       current_setting('psql.val'));
    END IF;

    EXECUTE format('GRANT USAGE, CREATE ON SCHEMA %I TO %I',
                   current_setting('psql.val'),
                   current_setting('psql.val'));

    EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA %I TO %I',
                   current_setting('psql.val'),
                   current_setting('psql.val'));
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I TO %I',
                   current_setting('psql.val'),
                   current_setting('psql.val'));
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA %I TO %I',
                   current_setting('psql.val'),
                   current_setting('psql.val'));
END
$do$;

-- Set default privileges as the schema owner
\set ON_ERROR_STOP on
SET ROLE :val;
ALTER DEFAULT PRIVILEGES IN SCHEMA :val GRANT ALL ON TABLES    TO :val;
ALTER DEFAULT PRIVILEGES IN SCHEMA :val GRANT ALL ON SEQUENCES TO :val;
ALTER DEFAULT PRIVILEGES IN SCHEMA :val GRANT ALL ON FUNCTIONS TO :val;
RESET ROLE;
SQL

echo "Done.
-  Database: $DB
-  Role/User: $VALUE (password: $PW)
-  Schema: $VALUE (owned by $VALUE)
"
