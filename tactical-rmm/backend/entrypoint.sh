#!/usr/bin/env bash
#
# tactical-backend entrypoint wrapper.
#
# The backend image ships the upstream Tactical RMM entrypoint unmodified (copied
# to /entrypoint-upstream.sh). This wrapper adds one step ahead of it: when the
# tactical-init command runs it provisions the MeshCentral database and role on
# the shared PostgreSQL server, then delegates to the upstream entrypoint with the
# original arguments.
#
# PostgreSQL is the only MeshCentral data store in these images. MeshCentral only
# creates its own tables inside an existing database; it does not create the
# database or the login role. On a bare-metal install the upstream install.sh
# provisions them with psql; in the container stack there is no such step, so
# tactical-init does it here. Provisioning happens before the upstream entrypoint
# waits for MeshCentral, so the mesh container (restart: always) can connect as
# soon as the database exists.
#
# The mesh database lives on the same PostgreSQL server as the tacticalrmm
# database, administered by POSTGRES_USER/POSTGRES_PASS. MESH_POSTGRES_HOST
# defaults to POSTGRES_HOST (tactical-postgres), matching the tacticalrmm DB host.

set -e

: "${POSTGRES_USER:=tactical}"
: "${POSTGRES_PASS:=tactical}"
: "${POSTGRES_HOST:=tactical-postgres}"
: "${MESH_POSTGRES_HOST:=${POSTGRES_HOST}}"
: "${MESH_POSTGRES_PORT:=5432}"
: "${MESH_POSTGRES_USER:=meshcentral}"
: "${MESH_POSTGRES_PASS:=}"
: "${MESH_POSTGRES_DATABASE:=meshcentral}"

if [ "$1" = 'tactical-init' ]; then
  echo "Provisioning MeshCentral PostgreSQL database on ${MESH_POSTGRES_HOST}:${MESH_POSTGRES_PORT}..."

  until (echo >/dev/tcp/"${MESH_POSTGRES_HOST}"/"${MESH_POSTGRES_PORT}") &>/dev/null; do
    echo "waiting for postgresql server to be ready..."
    sleep 5
  done

  # Connect to the server as the tactical superuser and create the MeshCentral
  # role and database if they are absent. Every statement is idempotent so the
  # repeated tactical-init runs on stack restarts and upgrades are safe. psycopg
  # (v3) ships in the API virtualenv, so no psql client binary is required.
  MESH_POSTGRES_HOST="${MESH_POSTGRES_HOST}" \
  MESH_POSTGRES_PORT="${MESH_POSTGRES_PORT}" \
  MESH_POSTGRES_USER="${MESH_POSTGRES_USER}" \
  MESH_POSTGRES_PASS="${MESH_POSTGRES_PASS}" \
  MESH_POSTGRES_DATABASE="${MESH_POSTGRES_DATABASE}" \
  POSTGRES_USER="${POSTGRES_USER}" \
  POSTGRES_PASS="${POSTGRES_PASS}" \
  python <<'PYEOF'
import os

import psycopg
from psycopg import sql

host = os.environ["MESH_POSTGRES_HOST"]
port = os.environ["MESH_POSTGRES_PORT"]
admin_user = os.environ["POSTGRES_USER"]
admin_pass = os.environ["POSTGRES_PASS"]
role = os.environ["MESH_POSTGRES_USER"]
password = os.environ["MESH_POSTGRES_PASS"]
database = os.environ["MESH_POSTGRES_DATABASE"]

role_id = sql.Identifier(role)

# Server-level objects: create the role and database against the maintenance
# database. autocommit is required because CREATE DATABASE cannot run inside a
# transaction block.
with psycopg.connect(
    host=host, port=port, user=admin_user, password=admin_pass,
    dbname="postgres", autocommit=True,
) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,))
        if cur.fetchone():
            cur.execute(sql.SQL("ALTER ROLE {} WITH LOGIN PASSWORD {}").format(role_id, sql.Literal(password)))
        else:
            cur.execute(sql.SQL("CREATE ROLE {} WITH LOGIN PASSWORD {}").format(role_id, sql.Literal(password)))

        cur.execute(sql.SQL("ALTER ROLE {} SET client_encoding TO 'utf8'").format(role_id))
        cur.execute(sql.SQL("ALTER ROLE {} SET default_transaction_isolation TO 'read committed'").format(role_id))
        cur.execute(sql.SQL("ALTER ROLE {} SET timezone TO 'UTC'").format(role_id))

        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (database,))
        if not cur.fetchone():
            cur.execute(sql.SQL("CREATE DATABASE {} OWNER {}").format(sql.Identifier(database), role_id))
        cur.execute(sql.SQL("GRANT ALL PRIVILEGES ON DATABASE {} TO {}").format(sql.Identifier(database), role_id))

# Schema-level grants are scoped to the target database, so they must run on a
# connection to the mesh database rather than the maintenance database.
with psycopg.connect(
    host=host, port=port, user=admin_user, password=admin_pass,
    dbname=database, autocommit=True,
) as conn:
    with conn.cursor() as cur:
        cur.execute(sql.SQL("GRANT USAGE, CREATE ON SCHEMA public TO {}").format(role_id))

print("MeshCentral PostgreSQL database provisioned.")
PYEOF
fi

exec /entrypoint-upstream.sh "$@"
