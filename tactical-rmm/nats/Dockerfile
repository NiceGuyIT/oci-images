ARG TRMM_VERSION
ARG BASE_IMAGE=nats
ARG BASE_TAG=2.14.2-alpine

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
RUN echo "683268e1602968be2ee0928bd954b980c9e7e0a31afaabf1ea5dad0d12a1f4fe  /src/docker/containers/tactical-nats/entrypoint.sh" \
	| sha256sum -c -

# Stage 2: Runtime image. Bundles the pre-built nats-api binary that ships
# in the upstream Tactical RMM repository.
FROM ${BASE_IMAGE}:${BASE_TAG}

ARG TARGETARCH

ENV TACTICAL_DIR=/opt/tactical
ENV TACTICAL_READY_FILE=${TACTICAL_DIR}/tmp/tactical.ready

RUN apk add --no-cache supervisor bash

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=source /src/natsapi/bin/nats-api /tmp/nats-api-amd64
COPY --from=source /src/natsapi/bin/nats-api-arm64 /tmp/nats-api-arm64
# Local fork of the upstream entrypoint; see the header comment in that file.
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Select the binary that matches the build architecture (set by BuildKit).
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
		mv /tmp/nats-api-arm64 /usr/local/bin/nats-api; \
	else \
		mv /tmp/nats-api-amd64 /usr/local/bin/nats-api; \
	fi \
	&& rm -f /tmp/nats-api-* \
	&& chmod +x /usr/local/bin/nats-api

# ${TACTICAL_DIR}/api is where compose mounts the conf volume for this image, and
# tmp carries the ready file. Both mount points must exist in the image and be
# owned by uid 10000: a named volume is seeded from the image path it is mounted
# on, so a missing path yields an empty root-owned directory.
RUN touch /usr/local/bin/config_watcher.sh \
	&& chown 10000:10000 /usr/local/bin/config_watcher.sh \
	&& mkdir -p /var/log/supervisor /etc/supervisor/conf.d \
	&& touch /etc/supervisor/conf.d/supervisor.conf \
	&& chown 10000:10000 /etc/supervisor/conf.d/supervisor.conf \
	&& mkdir -p "${TACTICAL_DIR}/api" "${TACTICAL_DIR}/tmp" \
	&& chown -R 10000:10000 "${TACTICAL_DIR}"

EXPOSE 4222 9235

USER 10000

ENTRYPOINT ["/entrypoint.sh"]
