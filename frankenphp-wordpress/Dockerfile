ARG WORDPRESS_TAG=6.8.1-php8.4-fpm-alpine

# Stage 1: Build static FrankenPHP binary (PHP + extensions + Caddy + modules)
FROM dunglas/frankenphp:static-builder-musl AS builder

ARG PHP_VERSION
ARG PHP_EXTENSIONS
ARG XCADDY_ARGS

ENV PHP_VERSION=${PHP_VERSION}
ENV PHP_EXTENSIONS=${PHP_EXTENSIONS}
ENV XCADDY_ARGS=${XCADDY_ARGS}

WORKDIR /go/src/app

# Download FrankenWP cache middleware source for local xcaddy build reference.
# Using a local copy avoids Go module resolution failures with the remote path.
RUN mkdir -p cache && \
	curl -fsSL https://raw.githubusercontent.com/StephenMiracle/frankenwp/main/sidekick/middleware/cache/cache.go -o cache/cache.go && \
	curl -fsSL https://raw.githubusercontent.com/StephenMiracle/frankenwp/main/sidekick/middleware/cache/store.go -o cache/store.go && \
	curl -fsSL https://raw.githubusercontent.com/StephenMiracle/frankenwp/main/sidekick/middleware/cache/writer.go -o cache/writer.go && \
	curl -fsSL https://raw.githubusercontent.com/StephenMiracle/frankenwp/main/sidekick/middleware/cache/go.mod -o cache/go.mod && \
	curl -fsSL https://raw.githubusercontent.com/StephenMiracle/frankenwp/main/sidekick/middleware/cache/go.sum -o cache/go.sum

# Build static binary with all PHP extensions and Caddy modules.
# GitHub token (if provided) avoids API rate limits during source downloads.
RUN --mount=type=secret,id=github-token \
	GITHUB_TOKEN=$(cat /run/secrets/github-token 2>/dev/null || true) \
	./build-static.sh

# Rename to architecture-independent path for the COPY in the runtime stage.
RUN cp dist/frankenphp-linux-$(uname -m) dist/frankenphp

# Stage 2: WordPress source files
FROM wordpress:${WORDPRESS_TAG} AS wordpress

# Stage 3: Runtime image
FROM alpine:3 AS runtime

RUN apk add --no-cache \
	bash \
	ca-certificates \
	curl \
	ghostscript \
	less \
	libcap

# Static FrankenPHP binary (PHP interpreter + Caddy + extensions compiled in)
COPY --from=builder /go/src/app/dist/frankenphp /usr/local/bin/frankenphp
RUN chmod +x /usr/local/bin/frankenphp && \
	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp

# PHP configuration directory (static binary reads ini from PHP_INI_SCAN_DIR)
ENV PHP_INI_DIR=/usr/local/etc/php
ENV PHP_INI_SCAN_DIR=${PHP_INI_DIR}/conf.d
RUN mkdir -p ${PHP_INI_DIR}/conf.d
COPY php.ini ${PHP_INI_DIR}/conf.d/wordpress.ini

# WordPress source (entrypoint copies to /var/www/html on first run)
COPY --from=wordpress /usr/src/wordpress /usr/src/wordpress
COPY --from=wordpress /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Add FORCE_HTTPS support and set direct filesystem access for WordPress
RUN sed -i 's/<?php/<?php if (!!getenv("FORCE_HTTPS")) { $_SERVER["HTTPS"] = "on"; } define("FS_METHOD", "direct"); set_time_limit(300); /g' \
	/usr/src/wordpress/wp-config-docker.php

# Modify WordPress entrypoint to detect FrankenPHP instead of php-fpm
RUN sed -i \
	-e 's/\[ "$1" = '\''php-fpm'\'' \]/[[ "$1" == frankenphp* ]]/g' \
	-e 's/php-fpm/frankenphp/g' \
	/usr/local/bin/docker-entrypoint.sh

# Caddyfile with FrankenWP wp_cache middleware
COPY Caddyfile /etc/caddy/Caddyfile

# WP-CLI via FrankenPHP's embedded PHP interpreter
ADD https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar /usr/local/bin/wp-cli.phar
COPY wp-cli.sh /usr/local/bin/wp
RUN chmod +x /usr/local/bin/wp-cli.phar /usr/local/bin/wp

# Create required directories (no VOLUME directive — bind-mount wp-content explicitly)
RUN mkdir -p /data/caddy /config/caddy /var/www/html

# Non-root user
RUN adduser -D -H www-data 2>/dev/null; \
	chown -R www-data:www-data \
		/data/caddy \
		/config/caddy \
		/var/www/html \
		/usr/src/wordpress \
		/usr/local/bin/docker-entrypoint.sh

ENV WP_DEBUG=0
ENV FORCE_HTTPS=0

WORKDIR /var/www/html

EXPOSE 80 443 2019

USER www-data

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
