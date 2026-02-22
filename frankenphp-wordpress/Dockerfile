# Stage 1: Static builder - compiles PHP + extensions + Caddy + FrankenPHP into a single static binary
FROM dunglas/frankenphp:static-builder-musl AS builder

ARG PHP_VERSION
ARG PHP_EXTENSIONS
ARG XCADDY_ARGS

# build-static.sh reads these environment variables
ENV PHP_VERSION=${PHP_VERSION}
ENV PHP_EXTENSIONS=${PHP_EXTENSIONS}
ENV XCADDY_ARGS=${XCADDY_ARGS}

WORKDIR /go/src/app

# Workaround: static-builder-musl ships FrankenPHP v1.11.2 which expects
# caddycmd.LoadConfig to return 3 values, but Caddy now returns 4.
# See: https://github.com/php/frankenphp/blob/main/caddy/php-server.go
# Remove this when static-builder-musl ships v1.12+.
RUN sed -i 's/config, _, err := caddycmd.LoadConfig/config, _, _, err := caddycmd.LoadConfig/' caddy/php-server.go

RUN ./build-static.sh

# Stage 2: Minimal runtime - static binary + Caddyfile in Alpine
FROM alpine:3 AS runtime

COPY --from=builder /go/src/app/dist/frankenphp-linux-x86_64 /usr/local/bin/frankenphp

RUN chmod +x /usr/local/bin/frankenphp

# Download Caddyfile from FrankenWP repository
ADD https://raw.githubusercontent.com/dunglas/frankenwp/main/Caddyfile /etc/caddy/Caddyfile

EXPOSE 8080
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
