ARG WORDPRESS_TAG=6.8.1-php8.4-fpm-alpine
FROM docker.io/wordpress:${WORDPRESS_TAG}

ARG REDIS_VERSION=6.2.0
ARG XDEBUG_VERSION=3.4.3
ARG INSTALL_XDEBUG=true

WORKDIR /var/www/html

# Install PHP build dependencies and extensions
RUN apk add pcre-dev libxml2-dev $PHPIZE_DEPS \
	&& docker-php-ext-install pdo pdo_mysql soap

# Install Redis extension
RUN echo | pecl install redis-${REDIS_VERSION} \
	&& docker-php-ext-enable redis

# Optionally install Xdebug (non-production environments)
RUN if [ "${INSTALL_XDEBUG}" = "true" ]; then \
		apk add linux-headers \
		&& echo | pecl install xdebug-${XDEBUG_VERSION} \
		&& docker-php-ext-enable xdebug; \
	fi
