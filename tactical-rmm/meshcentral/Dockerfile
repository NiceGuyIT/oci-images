ARG TRMM_VERSION
ARG BASE_IMAGE=node
ARG BASE_TAG=24-alpine
# Bun replaces npm as the build-time package manager (faster installs). The
# alpine (musl) variant matches the node:*-alpine runtime base.
ARG BUN_IMAGE=oven/bun
ARG BUN_TAG=1-alpine

# Stage 1: Fetch upstream Tactical RMM source at the pinned tag.
FROM alpine:3 AS source

ARG TRMM_VERSION

RUN apk add --no-cache curl tar \
	&& mkdir /src \
	&& curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused "https://github.com/amidaware/tacticalrmm/archive/refs/tags/v${TRMM_VERSION}.tar.gz" \
		| tar -xz -C /src --strip-components=1

# Stage 2: Provide the bun binary for the build-time install below.
FROM ${BUN_IMAGE}:${BUN_TAG} AS bun

# Stage 3: Runtime image. Installs MeshCentral at the version recorded in
# upstream settings.py so the mesh server matches the backend's expectations.
FROM ${BASE_IMAGE}:${BASE_TAG}

WORKDIR /home/node/app

ENV TACTICAL_DIR=/opt/tactical

# postgresql-client supplies pg_dump (MeshCentral's startup auto-backup shells
# out to it; without it the backup errors and trips an upstream crash bug) and
# pg_isready (the entrypoint waits on it before creating accounts, so the mesh
# server never races an unready PostgreSQL).
RUN apk add --no-cache bash postgresql-client

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=source /src/api/tacticalrmm/tacticalrmm/settings.py /tmp/settings.py
# Local entrypoint replaces the upstream MongoDB-based one with PostgreSQL. It
# always writes a "postgres" config block; PostgreSQL is the only MeshCentral
# data store in these images (no NeDB fallback, no MongoDB). MESH_POSTGRES_HOST
# defaults to tactical-postgres, the same server as the tacticalrmm database.
# --chmod pins the mode: without it a 0600 host checkout yields 0700 after the
# chmod +x below, which USER node cannot execute.
COPY --chmod=755 entrypoint.sh /entrypoint.sh
# Bun binary for the install below. node:*-alpine already ships libstdc++, which
# is bun's only shared-library dependency on musl.
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

# nodemailer and pg are baked in here because MeshCentral npm-installs its
# required modules on first boot whenever a matching version is not already
# present: nodemailer whenever config.json has an "smtp" block, and pg whenever
# a "postgres" block is present (the entrypoint always writes both). pg must be
# pinned to the EXACT version MeshCentral requires (8.16.3 for MeshCentral
# v1.2.0); a mismatched pin still triggers the boot-time reinstall. Pinning the
# right versions moves that slow install into the image build.
RUN MESH_VER=$(grep -o 'MESH_VER.*' /tmp/settings.py | cut -d'"' -f 2) \
	&& cat > package.json <<EOF
{
  "dependencies": {
    "archiver": "7.0.1",
    "meshcentral": "${MESH_VER}",
    "nodemailer": "6.10.1",
    "otplib": "10.2.3",
    "pg": "8.16.3",
    "pgtools": "0.3.2",
    "saslprep": "1.0.3"
  }
}
EOF

RUN bun install \
	&& chmod +x /entrypoint.sh \
	&& chown -R node:node /home/node

EXPOSE 8080 4443

USER node

ENTRYPOINT ["/entrypoint.sh"]
