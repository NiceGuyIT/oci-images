# OCI Images

This repo contains OCI images built with Docker BuildKit (`docker buildx`) and orchestrated by Nushell scripts.
Images are published to GitHub Container Registry (`ghcr.io/niceguyit/`).

## Building

Each image has a `Dockerfile`, `build.nu` orchestrator, and `config.yml`:

```bash
cd <image-dir> && ./build.nu
```

Only `opensuse-base` (`base` / `dev`) and `tactical-rmm` (component name, optional) take an argument.

## Images

### openSUSE Leap 16.0

The `opensuse-base` image is an openSUSE Leap 16.0 development environment with pre-installed single-file binaries
and packages. There are two variants:

1. **base** - For CI pipelines. Includes container tools (buildah, docker, docker-compose, docker-buildx),
   git, Node.js, Nushell with plugins, and the Forgejo (`fj`) and YouTrack (`yt`) CLIs.
2. **dev** - For development. Adds JetBrains remote development support (Java 21), PostgreSQL 17, Rust 1.94,
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
   `x86_64-pc-windows-gnu` + `i686-pc-windows-gnu` rustup targets, plus `perl` + `make` + `libssl-dev` for the OpenSSL
   C dependency that the libgit2 git stack and `reqwest` pull. Separate image because the mingw toolchain is large
   (~1.5GB); scope expected to deviate (msvc target, additional CRTs). Cross-compiling OpenSSL-linking crates to
   Windows has two gotchas (vendoring the Windows-target OpenSSL vs. the host-side `openssl-sys`); see
   [`rust-builder-glibc-windows/README.md`](rust-builder-glibc-windows/README.md).

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
rust-builder-glibc-windows:v1.1.0-rust1.94-trixie
```

### WordPress

The `wordpress` image extends the official `wordpress:6.8.1-php8.4-fpm-alpine` image with additional PHP extensions:

- pdo, pdo_mysql, soap (compiled)
- Redis 6.2.0 (PECL)
- Xdebug 3.4.3 (PECL, non-production only - disabled when `ENVIRONMENT=prod`)

```bash
cd wordpress && ./build.nu
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

- [caddy-cbrotli](https://github.com/dunglas/caddy-cbrotli) - Brotli compression
- [Mercure](https://github.com/dunglas/mercure) - Real-time push
- [Vulcain](https://github.com/dunglas/vulcain) - HTTP/2+ server push
- [FrankenWP cache](https://github.com/StephenMiracle/frankenwp) - WordPress caching middleware (`wp_cache`)

**Features:**

- Fully static musl binary (no runtime dependencies beyond Alpine base)
- WordPress entrypoint modified for FrankenPHP (copies WP core on first run)
- WP-CLI available via `wp` (invokes FrankenPHP's embedded PHP)
- `FORCE_HTTPS` environment variable for reverse proxy setups
- No `VOLUME` directive - bind-mount `wp-content` explicitly to avoid masking issues
- Configurable via environment variables (`SERVER_NAME`, `CACHE_LOC`, `TTL`, `FRANKENPHP_CONFIG`, etc.)

```bash
cd frankenphp-wordpress && ./build.nu
```

### smartctl\_exporter

The `smartctl_exporter` image repackages the Prometheus
[smartctl-exporter](https://github.com/prometheus-community/smartctl_exporter) (v0.14.0) to run as the `nobody` user
instead of root.

```bash
cd smartctl_exporter && ./build.nu
```

### Tactical RMM

[Tactical RMM](https://github.com/amidaware/tacticalrmm) is built from the `tactical-rmm/` directory, which packages
five custom images plus the stock `postgres:13-alpine` and `redis:6.0-alpine` dependencies. MeshCentral stores its
data in the shared PostgreSQL server (`MESH_POSTGRES_HOST` defaults to `tactical-postgres`), which `tactical-init`
provisions automatically; there is no NeDB or MongoDB option. The single shared `tactical-rmm/config.yml` pins the
upstream Tactical RMM release; every image downloads the source tarball at that tag during build, so a version bump
is a single-line change that rebuilds all five images together.

| Image                  | Purpose                                                                   | Notes                                                                                                                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tactical-backend`     | Django API, Celery worker, Celery beat, Daphne websockets, init container | Single image dispatched by the entrypoint via the first argument (`tactical-init`, `tactical-backend`, `tactical-celery`, `tactical-celerybeat`, `tactical-websockets`).                                                                                 |
| `tactical-frontend`    | Vue.js bundle on `nginx-unprivileged`                                     | The matching `tacticalrmm-web` release is pulled at build time using the `WEB_VERSION` recorded in upstream `settings.py`.                                                                                                                               |
| `tactical-meshcentral` | MeshCentral remote-access server                                          | The MeshCentral version is pulled from the upstream `MESH_VER` constant in `settings.py`. Stores its data in PostgreSQL only (`MESH_POSTGRES_HOST` defaults to `tactical-postgres`), which `tactical-init` provisions automatically; no NeDB or MongoDB. |
| `tactical-nats`        | NATS server plus the upstream `nats-api` Go binary under `supervisord`    | Multi-arch aware: selects the upstream-shipped `nats-api` (amd64) or `nats-api-arm64` based on `TARGETARCH`.                                                                                                                                             |
| `tactical-nginx`       | TLS-terminating reverse proxy                                             | Generates a self-signed wildcard cert at start if `CERT_PUB_KEY` / `CERT_PRIV_KEY` are not provided.                                                                                                                                                     |

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
migrations, writes the MeshCentral token, and provisions the MeshCentral PostgreSQL database when `MESH_POSTGRES_HOST`
is set). Every service that loads Django settings waits on it through
`depends_on` / `service_completed_successfully`, so nothing starts against a half-migrated database. The web UI is
served by `tactical-nginx` on `${TRMM_HTTPS_PORT}`.

#### On-disk layout

The Django tree is baked into the `tactical-backend` image at `/opt/tactical` and is **not** a volume. Upstream instead
stages it in `/tmp/tactical` and `rsync --delete`s it into a shared `/opt/tactical` volume on every start, which forces
all nine application containers to mount a volume over the whole application directory and makes each restart pay for
the copy plus a recursive `chown`. Neither happens here.

Mounting anything over `/opt/tactical` hides the baked tree, so the entrypoint checks for `/opt/tactical/.image-layout`
and aborts with a pointer to the migration steps below if it is gone. Only mutable state is mounted, in six volumes:

| Volume               | Mount point                             | Holds                                                                                     |
| -------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------- |
| `tactical-conf`      | `/opt/tactical/conf`                    | `generated_settings.py`, `local_settings.py`, `app.ini`, `nats-rmm.conf`, `nats-api.conf` |
| `tactical-tmp`       | `/opt/tactical/tmp`                     | `tactical.ready`, `mesh_token`, `web_tar_url`                                             |
| `tactical-private`   | `/opt/tactical/api/tacticalrmm/private` | Generated agent installers and Django logs, served by nginx under `/private/`             |
| `tactical-certs`     | `/opt/tactical/certs`                   | TLS material, generated by `tactical-nginx` when none is supplied                         |
| `tactical-reporting` | `/opt/tactical/reporting`               | Reporting assets uploaded through the dashboard                                           |
| `tactical-static`    | `/opt/tactical/api/static`              | `collectstatic` output, written by init and served by nginx                               |

`api/app.ini`, `api/nats-rmm.conf` and `api/nats-api.conf` are symlinks into `tactical-conf`. Three upstream management
commands write those files to `settings.BASE_DIR` with `open(..., "w")`, which follows a symlink and creates the target,
so the generated configs land in the mounted directory with no patching of upstream code. `tactical-nats` has no Django
tree, so compose mounts `tactical-conf` at `/opt/tactical/api` there and the upstream nats entrypoint finds both files
exactly where it expects them.

`tactical-conf` is mounted read-write on the Django services rather than read-only, because `reload_nats()` rewrites
`nats-rmm.conf` from the running API whenever an agent is added or removed, not only during init.

Every image contains the mount points it consumes, owned by uid 1000. A named volume is seeded from the image path it is
mounted on, so a path the image lacks would yield an empty root-owned directory that the container, running as uid 1000,
could not write.

#### Migrating an existing deployment

Deployments created before this layout keep everything in one `tactical-data` volume, which is not compatible. Because
the image tag tracks the upstream Tactical RMM version, the tag cannot signal the break; the `.image-layout` check is
what catches it. To migrate:

```bash
cd tactical-rmm
docker compose --file compose.example.yml down

# Recreate the state volumes from the old one. The application code, the
# community scripts and the static tree are not copied: they now come from the
# image and collectstatic re-runs on the next init.
docker volume create tactical-certs
docker volume create tactical-private
docker volume create tactical-reporting
for pair in "certs:tactical-certs" "api/tacticalrmm/private:tactical-private" "reporting:tactical-reporting"; do
	src="${pair%%:*}"
	dst="${pair##*:}"
	docker run --rm \
		--volume tactical-data:/old:ro \
		--volume "${dst}":/new \
		alpine sh -c "cp -a /old/${src}/. /new/ 2>/dev/null || true"
done

docker compose --file compose.example.yml up --detach
```

Keep the old `tactical-data` volume until the stack is verified, then remove it manually. Settings previously edited
into `local_settings.py` inside that volume should be re-applied to `tactical-conf/local_settings.py`, which the image
loads after the generated file and which init never rewrites.

#### Django settings from the environment

Settings resolve in three layers, each beating the one before it:

1. `conf/generated_settings.py`, rewritten by `tactical-init` on every run from the environment (database credentials,
   hostnames, the MeshCentral token, certificate and directory paths).
2. `conf/local_settings.py`, yours. `tactical-init` never writes it, so anything you put there survives a restart. Bind
   mount a host file over it, read-only if you like.
3. `TRMM_SETTING_*` environment variables, applied by `settings_env.py`.

The backend image ships `settings_env.py`, imported at the end of upstream `settings.py`, which applies every
`TRMM_SETTING_*` variable. The name after the prefix is the Django setting name, and because the import is last, these
values win over both files in `conf/` and over every upstream assignment.

```yaml
x-trmm-settings: &trmm-settings
    TRMM_SETTING_INSTALL_NUSHELL_VERSION: "0.112.2"
```

`compose.example.yml` declares that block once and merges it into the four services that load Django settings:
`tactical-backend`, `tactical-websockets`, `tactical-celery` and `tactical-celerybeat`.

##### Settings consumed at init time

Some settings are read while `tactical-init` runs, not while the service runs, and those must be in
`tactical-init`'s environment instead. Two classes: anything affecting migrations or superuser creation, and every
`UWSGI_*` knob, because `app.ini` is generated by `python manage.py create_uwsgi_conf` inside the init block
(`tactical-rmm/backend/entrypoint.sh`). `tactical-backend` only execs the finished file. Putting
`TRMM_SETTING_UWSGI_MAX_WORKERS` on `tactical-backend` is inert, and even on `tactical-init` it applies only after
init re-runs and rewrites `app.ini`.

Five uwsgi keys are hardcoded in `create_uwsgi_conf.py` and cannot be set by any `TRMM_SETTING_`: `chdir`, `module`,
`home`, `cheaper-algo`, and `socket`.

Worker count is worth capping deliberately. `create_uwsgi_conf` sizes it from RAM alone, with no CPU term: 6 workers
at 2GB or less, 20 at 4GB or less, 40 above that. A high-RAM, low-core host therefore gets 40 workers, and the
busyness cheaper (`cheaper-busyness-max` defaults to 10%) climbs toward that ceiling under light load, which can
saturate a small box and stall requests. Cap it on `tactical-init`:

```yaml
tactical-init:
    environment:
        TRMM_SETTING_UWSGI_MAX_WORKERS: "6"
        TRMM_SETTING_UWSGI_CHEAPER: "2"
        TRMM_SETTING_UWSGI_CHEAPER_INITIAL: "2"
        TRMM_SETTING_UWSGI_BUSYNESS_MAX: "50"
```

Confirm against the generated file rather than the environment, since init has to re-run for a change to land:

```bash
docker compose --file compose.example.yml exec tactical-backend grep -E "workers|cheaper" /opt/tactical/api/app.ini
```

##### uwsgi runtime options, including the listen socket

Because `socket` is hardcoded to `0.0.0.0:8080` under `DOCKER_BUILD`, no Django setting can move the uwsgi listener.
Use uWSGI's own environment mapping instead: an option is settable as `UWSGI_<OPTION>`, uppercased with dashes as
underscores, read by the uwsgi binary directly with no init re-run.

The mapping **fills in options the generated `app.ini` does not set, and is ignored for options it does**. The ini
always wins. So every key `create_uwsgi_conf` writes (`master`, `harakiri`, `workers`, `cheaper*`, `max-requests`,
`listen`, and the rest) has to be changed through `TRMM_SETTING_*` on `tactical-init`; setting `UWSGI_WORKERS` on
`tactical-backend` is silently ignored. `UWSGI_HTTP_SOCKET` is the useful exception precisely because `http-socket` is
not one of the keys the ini declares, so it adds a socket instead of replacing one.

Note also that `UWSGI_MAX_WORKERS` is a Django setting name that `create_uwsgi_conf` maps to the ini key `workers`. It
is not a uWSGI option name, so it means nothing as a `UWSGI_*` environment variable in either direction.

This matters when fronting the stack with something other than `tactical-nginx`. The stock backend socket speaks the
uwsgi binary protocol, not HTTP (`tactical-nginx` uses `uwsgi_pass`; only its `DEV=1` branch uses `proxy_pass`), so an
HTTP reverse proxy such as Caddy or Traefik needs an `http-socket` rather than a different port on the existing one:

```yaml
tactical-backend:
    environment:
        <<: *trmm-settings
        UWSGI_HTTP_SOCKET: 0.0.0.0:8081
```

Note this is a plain environment variable and deliberately **not** part of the `x-trmm-settings` anchor: it is
consumed by uwsgi, not by `settings_env.py`, so the `TRMM_SETTING_` prefix would only create a Django setting nothing
reads. Both sockets bind, so 8081 serves HTTP for the proxy while 8080 keeps the uwsgi protocol:

```bash
docker compose --file compose.example.yml logs tactical-backend | grep "bound to"
```

Values parse as JSON, so types survive: `"true"` becomes a bool and `"[30, 60]"` becomes a list, which is what
`CHECKIN_HELLO` needs. Anything JSON rejects stays a string, which covers versions like `0.112.2`. The sharp edge is a
value that is both numeric-looking and valid JSON: `"0.112"` becomes a float. Force it back to a string by quoting it
as JSON, `'"0.112"'`. Every applied setting is printed at startup with its resolved type, so check `docker logs` after
a change:

```bash
docker compose --file compose.example.yml logs tactical-backend | grep settings_env
```

`TRMM_SETTING_` is a distinct prefix on purpose. The bare `TRMM_` namespace already holds init-only values such as
`TRMM_USER` and `TRMM_PASS` that are not Django settings.

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
