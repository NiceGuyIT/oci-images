ARG TRMM_VERSION
ARG BASE_IMAGE=nginxinc/nginx-unprivileged
ARG BASE_TAG=stable-alpine

# Stage 1: Fetch upstream Tactical RMM source at the pinned tag.
FROM alpine:3 AS source

ARG TRMM_VERSION

RUN apk add --no-cache curl tar \
	&& mkdir /src \
	&& curl -fsSL "https://github.com/amidaware/tacticalrmm/archive/refs/tags/v${TRMM_VERSION}.tar.gz" \
		| tar -xz -C /src --strip-components=1

# Stage 2: Download and unpack the matching tacticalrmm-web release.
# WEB_VERSION is read from the upstream settings.py so the frontend tracks the backend.
FROM alpine:3 AS web

RUN apk add --no-cache bash wget tar grep

COPY --from=source /src/api/tacticalrmm/tacticalrmm/settings.py /tmp/settings.py

RUN WEB_VERSION=$(grep -o 'WEB_VERSION.*' /tmp/settings.py | cut -d'"' -f 2) \
	&& mkdir -p /web \
	&& wget -q "https://github.com/amidaware/tacticalrmm-web/releases/download/v${WEB_VERSION}/trmm-web-v${WEB_VERSION}.tar.gz" -O /tmp/web.tar.gz \
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
COPY --from=source /src/docker/containers/tactical-frontend/entrypoint.sh /docker-entrypoint.d/entrypoint.sh

RUN chown -R nginx:nginx /etc/nginx \
	&& chown -R nginx:nginx ${PUBLIC_DIR} \
	&& chmod +x /docker-entrypoint.d/entrypoint.sh

USER nginx

EXPOSE 8080
