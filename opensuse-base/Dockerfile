# ---- Stage: base ----
ARG OPENSUSE_VERSION=16.0
FROM docker.io/opensuse/leap:${OPENSUSE_VERSION} AS base

ARG NU_VERSION=0.112.2
ARG BINARIES_HOST=dufs.niceguyit.biz

# Toolchains install system-wide so every container UID can use them. setup.nu add-user mirrors
# these into /etc/profile.d for ssh login shells, which do not inherit Docker ENV.
ENV RUSTUP_HOME=/usr/local/rustup \
	CARGO_HOME=/usr/local/cargo \
	BUN_INSTALL_GLOBAL_DIR=/usr/local/share/bun/global \
	BUN_INSTALL_BIN=/usr/local/share/bun/bin \
	UV_TOOL_DIR=/usr/local/share/uv/tools \
	UV_TOOL_BIN_DIR=/usr/local/share/uv/bin \
	UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python \
	UV_PYTHON_BIN_DIR=/usr/local/share/uv/bin
ENV PATH="${CARGO_HOME}/bin:${BUN_INSTALL_BIN}:${UV_TOOL_BIN_DIR}:${PATH}"

# Bootstrap Nushell (needed to run setup.nu)
RUN curl -sSfL --retry 3 --retry-delay 2 --retry-connrefused -o /usr/local/bin/nu \
	"https://${BINARIES_HOST}/public/linux/x86_64/nu/${NU_VERSION}/nu" \
	&& chmod a+rx /usr/local/bin/nu \
	&& mkdir -p /tmp/build

# Copy setup scripts and config into the container. --chmod pins the file mode so a
# 0600 host checkout stays readable to USER dev below. /tmp/build is created above,
# because --chmod would otherwise apply 644 to the directory too and make it
# untraversable.
COPY --chmod=644 config.yml setup.nu /tmp/build/

# Install base system packages
RUN nu /tmp/build/setup.nu install-packages --variant base

# Download binaries in parallel
RUN nu /tmp/build/setup.nu install-binaries

# Create user and configure environment
RUN nu /tmp/build/setup.nu add-user

# Install Rust, bun global packages, and uv tools system-wide
RUN nu /tmp/build/setup.nu install-system-tools --variant base

USER dev

# ---- Stage: dev (extends base) ----
FROM base AS dev

ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/ms-playwright

# Install extra dev system packages
USER root
RUN nu /tmp/build/setup.nu install-packages --variant dev-extras

# Install Playwright browser system libraries + vendored Ubuntu support libs.
# Pre-baking these (and the browsers below) lets E2E suites run on this image
# without Playwright's unsupported-OS fallback to apt-get.
RUN nu /tmp/build/setup.nu install-playwright-libs

# Install extra dev bun/uv packages system-wide
RUN nu /tmp/build/setup.nu install-dev-extras

# Pre-download the Playwright browser binaries into PLAYWRIGHT_BROWSERS_PATH
RUN nu /tmp/build/setup.nu install-playwright-browsers

USER dev
