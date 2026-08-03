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

# Stage 2: Runtime image.
FROM ${BASE_IMAGE}:${BASE_TAG}

ENV TACTICAL_DIR=/opt/tactical

USER root

RUN deluser --remove-home nginx \
	&& addgroup -S nginx -g 10000 \
	&& adduser -S -G nginx -u 10000 nginx \
	&& apk add --no-cache openssl bash \
	&& chown -R nginx:nginx /etc/nginx

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=source /src/docker/containers/tactical-nginx/entrypoint.sh /docker-entrypoint.d/entrypoint.sh

# Mount points for the four state volumes this image consumes. They must exist
# in the image and be owned by the runtime user: a named volume is seeded from
# the image path it is mounted on, so a missing path yields an empty root-owned
# directory. certs matters most, being the one this container writes when it
# generates the self-signed pair, and this service has no depends_on so it can
# be created before anything else touches the volume.
RUN chmod +x /docker-entrypoint.d/entrypoint.sh \
	&& mkdir -p \
		"${TACTICAL_DIR}/certs" \
		"${TACTICAL_DIR}/reporting/assets" \
		"${TACTICAL_DIR}/api/static" \
		"${TACTICAL_DIR}/api/tacticalrmm/private" \
	&& chown -R nginx:nginx "${TACTICAL_DIR}"

USER nginx

EXPOSE 4443 8080
