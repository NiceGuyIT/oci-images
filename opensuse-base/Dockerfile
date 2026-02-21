# ---- Stage: base ----
ARG OPENSUSE_VERSION=16.0
FROM docker.io/opensuse/leap:${OPENSUSE_VERSION} AS base

ARG BASE_PACKAGES="sudo vim vim-data git tar gzip bzip2 unzip zstd which nodejs-common openssh-clients buildah docker docker-compose docker-buildx fuse-overlayfs"
ARG NU_VERSION=0.101.0
ARG BINARIES_HOST=dufs.niceguyit.biz

# Install system packages
RUN zypper --non-interactive --gpg-auto-import-keys refresh \
	&& zypper --non-interactive update \
	&& zypper --non-interactive install ${BASE_PACKAGES} \
	&& zypper --non-interactive clean --all

# Bootstrap Nushell (needed to run setup.nu)
RUN curl -sSfL -o /usr/local/bin/nu \
	"https://${BINARIES_HOST}/public/linux/x86_64/nu/${NU_VERSION}/nu" \
	&& chmod a+rx /usr/local/bin/nu

# Copy setup scripts and config into the container
COPY config.yml setup.nu /tmp/build/

# Run setup.nu to download binaries in parallel
RUN nu /tmp/build/setup.nu install-binaries

# Create user and configure environment
RUN nu /tmp/build/setup.nu add-user

# Switch to dev user for user-level tool installation
USER dev
SHELL ["/usr/local/bin/nu", "--login", "--commands"]
RUN nu /tmp/build/setup.nu install-user-tools --variant base

# ---- Stage: dev (extends base) ----
FROM base AS dev

ARG DEV_EXTRA_PACKAGES="java-21-openjdk-devel postgresql17 clang libopenssl-devel gcc bison flex gdbm-devel libfl-devel libfl2 libtool makeinfo patch patterns-devel-base-devel_basis perl-Text-Unidecode webkit2gtk3-devel libappindicator3-1 librsvg-devel"

USER root
RUN zypper --non-interactive --gpg-auto-import-keys refresh \
	&& zypper --non-interactive install ${DEV_EXTRA_PACKAGES} \
	&& zypper --non-interactive clean --all

# Install only the extra dev bun/uv packages that aren't already in base
USER dev
SHELL ["/usr/local/bin/nu", "--login", "--commands"]
RUN nu /tmp/build/setup.nu install-dev-extras
