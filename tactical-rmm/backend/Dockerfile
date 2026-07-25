ARG TRMM_VERSION
ARG BASE_IMAGE=python
ARG BASE_TAG=3.11.8-slim
# uv replaces pip as the Python package installer (faster resolution/installs).
# The binary is statically linked (musl) so it runs on the Debian-slim base.
ARG UV_IMAGE=ghcr.io/astral-sh/uv
ARG UV_TAG=0.11.29

# Stage 1: Fetch upstream Tactical RMM source at the pinned tag.
FROM alpine:3 AS source

ARG TRMM_VERSION

RUN apk add --no-cache curl tar \
	&& mkdir /src \
	&& curl -fsSL "https://github.com/amidaware/tacticalrmm/archive/refs/tags/v${TRMM_VERSION}.tar.gz" \
		| tar -xz -C /src --strip-components=1

# Provide the uv binary for the venv build below.
FROM ${UV_IMAGE}:${UV_TAG} AS uv

# Stage 2: Build Python virtualenv with API requirements.
FROM ${BASE_IMAGE}:${BASE_TAG} AS venv

ARG DEBIAN_FRONTEND=noninteractive

ENV VIRTUAL_ENV=/opt/venv
ENV TACTICAL_TMP_DIR=/tmp/tactical
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=uv /uv /usr/local/bin/uv
COPY --from=source /src/api/tacticalrmm/requirements.txt ${TACTICAL_TMP_DIR}/api/requirements.txt

# uv installs into the venv named by VIRTUAL_ENV. The venv is created by the
# stdlib venv module (system CPython) so it still ships pip/setuptools for any
# runtime code that expects them; uv only replaces the install step. gcc/libc6-dev
# remain for source distributions that build C extensions during install.
RUN python3 -m venv ${VIRTUAL_ENV} \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gcc libc6-dev \
	&& uv pip install --no-cache setuptools wheel \
	&& uv pip install --no-cache -r ${TACTICAL_TMP_DIR}/api/requirements.txt \
	&& rm -rf /var/lib/apt/lists/*

# Stage 3: Fetch the community-scripts repository.
FROM alpine:3 AS scripts

RUN apk add --no-cache git \
	&& git clone --depth 1 https://github.com/amidaware/community-scripts.git /community-scripts

# Stage 4: Runtime image.
FROM ${BASE_IMAGE}:${BASE_TAG}

ENV VIRTUAL_ENV=/opt/venv
ENV TACTICAL_DIR=/opt/tactical
ENV TACTICAL_TMP_DIR=/tmp/tactical
ENV TACTICAL_READY_FILE=${TACTICAL_DIR}/tmp/tactical.ready
ENV TACTICAL_USER=tactical
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=source /src/api/tacticalrmm ${TACTICAL_TMP_DIR}/api
COPY --from=scripts /community-scripts ${TACTICAL_TMP_DIR}/community-scripts
COPY --from=venv ${VIRTUAL_ENV} ${VIRTUAL_ENV}
# The upstream entrypoint is kept unmodified. entrypoint.sh is a thin local
# wrapper that provisions the MeshCentral PostgreSQL database during tactical-init
# and then execs the upstream entrypoint.
COPY --from=source /src/docker/containers/tactical/entrypoint.sh /entrypoint-upstream.sh
COPY --chmod=755 entrypoint.sh /entrypoint.sh

RUN apt-get update \
	&& apt-get upgrade -y \
	&& apt-get install -y --no-install-recommends rsync weasyprint \
	&& rm -rf /var/lib/apt/lists/* \
	&& groupadd -g 1000 "${TACTICAL_USER}" \
	&& useradd -M -d "${TACTICAL_DIR}" -s /bin/bash -u 1000 -g 1000 "${TACTICAL_USER}" \
	&& chmod +x /entrypoint.sh /entrypoint-upstream.sh

WORKDIR ${TACTICAL_DIR}/api

EXPOSE 8080 4443 8383

ENTRYPOINT ["/entrypoint.sh"]
