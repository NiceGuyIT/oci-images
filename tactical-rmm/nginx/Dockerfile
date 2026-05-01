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

# Stage 2: Runtime image.
FROM ${BASE_IMAGE}:${BASE_TAG}

ENV TACTICAL_DIR=/opt/tactical

USER root

RUN deluser --remove-home nginx \
	&& addgroup -S nginx -g 1000 \
	&& adduser -S -G nginx -u 1000 nginx \
	&& apk add --no-cache openssl bash \
	&& chown -R nginx:nginx /etc/nginx

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=source /src/docker/containers/tactical-nginx/entrypoint.sh /docker-entrypoint.d/entrypoint.sh

RUN chmod +x /docker-entrypoint.d/entrypoint.sh

USER nginx

EXPOSE 4443 8080
