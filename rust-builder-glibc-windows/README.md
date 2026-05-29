# rust-builder-glibc-windows

Debian trixie + Rust 1.94 + the mingw-w64 cross toolchain (32-bit and 64-bit) and the `x86_64-pc-windows-gnu` / `i686-pc-windows-gnu` rustup targets. Used to cross-compile Rust projects to Windows on a Linux runner. See the root [README](../README.md) for the build command and tag scheme.

## The OpenSSL cross-compile problem

Rust projects that use the libgit2 git stack (`git2` -> `libgit2-sys` -> `libssh2-sys` -> `openssl-sys`) or `reqwest`'s default `native-tls` link OpenSSL, a C dependency. Cross-compiling those to `x86_64-pc-windows-gnu` fails out of the box, and the failure has two distinct causes that need two different fixes. This bit `forgejo-cli` (`fj`); the notes below are so the next consumer does not rediscover it.

### Cause 1: the Windows TARGET has no OpenSSL

`openssl-sys` built for the `*-windows-gnu` target needs a Windows OpenSSL. There is no `x86_64-w64-mingw32` OpenSSL package on Debian (the `mingw-w64` packages ship gcc/binutils/CRT only), so the build aborts with:

```
error: failed to run custom build command for `openssl-sys vX`
  Could not find directory of OpenSSL installation ...
  X86_64_PC_WINDOWS_GNU_OPENSSL_DIR ...
```

The only practical fix is to **vendor** OpenSSL: the `openssl` crate's `vendored` feature pulls `openssl-src`, which builds OpenSSL from source for the target using the mingw gcc. That build needs `make` and a full `perl` (the slim base ships only `perl-base`, which lacks the core modules OpenSSL's `Configure` needs: `FindBin`, `File::Copy`, `File::Compare`, `IPC::Cmd`, `Pod::Usage`). This is a per-consumer choice (it changes the consumer's `Cargo.toml`), so the image cannot do it for you; the image's job is to make sure `perl` + `make` are available so the vendored build can run. See "What the consumer must do" below.

### Cause 2: the HOST also needs OpenSSL

When cross-compiling, build scripts run on the build host (linux). If any dependency *build-script* links a git crate, an `openssl-sys` instance is compiled for the host too. For example `ssh2-config` has an unconditional `[build-dependencies] git2`, which drags `libgit2-sys` -> `openssl-sys` into the host graph. That host `openssl-sys` looks for a system OpenSSL and fails with the same "Could not find directory of OpenSSL installation" message but with `$TARGET = x86_64-unknown-linux-gnu`.

Consumer-side `cfg(windows)` vendoring does **not** fix this one: build-dependencies compile for the host and use a separate feature set, so the host `openssl-sys` stays unvendored. The fix is to provide a host OpenSSL, i.e. `libssl-dev`.

## What this image provides

As of `v1.1.0` the image ships, on top of the mingw toolchain:

- full `perl` (the base ships only `perl-base`) and `make` - so a consumer can vendor the Windows-target OpenSSL via `openssl-src`.
- `libssl-dev` - so the host-side `openssl-sys` (from build-script git crates like `ssh2-config` -> `git2`) links the system OpenSSL.

This mirrors the sibling `rust-builder-glibc` image, which already ships `libssl-dev` + `build-essential`. Per the repo's kitchen-sink philosophy, consumers should not `apt-get install` anything of their own.

## What the consumer must do

The image cannot vendor the target OpenSSL for you (it is a `Cargo.toml` change). Add, in the crate that builds the binary:

```toml
# No Windows OpenSSL package exists, so build it from source for Windows targets
# only. openssl-sys uses `links = "openssl"`, so this single vendored feature
# unifies across the whole graph (git2 + reqwest) for the Windows build; native
# Linux builds keep using the distro OpenSSL.
[target.'cfg(windows)'.dependencies.openssl]
version = "0.10"
features = ["vendored"]
```

Then refresh `Cargo.lock` (it gains `openssl-src`) and commit it. Worked example: `forgejo-cli` (`fj`), `crates/fj/Cargo.toml` + `oci-build/Dockerfile.windows`.

## Why not vendor the host OpenSSL too (and drop libssl-dev)?

A consumer can vendor the host `openssl-sys` with an unconditional `[build-dependencies] openssl` (vendored), avoiding `libssl-dev`. We chose system `libssl-dev` in the image instead because the unconditional build-dependency also vendors OpenSSL on native Linux builds, adding ~30-60s of from-source OpenSSL compilation to every Linux build for no benefit. Keeping `libssl-dev` in the image leaves native Linux builds untouched.
