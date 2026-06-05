# Kitchen-sink glibc Rust builder. One FROM line and zero `apt-get install`
# below it covers every glibc-based Rust service in the org: plain CLIs,
# Axum APIs, Dioxus web + desktop, sqlx-postgres, sqlx-sqlite, git2, eframe
# (Wayland + X11 + OpenGL + fontconfig), HID/USB device access (umbra),
# Tauri desktop apps, and dev-environment containers running cargo-watch /
# cargo-chef. Space is cheap; the goal is no per-repo pkg drift.
#
# Tag suffix encodes rust + debian for predictable pinning:
#   rust-builder-glibc:v1.0.0-rust1.94-trixie
#
# Windows cross-compile lives in rust-builder-glibc-windows because the
# mingw-w64 toolchain is large and only one consumer needs it.

ARG RUST_VERSION=1.94
ARG DEBIAN_VARIANT=trixie

FROM rust:${RUST_VERSION}-slim-${DEBIAN_VARIANT}

ARG DIOXUS_CLI_VERSION=0.7.7

# Native packages, alphabetical for diff-friendliness.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        curl \
        file \
        git \
        libayatana-appindicator3-dev \
        libfontconfig1-dev \
        libgit2-dev \
        libgl1-mesa-dev \
        libgtk-3-dev \
        libjavascriptcoregtk-4.1-dev \
        librsvg2-dev \
        libsoup-3.0-dev \
        libsqlite3-dev \
        libssl-dev \
        libudev-dev \
        libusb-1.0-0-dev \
        libwayland-dev \
        libwebkit2gtk-4.1-dev \
        libxcb-cursor-dev \
        libxcb-render0-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev \
        libxcb1-dev \
        libxcursor-dev \
        libxdo-dev \
        libxi-dev \
        libxkbcommon-dev \
        libxrandr-dev \
        lld \
        nodejs \
        npm \
        patchelf \
        pkg-config \
        unzip \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# rustfmt + clippy ship as separate components in the slim image.
RUN rustup component add clippy rustfmt \
    && rustup target add wasm32-unknown-unknown

# cargo-binstall (pre-built binary, GNU variant for glibc).
RUN curl --location --silent --show-error \
        https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-x86_64-unknown-linux-gnu.tgz \
    | tar --extract --gzip --directory /usr/local/cargo/bin

# Bun for Tailwind / asset bundling. Installed directly under /usr/local so
# the binaries land at /usr/local/bin/{bun,bunx}: world-readable, already on
# PATH, and reachable by non-root consumers without traversing /root (mode 700).
RUN curl --fail --location --silent --show-error https://bun.sh/install | env BUN_INSTALL=/usr/local bash

# dioxus-cli pinned (must match the dioxus crate version in consumer
# Cargo.toml files; bump in config.yml when the crate version moves).
RUN cargo binstall dioxus-cli@${DIOXUS_CLI_VERSION} --no-confirm \
    && cargo binstall cargo-watch --no-confirm \
    && cargo binstall cargo-chef --no-confirm
