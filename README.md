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
