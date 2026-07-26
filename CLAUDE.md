# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCI Images is a container image build system for creating and publishing OCI-compliant images to GitHub Container Registry (ghcr.io/niceguyit/). The repository builds specialized container images including openSUSE development environments, WordPress hosting, and monitoring tools.

## Build System

**Language:** Nushell (Nu) - All build scripts use Nushell syntax and idioms
**Container Tool:** Docker BuildKit (`docker buildx build`) with Dockerfiles
**Registry:** GitHub Container Registry (GHCR)

### Building Images

Each image has its own directory with `Dockerfile`, `build.nu`, and `config.yml`:

```bash
# openSUSE images: the only build.nu that takes a variant argument
cd opensuse-base && ./build.nu base
cd opensuse-base && ./build.nu dev

# Tactical RMM: optional component argument, omit it to build all five
cd tactical-rmm && ./build.nu backend
cd tactical-rmm && ./build.nu

# Every other image takes no argument
cd coredns && ./build.nu
cd frankenphp-wordpress && ./build.nu
cd rust-builder-glibc && ./build.nu
cd rust-builder-glibc-windows && ./build.nu
cd rust-builder-musl && ./build.nu
cd smartctl_exporter && ./build.nu
cd wordpress && ./build.nu
```

### Build Architecture

- **Dockerfile** - Declarative image definition using Docker BuildKit
- **build.nu** - Thin Nushell orchestrator: reads `config.yml`, computes tags, calls `docker buildx build` with `--build-arg` and `--load`
- **config.yml** - Image-specific configuration (versions, packages, extensions)
- **setup.nu** (opensuse-base only) - Runs inside the container: handles parallel binary downloads via `par-each`, user creation, and tool installation

## Architecture

```
oci-images/
├── coredns/                    # CoreDNS built from source with the alias plugin
│   ├── Dockerfile
│   ├── build.nu
│   └── config.yml
├── frankenphp-wordpress/       # FrankenPHP + WordPress + Caddy
│   ├── Dockerfile              # Multi-stage: builder, wordpress, runtime
│   ├── build.nu
│   └── config.yml
├── opensuse-base/              # openSUSE Leap 16.0 dev environment (multi-target: base/dev)
│   ├── Dockerfile              # Multi-target Dockerfile (--target base or --target dev)
│   ├── build.nu                # Orchestrator with semver tag computation
│   ├── setup.nu                # Runs inside container: binary downloads, user setup, tool install
│   └── config.yml
├── rust-builder-glibc/         # Rust toolchain on Debian trixie (glibc build deps)
├── rust-builder-glibc-windows/ # Rust + mingw-w64 cross toolchain for *-pc-windows-gnu
├── rust-builder-musl/          # Rust toolchain on Alpine (musl build deps)
├── smartctl_exporter/          # Prometheus S.M.A.R.T. exporter, repackaged to run as nobody
│   ├── Dockerfile
│   ├── build.nu
│   └── config.yml
├── tactical-rmm/               # Five images from one shared config.yml and build.nu
│   ├── backend/Dockerfile      # Django API, Celery, Daphne, init; dispatched by first arg
│   ├── backend/entrypoint.sh   # Replaces the upstream entrypoint; hash-pinned against drift
│   ├── backend/local_settings.py # Shim: loads generated_settings.py then local_settings.py from conf/
│   ├── backend/settings_env.py # Applies TRMM_SETTING_* env vars as Django settings
│   ├── frontend/Dockerfile     # Vue.js bundle on nginx-unprivileged
│   ├── frontend/entrypoint.sh  # Fork of upstream; fast readiness poll
│   ├── meshcentral/Dockerfile  # MeshCentral, PostgreSQL-backed
│   ├── meshcentral/entrypoint.sh
│   ├── nats/Dockerfile
│   ├── nats/entrypoint.sh      # Fork of upstream; fast readiness poll
│   ├── nginx/Dockerfile
│   ├── build.nu                # Optional component arg; omit to build all five
│   ├── compose.example.yml     # Six state volumes; /opt/tactical is baked, never mounted
│   └── config.yml              # One TRMM_VERSION drives every component
└── wordpress/                  # PHP/WordPress with Redis, Xdebug
    ├── Dockerfile              # Conditional xdebug install via build arg
    ├── build.nu
    └── config.yml
```

Each `rust-builder-*` directory has the same `Dockerfile` / `build.nu` / `config.yml` layout.

`build.nu` takes an argument only in `opensuse-base` (`base` / `dev`) and `tactical-rmm` (component name, optional).
Everywhere else `main` is declared with no parameters, so passing one fails with `nu::parser::extra_positional`.

## CI/CD

GitHub Actions workflows in `.github/workflows/`:

- `build-and-push-image.yml` - Reusable workflow template (uses `docker/setup-buildx-action`, `docker/login-action`, Nushell)
- `image-type` accepts several space-separated variants (`base dev`), built in order on one runner so a stage that is `FROM` an earlier one reuses its layers. Each `build.nu` run gets a private output file and the step emits one `builds` JSON output, since duplicate `image=` keys in `GITHUB_OUTPUT` would keep only the last variant
- Individual workflows trigger on push to image directories or template changes
- Each caller workflow sets `concurrency` on workflow plus ref, so a newer push supersedes an in-flight build; it is not set in the reusable workflow, where sibling jobs share a caller and would cancel each other
- Builds run on Ubuntu 24.04 with Nushell 0.112.2, matching the `nu` version pinned in `opensuse-base/config.yml`
- Build step uses `--load` to load images locally; push step tags and pushes to GHCR
- Output written to `GITHUB_OUTPUT` (or `output.log` locally)

## Safety Rules

- **NEVER use force flags** in commands. For example: no `rm -rf`, no `save --force`, no `--force` on any command. If a command fails without force, the error reveals a logic bug that needs to be fixed properly, not suppressed.

## Code Style

- **Formatter:** Prettier, configured in `.prettierrc.json`
- **Indentation:** Tabs (4 spaces width), except YAML (2 spaces)
- **Line length:** 120 characters
- **Spell check:** cspell, configured in `cspell.json` with a project dictionary of container terms

Both tools ship inside the `opensuse-base` image (installed via bun), so run them there rather than
installing them on the host:

```bash
docker run --rm --user dev --volume "$PWD:/work:ro" --workdir /work \
	--entrypoint bash ghcr.io/niceguyit/opensuse-base:latest --login -c \
	'prettier --check "**/*.{md,yml,yaml,json}" && cspell --no-progress $(git ls-files)'
```
