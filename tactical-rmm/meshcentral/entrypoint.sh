#!/usr/bin/env bash
#
# MeshCentral entrypoint for Tactical RMM.
#
# Adapted from the upstream tactical-meshcentral entrypoint with the MongoDB
# back end replaced by PostgreSQL. The data store is selected at runtime:
#
#   - MESH_POSTGRES_HOST unset/empty (the default): no database block is written,
#     so MeshCentral falls back to its built-in NeDB store under
#     /home/node/app/meshcentral-data/. This is the zero-dependency layout used
#     by the Docker Compose example, so no external database container is needed.
#   - MESH_POSTGRES_HOST set: a "postgres" block is written under settings,
#     matching the PostgreSQL layout the upstream install.sh provisions. Used by
#     staging and production.

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
: "${MESH_POSTGRES_HOST:=}"
: "${MESH_POSTGRES_PORT:=5432}"
: "${MESH_POSTGRES_USER:=meshcentral}"
: "${MESH_POSTGRES_PASS:=}"
: "${MESH_POSTGRES_DATABASE:=meshcentral}"

# When MESH_POSTGRES_HOST is set, emit a "postgres" settings block so MeshCentral
# stores its data in PostgreSQL. Left empty, MeshCentral uses its built-in NeDB
# store. The block is placed as the first key in "settings" so its trailing comma
# stays valid regardless of the keys that follow.
mesh_db_settings=""
if [ -n "${MESH_POSTGRES_HOST}" ]; then
  mesh_db_settings=$(cat <<EOF
"postgres": {
      "user": "${MESH_POSTGRES_USER}",
      "password": "${MESH_POSTGRES_PASS}",
      "host": "${MESH_POSTGRES_HOST}",
      "port": "${MESH_POSTGRES_PORT}",
      "database": "${MESH_POSTGRES_DATABASE}"
    },
EOF
)
fi

if [ ! -f "/home/node/app/meshcentral-data/config.json" ] || [[ "${MESH_PERSISTENT_CONFIG}" -eq 0 ]]; then
  cat >/home/node/app/meshcentral-data/config.json <<EOF
{
  "settings": {
    ${mesh_db_settings}
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
