ARG TRMM_VERSION
ARG BASE_IMAGE=nats
ARG BASE_TAG=2.12.3-alpine

# Stage 1: Fetch upstream Tactical RMM source at the pinned tag.
FROM alpine:3 AS source

ARG TRMM_VERSION

RUN apk add --no-cache curl tar \
	&& mkdir /src \
	&& curl -fsSL "https://github.com/amidaware/tacticalrmm/archive/refs/tags/v${TRMM_VERSION}.tar.gz" \
		| tar -xz -C /src --strip-components=1

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
COPY --from=source /src/docker/containers/tactical-nats/entrypoint.sh /entrypoint.sh

# Select the binary that matches the build architecture (set by BuildKit).
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
		mv /tmp/nats-api-arm64 /usr/local/bin/nats-api; \
	else \
		mv /tmp/nats-api-amd64 /usr/local/bin/nats-api; \
	fi \
	&& rm -f /tmp/nats-api-* \
	&& chmod +x /usr/local/bin/nats-api /entrypoint.sh

RUN touch /usr/local/bin/config_watcher.sh \
	&& chown 1000:1000 /usr/local/bin/config_watcher.sh \
	&& mkdir -p /var/log/supervisor /etc/supervisor/conf.d \
	&& touch /etc/supervisor/conf.d/supervisor.conf \
	&& chown 1000:1000 /etc/supervisor/conf.d/supervisor.conf

EXPOSE 4222 9235

USER 1000

ENTRYPOINT ["/entrypoint.sh"]
