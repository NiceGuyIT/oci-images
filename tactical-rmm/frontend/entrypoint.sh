#!/usr/bin/env bash
#
# tactical-frontend entrypoint.
#
# Forked from the upstream tactical-frontend entrypoint. The only change is the
# readiness wait. Upstream sleeps 15 seconds unconditionally, then polls every 10
# for the ready file written by the tactical-init container. There is no such
# container any more, so this waits on the artifact it actually consumes instead:
# web_tar_url, written by tactical-backend's bootstrap. The upstream file's hash
# is pinned in the Dockerfile so a TRMM_VERSION bump that changes it fails the
# build.
#
# Runs from the base image's /docker-entrypoint.d/ hook, so it configures nginx
# and returns; the base image starts nginx afterwards. That also means a failure
# here under set -e stops nginx from ever starting.

set -e

URL_PATH="${TACTICAL_DIR}/tmp/web_tar_url"

# Seconds to wait for the backend bootstrap that writes the file above. Bounded
# so a backend that never finishes shows up here as a failed container rather
# than one that sits in "waiting" forever; restart: always retries.
: "${TRMM_WAIT_TIMEOUT:=600}"

function check_tactical_ready {
	local waited=0

	until [ -s "${URL_PATH}" ]; do
		if [ "${waited}" -ge "${TRMM_WAIT_TIMEOUT}" ]; then
			cat >&2 <<EOF
FATAL: ${URL_PATH} was still empty or missing after ${TRMM_WAIT_TIMEOUT}s.

tactical-backend writes it during its startup bootstrap; check that container's
logs. Raise TRMM_WAIT_TIMEOUT if a first run on this host legitimately takes
longer than that.
EOF
			exit 1
		fi
		echo "waiting for tactical-backend to write ${URL_PATH}..."
		sleep 1
		waited=$((waited + 1))
	done
}

# Recreate js config file on start
rm -rf ${PUBLIC_DIR}/env-config.js
touch ${PUBLIC_DIR}/env-config.js

nginx_config="$(
	cat <<EOF
server {
  listen 8080;
  charset utf-8;

  location / {
    root /usr/share/nginx/html;
    try_files \$uri \$uri/ /index.html;
    add_header Cache-Control "no-store, no-cache, must-revalidate";
    add_header Pragma "no-cache";
  }
}
EOF
)"

echo "${nginx_config}" >/etc/nginx/conf.d/default.conf

check_tactical_ready

AGENT_BASE=$(grep -o 'AGENT_BASE_URL.*' /tmp/settings.py | cut -d'"' -f 2)
WEB_VERSION=$(grep -o 'WEB_VERSION.*' /tmp/settings.py | cut -d'"' -f 2)

# add dynamic web tar if configured
if [ -f "$URL_PATH" ]; then
	START_STRING=$(head -c ${#AGENT_BASE} "$URL_PATH")
	if [ "$START_STRING" == "${AGENT_BASE}" ]; then
		echo "Attempting to pull dynamic web tar from ${AGENT_BASE}"
		webtar="trmm-web-v${WEB_VERSION}.tar.gz"
		wget -q $(cat "${URL_PATH}") -O /tmp/${webtar}
		tar -xzf /tmp/${webtar} -C /tmp/
		rm -rf ${PUBLIC_DIR}/*
		mv /tmp/dist/* ${PUBLIC_DIR}

		rm -f /tmp/${webtar}
		rm -rf /tmp/dist
		echo "Success!"
	fi
fi

# Add runtime base url assignment
echo "window._env_ = {PROD_URL: \"https://${API_HOST}\"}" >${PUBLIC_DIR}/env-config.js
chown -R nginx:nginx /etc/nginx && chown -R nginx:nginx ${PUBLIC_DIR}
