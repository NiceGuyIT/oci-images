#!/usr/bin/env nu
use std log

# Build an image that contains PDO_MYSQL.
# https://hub.docker.com/_/wordpress
# https://github.com/docker-library/docs/tree/master/php#pecl-extensions
# https://github.com/docker-library/docs/tree/master/php#how-to-install-more-php-extensions
# https://github.com/docker-library/php/blob/master/docker-php-ext-install#L92
#
# PHPIZE_DEPS is used internally when compiling PHP in Docker.
# https://github.com/docker-library/php/blob/master/8.3/alpine3.20/cli/Dockerfile
#   dependencies required for running "phpize"
#   these get automatically installed and removed by "docker-php-ext-*" (unless they're already installed)
#
# https://github.com/docker-library/php/issues/436#issuecomment-303171390
# If you are installing one of the extensions included with php source, you can use the helper scripts: see docs.
# In the alpine based images, the docker-php-ext-* scripts install the PHPIZE_DEPS as needed.
#
# DEPRECATED: The legacy builder is deprecated and will be removed in a future release.
#             Install the buildx component to build images with BuildKit:
#             https://docs.docker.com/go/buildx/

# These are the version numbers used to build the WordPress image. While WordPress can update itself,
# the other versions are not updated automatically. A new image needs to be built to update the versions.

# xdebug
# PECL: https://pecl.php.net/package/xdebug
let xdebug_version = "3.4.3"

# PHP Redis
# PECL: https://pecl.php.net/package/redis
let php_redis_version = "6.2.0"

# PHP
# https://www.php.net/supported-versions.php
# Note: The PHP version is determined by the WordPress Docker image, not this variable.
let php_version = "8.4"

# WordPress
# Docker: https://hub.docker.com/_/wordpress
# https://wordpress.org/download/releases/
# https://wordpress.org/documentation/article/wordpress-versions/#planned-versions
let wordpress_version = "6.8.1"
let wordpress_docker_tag = $"($wordpress_version)-php($php_version)-fpm-alpine"

# Build dev image or production?
let environment = "dev"

# Docker image name
let image_name = $"wordpress-redis-pdo_mysql(if $environment != "prod" {"-dev"} else {""})"
# Need a better version name when publishing to GHCR. For now, "latest" works.
# let image_version = ([$wordpress_version $php_version $php_redis_version] | str join '-')
let image_version = "latest"

let wordpress = (^buildah from $"docker.io/wordpress:($wordpress_docker_tag)")

^buildah config --workingdir /var/www/html $wordpress

# apt-get is not in alpine; use apk
# TODO: Look into --virtual
# https://github.com/docker-library/php/issues/769#issuecomment-517462110

# Note: $PHPIZE_DEPS refers to the PHP dependencies that need to be installed in Docker.
# https://github.com/docker-library/php/blob/master/8.3/alpine3.20/cli/Dockerfile
# https://www.php.net/manual/en/install.pecl.phpize.php
log info $"========================================\n\n\n"
log info $"Running apk add pcre-dev libxml2-dev $PHPIZE_DEPS"
^buildah run $wordpress -- bash -c $"apk add pcre-dev libxml2-dev $PHPIZE_DEPS (if $environment != "prod" {"linux-headers"} else {""})"

log info $"========================================\n\n\n"
log info $"Running docker-php-ext-install pdo pdo_mysql soap"
^buildah run $wordpress docker-php-ext-install pdo pdo_mysql soap

log info $"========================================\n\n\n"
log info $"Running pecl install redis"
^buildah run $wordpress -- bash -c $"echo | pecl install redis-($php_redis_version)"

if $environment != "prod" {
	log info $"========================================\n\n\n"
	log info $"Running pecl install xdebug"
	^buildah run $wordpress -- bash -c $"echo | pecl install xdebug-($xdebug_version)"
}

log info $"========================================\n\n\n"
log info $"Running docker-php-ext-enable redis"
^buildah run $wordpress docker-php-ext-enable redis (if $environment != "prod" {"xdebug"} else {""})

# Publish the container as an image (in buildah).
let image = (^buildah commit $wordpress $image_name)

# Publish the image to Docker for use.
^buildah push $image $"docker-daemon:($image_name):($image_version)"

log info $"Published image '($image_name)' version '($image_version)' to Docker."

# TODO: Add composer and wp-cli
# https://hub.docker.com/_/composer
# https://github.com/composer/composer
# Install composer from the composer image
# let composer = (^buildah from composer)
# TODO: Learn how to specify --from with buildah copy.
# https://github.com/containers/buildah/issues/2575#issuecomment-685075800
# ^buildah copy $container /usr/bin/composer /usr/local/bin/composer
# COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Install wp (WP-CLI) from the wordpress:cli image
# COPY --from=wordpress:cli /usr/local/bin/wp /usr/local/bin/wp

mut output = "output.txt"
if ("GITHUB_OUTPUT" in $env) {
	# Output the information to the GitHub action.
	$output = $env.GITHUB_OUTPUT
}
$"image=($image_name)\n" | save --append $output
$"tags=($image_version)\n" | save --append $output
