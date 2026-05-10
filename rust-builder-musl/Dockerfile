# Kitchen-sink musl/alpine Rust builder. Covers every alpine-based Rust
# service in the org: REST APIs (axum), CLIs, sqlx-postgres / sqlx-sqlite,
# dev-environment containers running cargo-watch, and the storefront video
# transcoder. No Dioxus / bun / GTK: those need glibc — see rust-builder-glibc.
#
# Tag suffix:
#   rust-builder-musl:v1.0.0-rust1.94-alpine

ARG RUST_VERSION=1.94

FROM rust:${RUST_VERSION}-alpine

# musl-dev + pkgconfig + openssl-{dev,libs-static} + sqlite-static: every
# alpine-Rust service in the org links these.
# perl + make + linux-headers: openssl-sys uses Configure (perl); ring and a
# handful of other crates need linux-headers.
# lld: opted-in linker via RUSTFLAGS in some Dockerfiles, harmless when unused.
# bash + curl + wget + git + ca-certificates: shell-script + network basics.
# ffmpeg: storefront transcodes video at build time. Cheap to bake in,
# saves storefront a heavy `apk add ffmpeg` step on every build.
RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        linux-headers \
        lld \
        make \
        musl-dev \
        openssl-dev \
        openssl-libs-static \
        perl \
        pkgconfig \
        sqlite-static \
        wget

RUN rustup component add clippy rustfmt \
    && rustup target add wasm32-unknown-unknown

# cargo-binstall (pre-built binary, musl variant for the alpine base).
RUN curl --location --silent --show-error \
        https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-x86_64-unknown-linux-musl.tgz \
    | tar --extract --gzip --directory /usr/local/cargo/bin

# cargo-watch for dev-environment containers.
RUN cargo binstall cargo-watch --no-confirm
