# Cross-compile-to-Windows builder. Adds the mingw-w64 toolchain (~1.5GB) on
# top of a glibc/trixie Rust base. Separate image from rust-builder-glibc
# because only one consumer (da-os) needs Windows cross-compile, and the
# scope is expected to deviate over time (eg. msvc target, additional crts).
#
# Tag suffix:
#   rust-builder-glibc-windows:v1.0.0-rust1.94-trixie

ARG RUST_VERSION=1.94
ARG DEBIAN_VARIANT=trixie

FROM rust:${RUST_VERSION}-slim-${DEBIAN_VARIANT}

# Mingw cross toolchains (64-bit + 32-bit) plus the basics rustc needs.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        gcc-mingw-w64-i686 \
        gcc-mingw-w64-x86-64 \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN rustup component add clippy rustfmt \
    && rustup target add x86_64-pc-windows-gnu i686-pc-windows-gnu
