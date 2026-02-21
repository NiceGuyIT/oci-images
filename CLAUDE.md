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
# openSUSE base images (supports base and dev variants)
cd opensuse-base && ./build.nu base
cd opensuse-base && ./build.nu dev

# Other images (base variant only)
cd wordpress && ./build.nu base
cd smartctl_exporter && ./build.nu base
cd frankenphp-wordpress && ./build.nu base
```

### Build Architecture

- **Dockerfile** - Declarative image definition using Docker BuildKit
- **build.nu** - Thin Nushell orchestrator: reads `config.yml`, computes tags, calls `docker buildx build` with `--build-arg` and `--load`
- **config.yml** - Image-specific configuration (versions, packages, extensions)
- **setup.nu** (opensuse-base only) - Runs inside the container: handles parallel binary downloads via `par-each`, user creation, and tool installation

## Architecture

```
oci-images/
├── opensuse-base/          # openSUSE Leap 16.0 dev environment (multi-target: base/dev)
│   ├── Dockerfile          # Multi-target Dockerfile (--target base or --target dev)
│   ├── build.nu            # Orchestrator with semver tag computation
│   ├── setup.nu            # Runs inside container: binary downloads, user setup, tool install
│   └── config.yml
├── wordpress/              # PHP/WordPress with Redis, Xdebug
│   ├── Dockerfile          # Conditional xdebug install via build arg
│   ├── build.nu
│   └── config.yml
├── smartctl_exporter/      # Prometheus S.M.A.R.T. exporter
│   ├── Dockerfile
│   ├── build.nu
│   └── config.yml
└── frankenphp-wordpress/   # FrankenPHP + WordPress + Caddy
    ├── Dockerfile          # Multi-stage: caddy-builder, frankenphp-builder, runtime
    ├── build.nu
    └── config.yml
```

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `build-and-push-image.yml` - Reusable workflow template (uses `docker/setup-buildx-action`, `docker/login-action`, Nushell)
- Individual workflows trigger on push to image directories or template changes
- Builds run on Ubuntu 24.04 with Nushell 0.101.0
- Build step uses `--load` to load images locally; push step tags and pushes to GHCR
- Output written to `GITHUB_OUTPUT` (or `output.log` locally)

## Safety Rules

- **NEVER use force flags** in commands. For example: no `rm -rf`, no `save --force`, no `--force` on any command. If a command fails without force, the error reveals a logic bug that needs to be fixed properly, not suppressed.

## Code Style

- **Formatter:** Prettier
- **Indentation:** Tabs (4 spaces width), except YAML (2 spaces)
- **Line length:** 120 characters
- **Spell check:** cspell with custom dictionary for container terms
