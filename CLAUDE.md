# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCI Images is a container image build system for creating and publishing OCI-compliant images to GitHub Container Registry (ghcr.io/niceguyit/). The repository builds specialized container images including openSUSE development environments, WordPress hosting, and monitoring tools.

## Build System

**Language:** Nushell (Nu) - All build scripts use Nushell syntax and idioms
**Container Tool:** Buildah (rootless) - Not Docker
**Registry:** GitHub Container Registry (GHCR)

### Building Images

Each image has its own directory with `build.nu` and `config.yml`:

```bash
# openSUSE base images (supports base and dev variants)
cd opensuse-base && ./build.nu base
cd opensuse-base && ./build.nu dev

# Other images (base variant only)
cd wordpress && ./build.nu base
cd smartctl_exporter && ./build.nu base
cd frankenphp-wordpress && ./build.nu base
```

### Configuration Files

- `config.yml` - Image-specific configuration (versions, packages, extensions)
- `buildah-wrapper.nu` - Core Buildah wrapper functions with namespace/isolation detection
- `dind.nu` - Docker-in-Docker initialization

## Architecture

```
oci-images/
├── buildah-wrapper.nu      # Shared Buildah functions (namespace detection, isolation modes)
├── opensuse-base/          # openSUSE Leap 16.0 dev environment
├── wordpress/              # PHP/WordPress with Redis, Xdebug
├── smartctl_exporter/      # Prometheus S.M.A.R.T. exporter
└── frankenphp-wordpress/   # FrankenPHP + WordPress + Caddy
```

**buildah-wrapper.nu** handles:
- Container environment detection (`is-container()`, `is-root-namespace()`)
- Automatic `buildah unshare` when needed
- Isolation mode selection (chroot vs user namespace)

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `build-and-push-image.yml` - Reusable workflow template
- Individual workflows trigger on push to image directories
- Builds run on Ubuntu 24.04 with Nushell 0.101.0
- Output written to `GITHUB_OUTPUT` (or `output.log` locally)

## Code Style

- **Formatter:** Prettier
- **Indentation:** Tabs (4 spaces width), except YAML (2 spaces)
- **Line length:** 120 characters
- **Spell check:** cspell with custom dictionary for container terms
