# Three-tier Rust builder image. Each named stage is a separate published
# image; consumers pick the closest tier.
#
#   base             - Rust toolchain + common build deps + cargo-binstall
#                      (generic Rust services with no Dioxus / WebKit).
#   dioxus           - Adds bun (Tailwind) + pinned dioxus-cli.
#                      For server-rendered or WASM Dioxus apps.
#   dioxus-desktop   - Adds GTK / WebKitGTK + libxdo + appindicator + librsvg.
#                      For Dioxus desktop builds (wry renderer).

ARG RUST_VERSION=1.93
ARG DEBIAN_VARIANT=trixie

# ---------------------------------------------------------------------------
# Stage: base
# ---------------------------------------------------------------------------
FROM rust:${RUST_VERSION}-slim-${DEBIAN_VARIANT} AS base

RUN apt-get update && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        pkg-config \
        libssl-dev \
        build-essential \
        lld \
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN rustup target add wasm32-unknown-unknown

RUN curl --location --silent --show-error \
        https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-x86_64-unknown-linux-gnu.tgz \
    | tar --extract --gzip --directory /usr/local/cargo/bin

# ---------------------------------------------------------------------------
# Stage: dioxus
# ---------------------------------------------------------------------------
FROM base AS dioxus

ARG DIOXUS_CLI_VERSION=0.7.7

# Bun for Tailwind CSS / asset bundling.
RUN curl --fail --location --silent --show-error https://bun.sh/install | bash \
    && cp /root/.bun/bin/bun /usr/local/bin/bun
ENV PATH="/root/.bun/bin:${PATH}"

RUN cargo binstall dioxus-cli@${DIOXUS_CLI_VERSION} --no-confirm

# ---------------------------------------------------------------------------
# Stage: dioxus-desktop
# ---------------------------------------------------------------------------
FROM dioxus AS dioxus-desktop

RUN apt-get update && apt-get install --yes --no-install-recommends \
        libwebkit2gtk-4.1-dev \
        libxdo-dev \
        libayatana-appindicator3-dev \
        librsvg2-dev \
    && rm -rf /var/lib/apt/lists/*
