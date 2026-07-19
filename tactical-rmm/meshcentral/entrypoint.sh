#!/usr/bin/env bash
#
# MeshCentral entrypoint for Tactical RMM.
#
# Adapted from the upstream tactical-meshcentral entrypoint with the MongoDB
# back end replaced by PostgreSQL. PostgreSQL is the only data store: a "postgres"
# block is always written under settings, matching the layout the upstream
# install.sh provisions. MESH_POSTGRES_HOST defaults to tactical-postgres, the
# same PostgreSQL server as the tacticalrmm database.

set -e

: "${MESH_USER:=meshcentral}"
: "${MESH_PASS:=meshcentralpass}"
: "${NGINX_HOST_IP:=tactical-nginx}"
: "${NGINX_HOST_PORT:=4443}"
: "${MESH_COMPRESSION_ENABLED:=false}"
: "${MESH_PERSISTENT_CONFIG:=0}"
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

if [ ! -f "/home/node/app/meshcentral-data/config.json" ] || [[ "${MESH_PERSISTENT_CONFIG}" -eq 0 ]]; then
  cat >/home/node/app/meshcentral-data/config.json <<EOF
{
  "settings": {
    "postgres": {
      "user": "${MESH_POSTGRES_USER}",
      "password": "${MESH_POSTGRES_PASS}",
      "host": "${MESH_POSTGRES_HOST}",
      "port": "${MESH_POSTGRES_PORT}",
      "database": "${MESH_POSTGRES_DATABASE}"
    },
    "cert": "${MESH_HOST}",
    "tlsOffload": "${NGINX_HOST_IP}",
    "redirPort": 8080,
    "WANonly": true,
    "minify": 1,
    "port": 4443,
    "agentAliasPort": 443,
    "aliasPort": 443,
    "allowLoginToken": true,
    "allowFraming": true,
    "agentPing": 35,
    "allowHighQualityDesktop": true,
    "agentCoreDump": false,
    "compression": ${MESH_COMPRESSION_ENABLED},
    "wsCompression": ${MESH_COMPRESSION_ENABLED},
    "agentWsCompression": ${MESH_COMPRESSION_ENABLED},
    "webRTC": ${MESH_WEBRTC_ENABLED},
    "maxInvalidLogin": {
      "time": 5,
      "count": 5,
      "coolofftime": 30
    }
  },
  "domains": {
    "": {
      "title": "Tactical RMM",
      "title2": "TacticalRMM",
      "newAccounts": false,
      "mstsc": true,
      "geoLocation": true,
      "certUrl": "https://${NGINX_HOST_IP}:${NGINX_HOST_PORT}",
      "agentConfig": [ "webSocketMaskOverride=${WS_MASK_OVERRIDE}" ]
    }
  },
  "smtp": {
    "host": "${SMTP_HOST}",
    "port": ${SMTP_PORT},
    "from": "${SMTP_FROM}",
    "user": "${SMTP_USER}",
    "pass": "${SMTP_PASS}",
    "tls": ${SMTP_TLS}
  }
}
EOF
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
