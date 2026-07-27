#!/usr/bin/env bash
#
# tactical-backend entrypoint.
#
# A full replacement for the upstream Tactical RMM entrypoint rather than a
# wrapper around it. Upstream stages the Django tree in /tmp/tactical and rsyncs
# it into a shared /opt/tactical volume on every start, which forces every
# service to mount a volume over the whole application directory and makes each
# restart pay for the copy, a recursive chown, and every management command.
#
# Here the tree is baked into the image at its final path and only mutable state
# is mounted. The upstream entrypoint's hash is pinned in the Dockerfile so a
# TRMM_VERSION bump that changes its init sequence fails the build.
#
# Configuration lives in TACTICAL_CONF_DIR, a small mounted volume, in two
# classes. generated_settings.py is rewritten from the environment on every run.
# local_settings.py and app.ini are seeded once and never touched again, so they
# are the operator's to edit or bind-mount; TRMM_PERSISTENT_CONFIG=0 restores the
# upstream regenerate-every-time behavior.
#
# api/nats-rmm.conf and api/nats-api.conf are symlinks into the conf directory,
# so the management commands that write to settings.BASE_DIR land there
# unmodified.

set -e

: "${TACTICAL_DIR:=/opt/tactical}"
: "${TACTICAL_CONF_DIR:=${TACTICAL_DIR}/conf}"
: "${TACTICAL_TEMPLATE_DIR:=${TACTICAL_DIR}/templates}"
: "${TACTICAL_READY_FILE:=${TACTICAL_DIR}/tmp/tactical.ready}"
: "${TACTICAL_LAYOUT_FILE:=${TACTICAL_DIR}/.image-layout}"
: "${TACTICAL_USER:=tactical}"

# 1 seeds app.ini and local_settings.py only when absent, so operator edits
# survive. 0 regenerates both on every init, which is what upstream did.
: "${TRMM_PERSISTENT_CONFIG:=1}"

# 1 runs the full init even when the recorded state already matches this image.
: "${TRMM_FORCE_INIT:=0}"

: "${TRMM_USER:=tactical}"
: "${TRMM_PASS:=tactical}"
: "${POSTGRES_HOST:=tactical-postgres}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=tactical}"
: "${POSTGRES_PASS:=tactical}"
: "${POSTGRES_DB:=tacticalrmm}"
: "${MESH_SERVICE:=tactical-meshcentral}"
: "${MESH_WS_URL:=ws://${MESH_SERVICE}:4443}"
: "${MESH_USER:=meshcentral}"
: "${MESH_PASS:=meshcentralpass}"
: "${MESH_HOST:=tactical-meshcentral}"
: "${API_HOST:=tactical-backend}"
: "${APP_HOST:=tactical-frontend}"
: "${REDIS_HOST:=tactical-redis}"
: "${TRMM_DISABLE_WEB_TERMINAL:=False}"
: "${TRMM_DISABLE_SERVER_SCRIPTS:=False}"
: "${TRMM_DISABLE_SSO:=False}"

: "${CERT_PRIV_PATH:=${TACTICAL_DIR}/certs/privkey.pem}"
: "${CERT_PUB_PATH:=${TACTICAL_DIR}/certs/fullchain.pem}"

: "${MESH_POSTGRES_HOST:=${POSTGRES_HOST}}"
: "${MESH_POSTGRES_PORT:=5432}"
: "${MESH_POSTGRES_USER:=meshcentral}"
: "${MESH_POSTGRES_PASS:=}"
: "${MESH_POSTGRES_DATABASE:=meshcentral}"

# A volume mounted over /opt/tactical hides the baked application tree, which is
# exactly what the pre-layout-2 compose file did with tactical-data. Fail here
# with the fix rather than several steps later with "manage.py: not found".
if [ ! -f "${TACTICAL_LAYOUT_FILE}" ]; then
	cat >&2 <<EOF
FATAL: ${TACTICAL_LAYOUT_FILE} is missing.

The application tree is baked into the image at ${TACTICAL_DIR}. A volume
mounted over that directory hides it. The single tactical-data volume was
replaced by per-purpose volumes (conf, tmp, private, certs, reporting, static);
see the Tactical RMM migration section in the repository README.
EOF
	exit 1
fi

# Take ownership of state paths init created or wrote, skipping anything it
# cannot write. A plain `chown -R` aborts on an operator-supplied read-only bind
# mount with EROFS, and under set -e that kills init into a restart loop; those
# files are deliberately supplied and are not init's to own anyway. `chown -f`
# is not the fix: it silences the message but still exits non-zero.
function chown_state {
	find "$@" ! -user 1000 -writable -exec chown 1000:1000 {} +
}

function wait_for_tcp {
	local host="$1" port="$2" label="$3"
	until (echo >/dev/tcp/"${host}"/"${port}") &>/dev/null; do
		echo "waiting for ${label} to be ready..."
		sleep 1
	done
}

# Fallback only. compose.example.yml gates these services on tactical-init with
# depends_on/service_completed_successfully, which is an ordering guarantee this
# poll cannot give: the ready file persists in a volume, so a service that starts
# before init has deleted it would sail straight past. Upstream's leading
# "sleep 15" was there to make that window unlikely, and it cost every service up
# to 25 seconds on every start.
function check_tactical_ready {
	until [ -f "${TACTICAL_READY_FILE}" ]; do
		echo "waiting for init container to finish install or update..."
		sleep 1
	done
}

# PostgreSQL is the only MeshCentral data store in these images. MeshCentral
# creates its own tables inside an existing database but never the database or
# the login role; on a bare-metal install upstream install.sh provisions them
# with psql, and in the container stack there is no such step. Runs before the
# wait on MeshCentral below, so the mesh container can connect as soon as the
# database exists.
function provision_mesh_database {
	echo "Provisioning MeshCentral PostgreSQL database on ${MESH_POSTGRES_HOST}:${MESH_POSTGRES_PORT}..."

	wait_for_tcp "${MESH_POSTGRES_HOST}" "${MESH_POSTGRES_PORT}" "postgresql server"

	# Every statement is idempotent so the repeated tactical-init runs on stack
	# restarts and upgrades are safe. psycopg (v3) ships in the API virtualenv,
	# so no psql client binary is required.
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
}

# Named volumes are seeded from the image, so these already exist in the default
# deployment. Recreated here so a bind-mounted empty host directory works too.
function ensure_state_dirs {
	mkdir -p \
		"${TACTICAL_CONF_DIR}" \
		"${TACTICAL_DIR}/tmp" \
		"${TACTICAL_DIR}/certs" \
		"${TACTICAL_DIR}/reporting/assets" \
		"${TACTICAL_DIR}/api/static" \
		"${TACTICAL_DIR}/api/tacticalrmm/private/exe" \
		"${TACTICAL_DIR}/api/tacticalrmm/private/log"
	touch "${TACTICAL_DIR}/api/tacticalrmm/private/log/django_debug.log"

	# Scoped to the mount points, all of which are small. Upstream chowns the
	# whole tree including the Django source and community-scripts, which is a
	# large part of its restart cost; the baked tree is already owned correctly.
	chown_state \
		"${TACTICAL_CONF_DIR}" \
		"${TACTICAL_DIR}/tmp" \
		"${TACTICAL_DIR}/certs" \
		"${TACTICAL_DIR}/reporting" \
		"${TACTICAL_DIR}/api/tacticalrmm/private" \
		"${TACTICAL_DIR}/api/static"
}

# Written by the mesh container once MeshCentral has minted a login token key.
# Upstream reads it with a bare cat, so a mesh container that never got that far
# kills init under set -e with an opaque "No such file or directory".
function wait_for_mesh_token {
	until [ -s "${TACTICAL_DIR}/tmp/mesh_token" ]; do
		echo "waiting for tactical-meshcentral to write ${TACTICAL_DIR}/tmp/mesh_token..."
		sleep 1
	done
}

# True when a config file should be seeded: it is absent, or persistence is off.
# A file that exists but is not writable is a read-only bind mount, which is a
# supported way to supply one, so it is left alone rather than treated as an
# error.
function should_seed {
	local target="$1"

	if [ ! -e "${target}" ]; then
		return 0
	fi
	if [ "${TRMM_PERSISTENT_CONFIG}" != "0" ]; then
		return 1
	fi
	if [ ! -w "${target}" ]; then
		echo "${target} is not writable, leaving it as supplied"
		return 1
	fi
	return 0
}

# Rewritten on every init from the environment. Operator overrides belong in
# ${TACTICAL_CONF_DIR}/local_settings.py, which local_settings.py in the image
# loads after this file, or in TRMM_SETTING_* variables, which win over both.
function write_generated_settings {
	local mesh_token base_domain

	mesh_token=$(cat "${TACTICAL_DIR}/tmp/mesh_token")
	base_domain=$(echo "import tldextract; no_fetch_extract = tldextract.TLDExtract(suffix_list_urls=()); extracted = no_fetch_extract('${API_HOST}'); print(f'{extracted.domain}.{extracted.suffix}')" | python)

	: "${SESSION_COOKIE_DOMAIN:=$base_domain}"
	: "${CSRF_COOKIE_DOMAIN:=$base_domain}"

	cat >"${TACTICAL_CONF_DIR}/generated_settings.py" <<EOF
# Generated by tactical-init on every run. Edits here are lost.
# Put operator settings in local_settings.py beside this file instead.

DOCKER_BUILD = True

CERT_FILE = '${CERT_PUB_PATH}'
KEY_FILE = '${CERT_PRIV_PATH}'

EXE_DIR = '${TACTICAL_DIR}/api/tacticalrmm/private/exe'
LOG_DIR = '${TACTICAL_DIR}/api/tacticalrmm/private/log'

SCRIPTS_DIR = '${TACTICAL_DIR}/community-scripts'

ALLOWED_HOSTS = ['${API_HOST}', '${APP_HOST}', 'tactical-backend']

CORS_ORIGIN_WHITELIST = ['https://${APP_HOST}']

SESSION_COOKIE_DOMAIN = '${SESSION_COOKIE_DOMAIN}'
CSRF_COOKIE_DOMAIN = '${CSRF_COOKIE_DOMAIN}'
CSRF_TRUSTED_ORIGINS = ['https://${API_HOST}', 'https://${APP_HOST}']

HEADLESS_FRONTEND_URLS = {'socialaccount_login_error': 'https://${APP_HOST}/account/provider/callback'}

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '${POSTGRES_DB}',
        'USER': '${POSTGRES_USER}',
        'PASSWORD': '${POSTGRES_PASS}',
        'HOST': '${POSTGRES_HOST}',
        'PORT': '${POSTGRES_PORT}',
    }
}

MESH_USERNAME = '${MESH_USER}'
MESH_SITE = 'https://${MESH_HOST}'
MESH_TOKEN_KEY = '${mesh_token}'
REDIS_HOST = '${REDIS_HOST}'
MESH_WS_URL = '${MESH_WS_URL}'
TRMM_DISABLE_WEB_TERMINAL = ${TRMM_DISABLE_WEB_TERMINAL}
TRMM_DISABLE_SERVER_SCRIPTS = ${TRMM_DISABLE_SERVER_SCRIPTS}
TRMM_DISABLE_SSO = ${TRMM_DISABLE_SSO}
EOF
}

# Seeded once and never rewritten, so operator edits survive a restart. Holds the
# values that must stay stable across restarts rather than track the environment:
# SECRET_KEY above all, which upstream regenerated on every init, silently
# invalidating every session and logging every user out.
function seed_local_settings {
	local target="${TACTICAL_CONF_DIR}/local_settings.py"
	local adminurl django_sekret

	if ! should_seed "${target}"; then
		echo "Keeping existing ${target}"
		return
	fi

	echo "Seeding ${target}"
	adminurl=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 70 | head -n 1)
	django_sekret=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 80 | head -n 1)

	cat >"${target}" <<EOF
# Operator-owned Django settings, seeded once by tactical-init and never
# rewritten. Edits survive a restart. Loaded after generated_settings.py, so
# anything set here beats the generated value; TRMM_SETTING_* env vars beat both.
#
# Set TRMM_PERSISTENT_CONFIG=0 to have tactical-init regenerate this file.

SECRET_KEY = '${django_sekret}'

# Randomized at seed time so the Django admin is not at a guessable path.
ADMIN_URL = '${adminurl}/'
ADMIN_ENABLED = False

DEBUG = False
EOF
}

# uwsgi's own config, replacing manage.py create_uwsgi_conf. Seeded from the
# template baked into the image; see the comments in that file for why the
# defaults differ from the ones upstream generated.
function seed_app_ini {
	local target="${TACTICAL_CONF_DIR}/app.ini"

	if ! should_seed "${target}"; then
		echo "Keeping existing ${target}"
		return
	fi

	echo "Seeding ${target} from ${TACTICAL_TEMPLATE_DIR}/app.ini"
	cp "${TACTICAL_TEMPLATE_DIR}/app.ini" "${target}"
}

# The ready file is a copy of the image's layout marker, so it records both the
# layout revision and TRMM_VERSION. Matching means this exact image already
# finished an init against this state, and the upgrade-shaped work can be
# skipped. Upstream writes the literal string "tactical-init" here, which carries
# no such information, so it re-ran everything on every start.
#
# The marker only changes with TRMM_VERSION or the layout revision, so rebuilding
# the image without bumping either (a changed entrypoint, a changed app.ini
# template) still takes the short path. Nothing in the long path is needed for
# those, but TRMM_FORCE_INIT=1 forces it when you want it anyway, which beats
# telling people to delete a file out of a named volume.
function init_is_current {
	[ "${TRMM_FORCE_INIT}" = "1" ] && return 1
	[ -f "${TACTICAL_READY_FILE}" ] || return 1
	cmp --silent "${TACTICAL_READY_FILE}" "${TACTICAL_LAYOUT_FILE}"
}

# Everything that only has to happen on a first run or a version change. Ordering
# is upstream's and matters: pre_update_tasks before migrate, and
# generate_json_schemas before collectstatic because it writes into
# STATICFILES_DIRS.
function run_full_init {
	python manage.py pre_update_tasks
	python manage.py migrate --no-input
	python manage.py generate_json_schemas
	python manage.py get_webtar_url >"${TACTICAL_DIR}/tmp/web_tar_url"
	python manage.py collectstatic --no-input
	python manage.py initial_db_setup
	python manage.py initial_mesh_setup
	python manage.py load_chocos
	python manage.py load_community_scripts
	python manage.py reload_nats
	python manage.py create_natsapi_conf
	python manage.py create_installer_user
	python manage.py clear_redis_celery_locks
	python manage.py post_update_tasks

	echo "Creating dashboard user if it doesn't exist"
	echo "from accounts.models import User; User.objects.create_superuser('${TRMM_USER}', 'admin@example.com', '${TRMM_PASS}') if not User.objects.filter(username='${TRMM_USER}').exists() else 0;" | python manage.py shell
}

# A strict subsequence of run_full_init, in the same relative order. migrate stays
# in even though it is a no-op round trip, so a hand-applied database change is
# still caught. get_webtar_url stays because tactical-frontend reads web_tar_url
# on every start. The nats configs are regenerated because they are derived from
# the agent list, and clear_redis_celery_locks because the locks are stale by
# definition after a stop.
function run_warm_init {
	python manage.py migrate --no-input
	python manage.py get_webtar_url >"${TACTICAL_DIR}/tmp/web_tar_url"
	python manage.py reload_nats
	python manage.py create_natsapi_conf
	python manage.py clear_redis_celery_locks
}

case "$1" in
tactical-init)
	if init_is_current; then
		init_mode=warm
		echo "State matches this image ($(tr '\n' ' ' <"${TACTICAL_LAYOUT_FILE}")); running the short init."
	else
		init_mode=full
		echo "First run, or layout/version change; running the full init."
	fi

	test -f "${TACTICAL_READY_FILE}" && rm "${TACTICAL_READY_FILE}"

	ensure_state_dirs
	provision_mesh_database

	wait_for_tcp "${POSTGRES_HOST}" "${POSTGRES_PORT}" "postgresql container"

	# Only the full path needs MeshCentral itself: initial_mesh_setup opens a
	# websocket to it. The warm path needs nothing but the token file, which is
	# already in the tmp volume from the previous run, so it does not wait for a
	# mesh container that is still booting. That wait is the single largest part
	# of a restart, because mesh in turn waits on nginx before it listens.
	if [ "${init_mode}" = full ]; then
		wait_for_tcp "${MESH_SERVICE}" 4443 "meshcentral container"
	fi
	wait_for_mesh_token

	# Order matters: the seeded local_settings.py must exist before any management
	# command imports Django settings, because it carries SECRET_KEY.
	write_generated_settings
	seed_local_settings
	seed_app_ini

	if [ "${init_mode}" = full ]; then
		run_full_init
	else
		run_warm_init
	fi

	# init runs as root so it can take ownership of freshly created volumes, which
	# means everything it just wrote is root-owned: the generated configs, the
	# collectstatic output, and the Django log files the management commands open
	# (trmm_debug.log in particular, which the backend cannot append to as uid 1000
	# and which fails the whole uwsgi app load, not just logging). Every state
	# mount point is covered, and only those: upstream chowns the entire tree
	# including the Django source and community-scripts, which is a large part of
	# its restart cost.
	chown_state \
		"${TACTICAL_CONF_DIR}" \
		"${TACTICAL_DIR}/tmp" \
		"${TACTICAL_DIR}/certs" \
		"${TACTICAL_DIR}/reporting" \
		"${TACTICAL_DIR}/api/static" \
		"${TACTICAL_DIR}/api/tacticalrmm/private"

	echo "Creating install ready file"
	cp "${TACTICAL_LAYOUT_FILE}" "${TACTICAL_READY_FILE}"
	chown 1000:1000 "${TACTICAL_READY_FILE}"
	;;

tactical-backend)
	check_tactical_ready
	uwsgi "${TACTICAL_CONF_DIR}/app.ini"
	;;

tactical-celery)
	check_tactical_ready
	celery -A tacticalrmm worker --autoscale=20,2 -l info
	;;

tactical-celerybeat)
	check_tactical_ready
	test -f "${TACTICAL_DIR}/api/celerybeat.pid" && rm "${TACTICAL_DIR}/api/celerybeat.pid"
	celery -A tacticalrmm beat -l info
	;;

tactical-websockets)
	check_tactical_ready
	export DJANGO_SETTINGS_MODULE=tacticalrmm.settings
	uvicorn --host 0.0.0.0 --port 8383 --forwarded-allow-ips='*' tacticalrmm.asgi:application
	;;

*)
	echo "unknown command: $1" >&2
	echo "expected one of: tactical-init tactical-backend tactical-celery tactical-celerybeat tactical-websockets" >&2
	exit 1
	;;
esac
