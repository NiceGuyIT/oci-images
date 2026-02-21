# Stage 1: Caddy builder - provides xcaddy binary
ARG CADDY_VERSION=2.10
FROM docker.io/caddy:${CADDY_VERSION}-builder AS caddy-builder

# Stage 2: FrankenPHP builder - builds custom FrankenPHP binary with Caddy modules and PHP extensions
ARG PHP_VERSION=8.4
FROM docker.io/dunglas/frankenphp:builder-php${PHP_VERSION} AS frankenphp-builder

# Copy xcaddy from caddy-builder
COPY --from=caddy-builder /usr/bin/xcaddy /usr/bin/xcaddy

WORKDIR /build

# Build FrankenPHP with custom Caddy modules
# Get PHP build flags for CGO
RUN export CGO_ENABLED=1 \
	&& export XCADDY_SETCAP=1 \
	&& export XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
	&& export CGO_CFLAGS="$(php-config --includes)" \
	&& export CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
	&& xcaddy build \
		--output /usr/local/bin/frankenphp \
		--with github.com/dunglas/frankenphp=./ \
		--with github.com/dunglas/frankenphp/caddy=./caddy \
		--with github.com/dunglas/caddy-cbrotli \
		--with github.com/dunglas/mercure/caddy \
		--with github.com/dunglas/vulcain/caddy

# Install system dependencies for PHP extensions
RUN apt-get update \
	&& apt-get install -y \
		curl tar ca-certificates libxml2-dev \
		libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev \
		libzip-dev libicu-dev libmagickwand-dev \
	&& rm -rf /var/lib/apt/lists/*

# Install PHP extensions for WordPress
RUN install-php-extensions \
	bcmath exif gd intl imagick/imagick@master \
	mysqli pdo pdo_mysql opcache soap zip

# Download Caddyfile from frankenwp GitHub repository
RUN curl -o /etc/caddy/Caddyfile https://raw.githubusercontent.com/dunglas/frankenwp/main/Caddyfile

# Stage 3: Runtime - lean image with only what's needed to run
ARG PHP_VERSION=8.4
ARG FRANKENPHP_VERSION=1.9
FROM docker.io/dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION} AS runtime

# Copy built FrankenPHP binary from builder
COPY --from=frankenphp-builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Copy PHP extensions and config from builder
COPY --from=frankenphp-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=frankenphp-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy Caddyfile from builder
COPY --from=frankenphp-builder /etc/caddy/Caddyfile /etc/caddy/Caddyfile

EXPOSE 8080
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
