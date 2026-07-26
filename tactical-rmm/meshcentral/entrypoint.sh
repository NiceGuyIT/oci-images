#!/usr/bin/env bash
#
# MeshCentral entrypoint for Tactical RMM.
#
# Adapted from the upstream tactical-meshcentral entrypoint with the MongoDB
# back end replaced by PostgreSQL. PostgreSQL is the only data store: a "postgres"
# block is always written under settings, matching the layout the upstream
# install.sh provisions. MESH_POSTGRES_HOST defaults to tactical-postgres, the
# same PostgreSQL server as the tacticalrmm database.
#
# config.json is seeded from templates/config.json on first run and then left
# alone, so edits survive a restart. Upstream rewrote it on every start, which
# made the file impossible to customize. MESH_PERSISTENT_CONFIG=0 restores that
# behavior for one run.

set -e

# allexport so these reach envsubst below. It reads the environment, not shell
# variables, so a plain `: "${VAR:=default}"` would leave every value that came
# from a default rather than from compose unset at render time, and the unquoted
# JSON booleans and numbers would render as empty, producing a config.json
# MeshCentral cannot parse.
set -a

: "${MESH_USER:=meshcentral}"
: "${MESH_PASS:=meshcentralpass}"
: "${MESH_DATA_DIR:=/home/node/app/meshcentral-data}"
: "${MESH_TEMPLATE_DIR:=/home/node/app/templates}"
: "${NGINX_HOST_IP:=tactical-nginx}"
: "${NGINX_HOST_PORT:=4443}"
: "${MESH_COMPRESSION_ENABLED:=false}"
# 1 seeds config.json only when absent, so operator edits survive. 0 rewrites it
# on every start. Matches TRMM_PERSISTENT_CONFIG on the backend.
: "${MESH_PERSISTENT_CONFIG:=1}"
: "${MESH_WEBRTC_ENABLED:=false}"
: "${WS_MASK_OVERRIDE:=0}"
: "${SMTP_HOST:=smtp.example.com}"
: "${SMTP_PORT:=587}"
: "${SMTP_FROM:=mesh@example.com}"
: "${SMTP_USER:=mesh@example.com}"
: "${SMTP_PASS:=mesh-smtp-pass}"
: "${SMTP_TLS:=false}"
: "${MESH_POSTGRES_HOST:=tactical-postgres}"
: "${MESH_POSTGRES_PORT:=5432}"
: "${MESH_POSTGRES_USER:=meshcentral}"
: "${MESH_POSTGRES_PASS:=}"
: "${MESH_POSTGRES_DATABASE:=meshcentral}"

set +a

mesh_config="${MESH_DATA_DIR}/config.json"

# True when config.json should be written: it is absent, or persistence is off.
# A file that exists but is not writable is a read-only bind mount, which is a
# supported way to supply one, so it is left alone rather than treated as an
# error. Mirrors should_seed in the backend entrypoint.
should_seed() {
  local target="$1"

  if [ ! -e "${target}" ]; then
    return 0
  fi
  if [ "${MESH_PERSISTENT_CONFIG}" != "0" ]; then
    echo "Keeping existing ${target}"
    return 1
  fi
  if [ ! -w "${target}" ]; then
    echo "${target} is not writable, leaving it as supplied"
    return 1
  fi
  return 0
}

if should_seed "${mesh_config}"; then
  echo "Seeding ${mesh_config} from ${MESH_TEMPLATE_DIR}/config.json"

  # Rendered to a temporary file and validated before it is moved into place.
  # MeshCentral answers an unparseable config with "Unable to parse" and exits,
  # so a bad render is a crash loop with no useful diagnosis; worse, because the
  # file is persistent, the broken copy would then be kept on every later start.
  # Values are interpolated without JSON escaping (as they were in the heredoc
  # this replaces), so a password containing a quote or backslash lands here.
  #
  # Only the listed names are substituted, so any other $ in a value cannot be
  # expanded by accident.
  envsubst \
    '${MESH_POSTGRES_USER} ${MESH_POSTGRES_PASS} ${MESH_POSTGRES_HOST} ${MESH_POSTGRES_PORT} ${MESH_POSTGRES_DATABASE} ${MESH_HOST} ${NGINX_HOST_IP} ${NGINX_HOST_PORT} ${MESH_COMPRESSION_ENABLED} ${MESH_WEBRTC_ENABLED} ${WS_MASK_OVERRIDE} ${SMTP_HOST} ${SMTP_PORT} ${SMTP_FROM} ${SMTP_USER} ${SMTP_PASS} ${SMTP_TLS}' \
    <"${MESH_TEMPLATE_DIR}/config.json" >"${mesh_config}.tmp"

  if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${mesh_config}.tmp" 2>/tmp/mesh_config_error; then
    echo "FATAL: rendered config.json is not valid JSON" >&2
    sed -n '1,3p' /tmp/mesh_config_error >&2
    echo "Check MESH_POSTGRES_PASS and the SMTP_* values for quotes or backslashes." >&2
    rm -f "${mesh_config}.tmp"
    exit 1
  fi

  mv "${mesh_config}.tmp" "${mesh_config}"
fi

# Wait until the MeshCentral database is provisioned, not merely until the server
# answers. tactical-init creates the role, database and password; pg_isready would
# pass as soon as the server accepts connections (before that provisioning), so the
# createaccount below would fail with 28P01. A real authenticated SELECT as the mesh
# role against the mesh database only succeeds once tactical-init has finished, which
# breaks the init/mesh ordering without a compose dependency cycle.
until PGPASSWORD="${MESH_POSTGRES_PASS}" psql --host="${MESH_POSTGRES_HOST}" --port="${MESH_POSTGRES_PORT}" --username="${MESH_POSTGRES_USER}" --dbname="${MESH_POSTGRES_DATABASE}" --no-password --tuples-only --command='SELECT 1' &>/dev/null; do
  echo "waiting for meshcentral database to be provisioned by tactical-init..."
  sleep 5
done

node node_modules/meshcentral --createaccount "${MESH_USER}" --pass "${MESH_PASS}" --email example@example.com
node node_modules/meshcentral --adminaccount "${MESH_USER}"

if [ ! -f "${TACTICAL_DIR}/tmp/mesh_token" ]; then
  mesh_token=$(node node_modules/meshcentral --logintokenkey)

  if [[ ${#mesh_token} -eq 160 ]]; then
    echo "${mesh_token}" >"${TACTICAL_DIR}/tmp/mesh_token"
  else
    echo "Failed to generate mesh token. Fix the error and restart the mesh container"
  fi
fi

until (echo >/dev/tcp/"${NGINX_HOST_IP}"/"${NGINX_HOST_PORT}") &>/dev/null; do
  echo "waiting for nginx to start..."
  sleep 5
done

node node_modules/meshcentral
