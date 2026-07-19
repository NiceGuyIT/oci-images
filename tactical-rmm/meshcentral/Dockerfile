ARG TRMM_VERSION
ARG BASE_IMAGE=node
ARG BASE_TAG=24-alpine

# Stage 1: Fetch upstream Tactical RMM source at the pinned tag.
FROM alpine:3 AS source

ARG TRMM_VERSION

RUN apk add --no-cache curl tar \
	&& mkdir /src \
	&& curl -fsSL "https://github.com/amidaware/tacticalrmm/archive/refs/tags/v${TRMM_VERSION}.tar.gz" \
		| tar -xz -C /src --strip-components=1

# Stage 2: Runtime image. Installs MeshCentral at the version recorded in
# upstream settings.py so the mesh server matches the backend's expectations.
FROM ${BASE_IMAGE}:${BASE_TAG}

WORKDIR /home/node/app

ENV TACTICAL_DIR=/opt/tactical

RUN apk add --no-cache bash

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=source /src/api/tacticalrmm/tacticalrmm/settings.py /tmp/settings.py
# Local entrypoint replaces the upstream MongoDB-based one with PostgreSQL. It
# writes a "postgres" config block when MESH_POSTGRES_HOST is set (staging and
# production); otherwise MeshCentral falls back to its built-in NeDB store under
# /home/node/app/meshcentral-data (the Docker Compose default). The MongoDB
# container dependency is removed either way.
COPY entrypoint.sh /entrypoint.sh

# nodemailer is baked in here because MeshCentral npm-installs it on first boot
# whenever config.json has an "smtp" block (the entrypoint always writes one).
# Pinning it in package.json moves that slow install into the image build.
RUN MESH_VER=$(grep -o 'MESH_VER.*' /tmp/settings.py | cut -d'"' -f 2) \
	&& cat > package.json <<EOF
{
  "dependencies": {
    "archiver": "7.0.1",
    "meshcentral": "${MESH_VER}",
    "mongodb": "4.13.0",
    "nodemailer": "6.10.1",
    "otplib": "10.2.3",
    "pg": "8.7.1",
    "pgtools": "0.3.2",
    "saslprep": "1.0.3"
  }
}
EOF

RUN npm install \
	&& chmod +x /entrypoint.sh \
	&& chown -R node:node /home/node

EXPOSE 8080 4443

USER node

ENTRYPOINT ["/entrypoint.sh"]
