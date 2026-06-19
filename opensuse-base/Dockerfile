# ---- Stage: base ----
ARG OPENSUSE_VERSION=16.0
FROM docker.io/opensuse/leap:${OPENSUSE_VERSION} AS base

ARG NU_VERSION=0.101.0
ARG BINARIES_HOST=dufs.niceguyit.biz

# Bootstrap Nushell (needed to run setup.nu)
RUN curl -sSfL -o /usr/local/bin/nu \
	"https://${BINARIES_HOST}/public/linux/x86_64/nu/${NU_VERSION}/nu" \
	&& chmod a+rx /usr/local/bin/nu

# Copy setup scripts and config into the container
COPY config.yml setup.nu /tmp/build/

# Install base system packages
RUN nu /tmp/build/setup.nu install-packages --variant base

# Download binaries in parallel
RUN nu /tmp/build/setup.nu install-binaries

# Create user and configure environment
RUN nu /tmp/build/setup.nu add-user

# Install user-level tools (nvm, bun, uv, Rust) as dev user
USER dev
RUN nu --login --commands "nu /tmp/build/setup.nu install-user-tools --variant base"

# Make user-installed binaries discoverable to non-login shells (`docker exec`,
# act CI, anything that doesn't go through PAM). Login shells / ssh sessions /
# devcontainer userEnvProbe get the same PATH from /etc/profile.d/dev-paths.sh
# written by setup.nu::add-user; this ENV is the second half of the same wiring
# for environments that inherit Docker's image metadata directly.
ENV PATH="/home/dev/.cargo/bin:/home/dev/.bun/bin:${PATH}"

# ---- Stage: dev (extends base) ----
FROM base AS dev

# Install extra dev system packages
USER root
RUN nu /tmp/build/setup.nu install-packages --variant dev-extras

# Install Playwright browser system libraries + vendored Ubuntu support libs.
# Pre-baking these (and the browsers below) lets E2E suites run on this image
# without Playwright's unsupported-OS fallback to apt-get.
RUN nu /tmp/build/setup.nu install-playwright-libs

# Install extra dev bun/uv packages as dev user
USER dev
RUN nu --login --commands "nu /tmp/build/setup.nu install-dev-extras"

# Pre-download the Playwright browser binaries into the dev user's cache
RUN nu --login --commands "nu /tmp/build/setup.nu install-playwright-browsers"
