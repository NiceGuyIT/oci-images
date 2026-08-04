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
#
# There is no tactical-init service any more. Each Django-bearing service runs the
# same bootstrap at startup under a PostgreSQL advisory lock (pg_lock.py), so
# whichever starts first does the work and the rest find it done. Nothing runs as
# root as a result, which removes the whole class of root-owned-file problems the
# one-shot container used to create and then chown away.

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

# Seconds any wait on another container's artifact may take before this service
# gives up and exits. Every service sets restart: always, so a bounded failure is
# a visible retry loop; an unbounded one is a deadlock that surfaces layers away.
# Sized to clear a first-run bootstrap (collectstatic, community scripts, mesh
# setup), which is the longest thing anything here waits on.
: "${TRMM_WAIT_TIMEOUT:=600}"

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

function wait_for_tcp {
	local host="$1" port="$2" label="$3" waited=0
	until (echo >/dev/tcp/"${host}"/"${port}") &>/dev/null; do
		if [ "${waited}" -ge "${TRMM_WAIT_TIMEOUT}" ]; then
			cat >&2 <<EOF
FATAL: ${label} did not accept a connection on ${host}:${port} within ${TRMM_WAIT_TIMEOUT}s.

Check that container's logs. Exiting so this restarts and stays visible instead
of blocking the startup bootstrap; raise TRMM_WAIT_TIMEOUT if the host is slow.
EOF
			exit 1
		fi
		echo "waiting for ${label} to be ready..."
		sleep 1
		waited=$((waited + 1))
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
# deployment. Recreated here so a bind-mounted host directory works too, which
# requires that directory to already be owned by uid 10000: nothing here runs as
# root any more, so there is no chown to fix it up.
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
}

# Written by the mesh container once MeshCentral has minted a login token key.
# Upstream reads it with a bare cat, so a mesh container that never got that far
# kills init under set -e with an opaque "No such file or directory".
#
# Bounded, because everything after it (generated settings, migrate, the whole
# init) is behind this wait, and this bootstrap holds the advisory lock the other
# Django services queue on. Unbounded, one missing file stalls four containers
# and reports itself as a missing database table.
function wait_for_mesh_token {
	local token_file="${TACTICAL_DIR}/tmp/mesh_token" waited=0

	until [ -s "${token_file}" ]; do
		if [ "${waited}" -ge "${TRMM_WAIT_TIMEOUT}" ]; then
			cat >&2 <<EOF
FATAL: ${token_file} was still empty or missing after ${TRMM_WAIT_TIMEOUT}s.

tactical-meshcentral writes it from \`meshcentral --logintokenkey\` and exits
non-zero when that fails, so check its logs. Everything in this bootstrap after
this point (generated settings, migrate, the full init) needs the token, and the
other Django services are waiting on the advisory lock held here, so this exits
rather than stalling the whole stack.
EOF
			exit 1
		fi
		echo "waiting for tactical-meshcentral to write ${token_file}..."
		sleep 1
		waited=$((waited + 1))
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
# The marker carries the layout revision, the upstream release and our packaging
# revision, so any released change to these images moves it and the next start
# runs the full bootstrap. TRMM_FORCE_INIT=1 still forces it for a local rebuild
# that did not bump config.yml published.revision, which beats telling people to
# delete a file out of a named volume.
function init_is_current {
	[ "${TRMM_FORCE_INIT}" = "1" ] && return 1
	[ -f "${TACTICAL_READY_FILE}" ] || return 1
	cmp --silent "${TACTICAL_READY_FILE}" "${TACTICAL_LAYOUT_FILE}"
}

# tactical-frontend polls this file, so it is written through a temp file and
# renamed. A plain redirect truncates first, which that poller can observe as an
# empty file (it waits, harmless) or a partial URL (it fetches garbage).
function write_web_tar_url {
	local target="${TACTICAL_DIR}/tmp/web_tar_url"

	python manage.py get_webtar_url >"${target}.tmp"
	mv "${target}.tmp" "${target}"
}

# Everything that only has to happen on a first run or a version change. Ordering
# is upstream's and matters: pre_update_tasks before migrate, and
# generate_json_schemas before collectstatic because it writes into
# STATICFILES_DIRS.
function run_full_init {
	python manage.py pre_update_tasks
	python manage.py migrate --no-input
	python manage.py generate_json_schemas
	write_web_tar_url
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

# The work that has to happen once per stack start rather than once per upgrade,
# split by which service owns it so it runs exactly once without any
# cross-container coordination beyond the lock. Assigning by role is what lets
# tactical-init go away: a shared one-shot container was previously the only
# thing expressing "once per stack start".
#
# Nothing here is required by every service, so none of it is in the common path:
# the nats configs and the web tar URL are consumed by tactical-nats and
# tactical-frontend, and the celery locks only matter to a worker.
function run_role_tasks {
	case "$1" in
	tactical-backend)
		write_web_tar_url
		python manage.py reload_nats
		python manage.py create_natsapi_conf
		;;
	tactical-celery)
		python manage.py clear_redis_celery_locks
		;;
	esac
}

# Runs under the advisory lock held by pg_lock.py, so exactly one container is
# inside this at a time. Idempotent throughout: the second and later containers
# find the marker current and do nothing but a no-op migrate.
function bootstrap {
	local role="$1" mode

	if init_is_current; then
		mode=warm
		echo "State matches this image ($(tr '\n' ' ' <"${TACTICAL_LAYOUT_FILE}")); short bootstrap for ${role}."
	else
		mode=full
		echo "First run, or layout/version change; full bootstrap for ${role}."
	fi

	ensure_state_dirs
	provision_mesh_database

	# Only the full path needs MeshCentral itself: initial_mesh_setup opens a
	# websocket to it. Otherwise all that is needed is the token file, already in
	# the tmp volume from the previous run, so a restart does not wait for a mesh
	# container that is still booting. That wait is the single largest part of a
	# cold start, because mesh in turn waits on nginx before it listens.
	if [ "${mode}" = full ]; then
		wait_for_tcp "${MESH_SERVICE}" 4443 "meshcentral container"
	fi
	wait_for_mesh_token

	# Order matters: the seeded local_settings.py must exist before any management
	# command imports Django settings, because it carries SECRET_KEY.
	write_generated_settings
	seed_local_settings
	seed_app_ini

	if [ "${mode}" = full ]; then
		run_full_init
		cp "${TACTICAL_LAYOUT_FILE}" "${TACTICAL_READY_FILE}"
	else
		# A no-op round trip when nothing changed, kept so a hand-applied database
		# change is still caught.
		python manage.py migrate --no-input
	fi

	run_role_tasks "${role}"
}

case "$1" in
# Serialized startup bootstrap, invoked by each service below through pg_lock.py.
# Not meant to be run directly; use tactical-init for that.
bootstrap)
	bootstrap "$2"
	;;

# Manual re-seed, and the compatibility name for what used to be a compose
# service: `docker compose run --rm tactical-backend tactical-init`. Takes the
# same lock, so it is safe to run against a live stack. Forces the full path,
# since running this at all means asking for the whole sequence.
tactical-init)
	export TRMM_FORCE_INIT=1
	exec python /pg_lock.py "$0" bootstrap tactical-init
	;;

tactical-backend)
	python /pg_lock.py "$0" bootstrap tactical-backend
	uwsgi "${TACTICAL_CONF_DIR}/app.ini"
	;;

tactical-celery)
	python /pg_lock.py "$0" bootstrap tactical-celery
	celery -A tacticalrmm worker --autoscale=20,2 -l info
	;;

tactical-celerybeat)
	python /pg_lock.py "$0" bootstrap tactical-celerybeat
	test -f "${TACTICAL_DIR}/api/celerybeat.pid" && rm "${TACTICAL_DIR}/api/celerybeat.pid"
	celery -A tacticalrmm beat -l info
	;;

tactical-websockets)
	python /pg_lock.py "$0" bootstrap tactical-websockets
	export DJANGO_SETTINGS_MODULE=tacticalrmm.settings
	uvicorn --host 0.0.0.0 --port 8383 --forwarded-allow-ips='*' tacticalrmm.asgi:application
	;;

*)
	echo "unknown command: $1" >&2
	echo "expected one of: tactical-init tactical-backend tactical-celery tactical-celerybeat tactical-websockets" >&2
	exit 1
	;;
esac
