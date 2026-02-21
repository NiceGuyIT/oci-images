# OCI Images

This repo contains OCI images built with Docker BuildKit (`docker buildx`) and orchestrated by Nushell scripts.

## Building

Each image has a `Dockerfile`, `build.nu` orchestrator, and `config.yml`:

```bash
cd <image-dir> && ./build.nu base
```

## smartctl_exporter

The `smartctl_exporter` image runs as the "nobody" user.

## WordPress

The `wordpress` image has the following libraries compiled in.

-   php
    -   pdo
    -   pdo_mysql
    -   soap
-   redis
-   xdebug (optional, non-production only)

## FrankenPHP WordPress

The `frankenphp-wordpress` image is a multi-stage build providing FrankenPHP with Caddy and PHP extensions for WordPress.

## openSUSE Leap 16.0

The `opensuse-base` image has a variety of single-file binaries and is used for development and CI.
There are 2 flavors:

1. base: The base image is used for CI and does not have the dotfiles installed or the development packages.
    - Note: "build" workflows use the dev image.
2. dev: The dev image is meant for development and has the dotfiles installed and many development packages.

Build variants:

```bash
cd opensuse-base && ./build.nu base
cd opensuse-base && ./build.nu dev
```
