# OCI Images

This repo contains OCI images built with Docker BuildKit (`docker buildx`) and orchestrated by Nushell scripts.
Images are published to GitHub Container Registry (`ghcr.io/niceguyit/`).

## Building

Each image has a `Dockerfile`, `build.nu` orchestrator, and `config.yml`:

```bash
cd <image-dir> && ./build.nu base
```

## Images

### openSUSE Leap 16.0

The `opensuse-base` image is an openSUSE Leap 16.0 development environment with pre-installed single-file binaries
and packages. There are two variants:

1. **base** — For CI pipelines. Includes container tools (buildah, docker, docker-compose, docker-buildx),
   git, Node.js, and Nushell with plugins.
2. **dev** — For development. Adds JetBrains remote development support (Java 21), PostgreSQL 17, Rust 1.93,
   C/C++ toolchain (clang, gcc), Dioxus dependencies, dotfiles (chezmoi), and additional tools
   (claude-code, starship, ripgrep, fd, etc.).

Build variants:

```bash
cd opensuse-base && ./build.nu base
cd opensuse-base && ./build.nu dev
```

### Rust builder

Pre-baked Rust toolchain images for downstream OCI / package builds. Each consumer drops onto one image with a single
`FROM` line and zero `apt-get install` / `apk add` / `rustup component add` / `cargo binstall` of its own.

Images are organized around the C runtime, since that is the dimension that splits the dependency set in half. Space
inside an image is cheap relative to the per-build cost of installing tooling, so each image is intentionally a
kitchen sink.

1. **`rust-builder-glibc`** (Debian trixie) - Rust 1.94 + every glibc-compatible build dependency the org uses:
   pkg-config, libssl-dev, build-essential, lld, libsqlite3-dev, libgit2-dev, zlib1g-dev, the full Dioxus desktop
   stack (libwebkit2gtk-4.1-dev, libgtk-3-dev, libsoup-3.0-dev, libxdo-dev, libayatana-appindicator3-dev,
   librsvg2-dev, libjavascriptcoregtk-4.1-dev), eframe Wayland + X11 + OpenGL + fontconfig deps, libudev / libusb /
   libxkbcommon for HID/USB device access, nodejs/npm + bun for asset bundling, dioxus-cli (pinned), cargo-binstall,
   cargo-watch, cargo-chef, the WASM target, and rustfmt + clippy.
2. **`rust-builder-musl`** (Alpine 3) - Rust 1.94 + every musl-compatible build dependency: musl-dev, pkgconfig,
   openssl-dev + openssl-libs-static, sqlite-static, lld, perl + make + linux-headers (for openssl-sys / ring),
   bash + curl + wget + git + ffmpeg, cargo-binstall, cargo-watch, the WASM target, and rustfmt + clippy.
3. **`rust-builder-glibc-windows`** (Debian trixie) - Rust 1.94 + mingw-w64 cross toolchain (32-bit + 64-bit) +
   `x86_64-pc-windows-gnu` + `i686-pc-windows-gnu` rustup targets. Separate image because the mingw toolchain is
   large (~1.5GB) and only one consumer (`da-os`) needs it; scope expected to deviate (msvc target, additional CRTs).

Versions live in each image's `config.yml`; bump there to roll a new tag.

```bash
cd rust-builder-glibc && ./build.nu
cd rust-builder-musl && ./build.nu
cd rust-builder-glibc-windows && ./build.nu
```

Tag scheme encodes Rust + base distro:

```
rust-builder-glibc:v1.0.0-rust1.94-trixie
rust-builder-musl:v1.0.0-rust1.94-alpine
rust-builder-glibc-windows:v1.0.0-rust1.94-trixie
```

### WordPress

The `wordpress` image extends the official `wordpress:6.8.1-php8.4-fpm-alpine` image with additional PHP extensions:

- pdo, pdo_mysql, soap (compiled)
- Redis 6.2.0 (PECL)
- Xdebug 3.4.3 (PECL, non-production only — disabled when `ENVIRONMENT=prod`)

```bash
cd wordpress && ./build.nu base
```

### FrankenPHP WordPress

The `frankenphp-wordpress` image is a statically compiled FrankenPHP binary (musl) that bundles the PHP 8.4
interpreter, Caddy web server, and WordPress 6.8.1 into a single image. It is based on the
[FrankenWP](https://github.com/StephenMiracle/frankenwp/) project.

**PHP extensions** (compiled into the static binary):
bcmath, ctype, curl, dom, exif, fileinfo, filter, gd, iconv, imagick, intl, ldap, mbregex, mbstring,
mysqli, mysqlnd, opcache, openssl, pdo, pdo\_mysql, phar, posix, readline, redis, session, simplexml,
soap, sockets, sodium, ssh2, tokenizer, xml, xmlreader, xmlwriter, xz, zip, zlib, zstd

**Caddy modules:**
- [caddy-cbrotli](https://github.com/dunglas/caddy-cbrotli) — Brotli compression
- [Mercure](https://github.com/dunglas/mercure) — Real-time push
- [Vulcain](https://github.com/dunglas/vulcain) — HTTP/2+ server push
- [FrankenWP cache](https://github.com/StephenMiracle/frankenwp) — WordPress caching middleware (`wp_cache`)

**Features:**
- Fully static musl binary (no runtime dependencies beyond Alpine base)
- WordPress entrypoint modified for FrankenPHP (copies WP core on first run)
- WP-CLI available via `wp` (invokes FrankenPHP's embedded PHP)
- `FORCE_HTTPS` environment variable for reverse proxy setups
- No `VOLUME` directive — bind-mount `wp-content` explicitly to avoid masking issues
- Configurable via environment variables (`SERVER_NAME`, `CACHE_LOC`, `TTL`, `FRANKENPHP_CONFIG`, etc.)

```bash
cd frankenphp-wordpress && ./build.nu base
```

### smartctl\_exporter

The `smartctl_exporter` image repackages the Prometheus
[smartctl-exporter](https://github.com/prometheus-community/smartctl_exporter) (v0.14.0) to run as the `nobody` user
instead of root.

```bash
cd smartctl_exporter && ./build.nu base
```

### Tactical RMM

[Tactical RMM](https://github.com/amidaware/tacticalrmm) is built from the `tactical-rmm/` directory, which packages
five custom images plus the stock `postgres:13-alpine` and `redis:6.0-alpine` dependencies. MeshCentral runs against
its built-in NeDB store, so no MongoDB container is needed. The single shared `tactical-rmm/config.yml` pins the
upstream Tactical RMM release; every image downloads the source tarball at that tag during build, so a version bump
is a single-line change that rebuilds all five images together.


| Image                  | Purpose                                                                   | Notes                                                                                                                                                                    |
|------------------------|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `tactical-backend`     | Django API, Celery worker, Celery beat, Daphne websockets, init container | Single image dispatched by the entrypoint via the first argument (`tactical-init`, `tactical-backend`, `tactical-celery`, `tactical-celerybeat`, `tactical-websockets`). |
| `tactical-frontend`    | Vue.js bundle on `nginx-unprivileged`                                     | The matching `tacticalrmm-web` release is pulled at build time using the `WEB_VERSION` recorded in upstream `settings.py`.                                               |
| `tactical-meshcentral` | MeshCentral remote-access server                                          | The MeshCentral version is pulled from the upstream `MESH_VER` constant in `settings.py`. Uses the built-in NeDB store under `meshcentral-data` (no MongoDB required).   |
| `tactical-nats`        | NATS server plus the upstream `nats-api` Go binary under `supervisord`    | Multi-arch aware: selects the upstream-shipped `nats-api` (amd64) or `nats-api-arm64` based on `TARGETARCH`.                                                             |
| `tactical-nginx`       | TLS-terminating reverse proxy                                             | Generates a self-signed wildcard cert at start if `CERT_PUB_KEY` / `CERT_PRIV_KEY` are not provided.                                                                     |

Build all five locally (single command):

```bash
cd tactical-rmm && ./build.nu
```

Or build a single component when iterating:

```bash
cd tactical-rmm && ./build.nu backend
```

Run the stack:

```bash
cd tactical-rmm
cp .env.example .env
# edit .env: hostnames, admin credentials, database passwords
docker compose --file compose.example.yml up --detach
```

After the first start, watch `tactical-init` until it exits successfully (it creates the Django superuser, runs
migrations, and writes the MeshCentral token). The web UI is served by `tactical-nginx` on `${TRMM_HTTPS_PORT}`.

Verify a deployment end-to-end with `tactical-rmm/test.nu`. Given a domain (or explicit hosts) and an `X-API-KEY`, it
exercises every public protocol surface in the stack: DNS, TLS, HTTP-to-HTTPS redirects, the Vue frontend SPA, the
Django REST API (with and without auth), Django Channels websockets, the NATS websocket bridge, nginx static-file
serving, and MeshCentral. The run is read-only: nothing in the deployment is mutated.

```bash
cd tactical-rmm
./test.nu --domain example.com --api-key <KEY>

# explicit per-host overrides
./test.nu --app-host rmm.x.com --api-host api.x.com --mesh-host mesh.x.com --api-key <KEY>

# self-signed certs + optional MeshCentral login probe
./test.nu --domain example.com --api-key <KEY> --mesh-user tactical --mesh-pass <PASS> --insecure
```

Each test prints `[ PASS ]` or `[ FAIL ]` live; the script summarizes counts and exits non-zero on any failure, so it
slots into a CI pipeline or a post-change check.
