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
#
# perl + make + libssl-dev exist for the OpenSSL C dependency that Rust git
# crates pull (git2 -> libgit2-sys -> libssh2-sys -> openssl-sys, and reqwest's
# native-tls):
#   - perl + make: let a consumer vendor the *target* OpenSSL (openssl
#     `vendored` feature -> openssl-src builds OpenSSL from source). There is no
#     x86_64-w64-mingw32 OpenSSL package, so vendoring is the only way to get a
#     Windows OpenSSL. The base only ships perl-base, which lacks the core
#     modules OpenSSL's Configure needs (FindBin, File::Copy, File::Compare,
#     IPC::Cmd, Pod::Usage), so the full perl package is required.
#   - libssl-dev: satisfies the *host* openssl-sys that gets compiled for the
#     build host whenever a dependency build-script links a git crate (e.g.
#     ssh2-config build-depends on git2). Mirrors rust-builder-glibc, which
#     already ships libssl-dev + build-essential. See README.md.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        gcc-mingw-w64-i686 \
        gcc-mingw-w64-x86-64 \
        libssl-dev \
        make \
        perl \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN rustup component add clippy rustfmt \
    && rustup target add x86_64-pc-windows-gnu i686-pc-windows-gnu
