-- Run these in psql as a superuser (e.g., postgres)

-- 1) Create role (login) if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'quote') THEN
        CREATE ROLE quote LOGIN PASSWORD 'quote';
    END IF;
END$$;

-- 2) Create the database (standalone statement)
-- If it might already exist, you can ignore the error or check first with:
--   SELECT 1 FROM pg_database WHERE datname = 'quote';
CREATE DATABASE quote OWNER quote;

-- 3) Connect to the new database
\c quote

-- 4) Ensure the public schema is owned by the quote role
ALTER SCHEMA public OWNER TO quote;

-- 5) Tighten PUBLIC and grant to quote
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO quote;

-- Done. Then set your env for Alembic/SQLAlchemy (psycopg3 driver):
--   export DATABASE_URL="postgresql+psycopg://quote:quote@localhost:5432/quote"
-- And run:
--   alembic revision --autogenerate -m "initial schema"
--   alembic upgrade head
