ARG TRMM_VERSION
ARG BASE_IMAGE=nginxinc/nginx-unprivileged
ARG BASE_TAG=stable-alpine

# Stage 1: Fetch upstream Tactical RMM source at the pinned tag.
FROM alpine:3 AS source

ARG TRMM_VERSION

RUN apk add --no-cache curl tar \
	&& mkdir /src \
	&& curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused "https://github.com/amidaware/tacticalrmm/archive/refs/tags/v${TRMM_VERSION}.tar.gz" \
		| tar -xz -C /src --strip-components=1

# entrypoint.sh here is a fork of the upstream one, so nothing detects upstream
# changing it. Pin the hash: a TRMM_VERSION bump that rewrites it fails the build
# instead of silently shipping a stale fork.
RUN echo "3fa879c079d1202ec0bdd1ae0d6d229f1ff0328859d8d49aaa327693ae37a6f5  /src/docker/containers/tactical-frontend/entrypoint.sh" \
	| sha256sum -c -

# Stage 2: Download and unpack the matching tacticalrmm-web release.
# WEB_VERSION is read from the upstream settings.py so the frontend tracks the backend.
FROM alpine:3 AS web

RUN apk add --no-cache bash wget tar grep

COPY --from=source /src/api/tacticalrmm/tacticalrmm/settings.py /tmp/settings.py

RUN WEB_VERSION=$(grep -o 'WEB_VERSION.*' /tmp/settings.py | cut -d'"' -f 2) \
	&& mkdir -p /web \
	&& wget -q --tries=3 --waitretry=2 "https://github.com/amidaware/tacticalrmm-web/releases/download/v${WEB_VERSION}/trmm-web-v${WEB_VERSION}.tar.gz" -O /tmp/web.tar.gz \
	&& tar -xzf /tmp/web.tar.gz -C /web \
	&& mv /web/dist/* /web/ \
	&& rm -rf /web/dist /tmp/web.tar.gz

# Stage 3: Runtime image.
FROM ${BASE_IMAGE}:${BASE_TAG}

ENV PUBLIC_DIR=/usr/share/nginx/html
ENV TACTICAL_DIR=/opt/tactical
ENV TACTICAL_READY_FILE=${TACTICAL_DIR}/tmp/tactical.ready

USER root

RUN deluser --remove-home nginx \
	&& addgroup -S nginx -g 1000 \
	&& adduser -S -G nginx -u 1000 nginx \
	&& apk add --no-cache bash wget tar grep

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=web /web ${PUBLIC_DIR}
# The entrypoint greps AGENT_BASE_URL and WEB_VERSION out of this at runtime.
# Without it both are empty, which makes the dynamic-web-tar guard
# (`head -c ${#AGENT_BASE}` compared against AGENT_BASE) trivially true, so that
# branch runs on every start and fetches whatever tmp/web_tar_url happens to hold.
COPY --from=source /src/api/tacticalrmm/tacticalrmm/settings.py /tmp/settings.py
# Local fork of the upstream entrypoint; see the header comment in that file.
# --chmod pins the mode so a restrictive host checkout cannot ship a file the
# base image's /docker-entrypoint.d/ runner refuses to execute.
COPY --chmod=755 entrypoint.sh /docker-entrypoint.d/entrypoint.sh

# tmp is the only state volume this image mounts. The mount point must exist in
# the image and be owned by the runtime user: a named volume is seeded from the
# image path it is mounted on, so a missing path yields an empty root-owned
# directory that whichever container is created first would then be stuck with.
RUN chown -R nginx:nginx /etc/nginx \
	&& chown -R nginx:nginx ${PUBLIC_DIR} \
	&& mkdir -p ${TACTICAL_DIR}/tmp \
	&& chown -R nginx:nginx ${TACTICAL_DIR}

USER nginx

EXPOSE 8080
