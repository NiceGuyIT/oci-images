#!/usr/bin/env bash
#
# tactical-nats entrypoint.
#
# Forked from the upstream tactical-nats entrypoint. The only change is the
# readiness wait. Upstream sleeps 15 seconds unconditionally, then polls every 10
# for the ready file written by the tactical-init container. There is no such
# container any more, so this waits on the config it actually consumes instead,
# written by tactical-backend's bootstrap. The upstream file's hash is pinned in
# the Dockerfile so a TRMM_VERSION bump that changes it fails the build.
#
# The config paths are unchanged. The backend writes nats-rmm.conf and
# nats-api.conf into the conf volume through symlinks in its own api directory,
# and compose mounts that same volume at ${TACTICAL_DIR}/api here, so both files
# appear exactly where upstream expects them.

set -e

: "${DEV:=0}"
: "${NATS_CONFIG_CHECK_INTERVAL:=1}"
# Seconds to wait for the backend bootstrap that writes the two configs below.
# Bounded so a backend that never finishes shows up here as a failed container
# rather than one that sits in "waiting" forever; restart: always retries.
: "${TRMM_WAIT_TIMEOUT:=600}"

if [ "${DEV}" = 1 ]; then
	NATS_CONFIG=/workspace/api/tacticalrmm/nats-rmm.conf
	NATS_API_CONFIG=/workspace/api/tacticalrmm/nats-api.conf
else
	NATS_CONFIG="${TACTICAL_DIR}/api/nats-rmm.conf"
	NATS_API_CONFIG="${TACTICAL_DIR}/api/nats-api.conf"
fi

waited=0
until [ -s "${NATS_CONFIG}" ] && [ -s "${NATS_API_CONFIG}" ]; do
	if [ "${waited}" -ge "${TRMM_WAIT_TIMEOUT}" ]; then
		cat >&2 <<EOF
FATAL: ${NATS_CONFIG} or ${NATS_API_CONFIG} was still empty or missing after ${TRMM_WAIT_TIMEOUT}s.

tactical-backend writes both during its startup bootstrap; check that container's
logs. Raise TRMM_WAIT_TIMEOUT if a first run on this host legitimately takes
longer than that.
EOF
		exit 1
	fi
	echo "waiting for tactical-backend to write ${NATS_CONFIG}..."
	sleep 1
	waited=$((waited + 1))
done

config_watcher="$(
	cat <<EOF
while true; do
    sleep ${NATS_CONFIG_CHECK_INTERVAL};
    if [[ ! -z \${NATS_CHECK} ]]; then
        NATS_RELOAD=\$(date -r '${NATS_CONFIG}')
        if [[ \$NATS_RELOAD == \$NATS_CHECK ]]; then
            :
        else
            nats-server --signal reload;
            NATS_CHECK=\$(date -r '${NATS_CONFIG}');
        fi
    else NATS_CHECK=\$(date -r '${NATS_CONFIG}');
    fi
done

EOF
)"

echo "${config_watcher}" >/usr/local/bin/config_watcher.sh
chmod +x /usr/local/bin/config_watcher.sh

supervisor_config="$(
	cat <<EOF
[supervisord]
nodaemon=true
logfile=/tmp/supervisord.log
pidfile=/tmp/supervisord.pid
[include]
files = /etc/supervisor/conf.d/*.conf

[program:nats-server]
command=nats-server --config ${NATS_CONFIG}
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:config-watcher]
command=/bin/bash /usr/local/bin/config_watcher.sh
startsecs=10
autorestart=true
startretries=1
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:nats-api]
command=/bin/bash -c "/usr/local/bin/nats-api -config ${NATS_API_CONFIG}"
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

EOF
)"

echo "${supervisor_config}" >/etc/supervisor/conf.d/supervisor.conf

# run supervised processes
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisor.conf
