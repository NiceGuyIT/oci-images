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

# Contains versions of packages to install.
# xdebug: https://pecl.php.net/package/xdebug
# Redis: https://pecl.php.net/package/redis
# PHP: https://www.php.net/supported-versions.php
# WordPress: https://hub.docker.com/_/wordpress
let config = (open config.yml)

# WordPress
# Docker: https://hub.docker.com/_/wordpress
# Download: https://wordpress.org/download/releases/
# https://wordpress.org/documentation/article/wordpress-versions/#planned-versions
# let wordpress_docker_tag = (
# 	[
# 		$config.wordpress.version
# 		$"php($config.php.version)"
# 		"fpm"
# 		"alpine"
# 	] | str join '-'
# )

# Build debug/dev image or production?
# "prod" == production
# anything else == debug
let environment = ($env.ENVIRONMENT | default "debug")

# Image name
# let image_name = $"wordpress-redis-pdo"
let image_name = $"smartctl-exporter-noroot"
# The image version does not include the WordPress version because the WordPress version is determined
# by the data, not the image.
# let image_version = (
# 	[
# 		$"php($config.php.version)"
# 		$"redis($config.redis.version)"
# 		(if $environment != "prod" {"debug"})
# 	]
# 	| str join '-'
# 	# $xdebug_version may be blank causing an extra '-' at the end of the string.
# 	| str trim --char '-'
# )

let smartctl_exporter_tag = $config.smartctl_exporter.version
let image_version = $"smartctl-exporter-noroot-($smartctl_exporter_tag)"

let smartctl_exporter = (^buildah from $"docker.io/prometheuscommunity/smartctl-exporter:($smartctl_exporter_tag)")


# ^buildah config --workingdir /var/www/html $smartctl_exporter

# apt-get is not in alpine; use apk
# TODO: Look into --virtual
# https://github.com/docker-library/php/issues/769#issuecomment-517462110

# Note: $PHPIZE_DEPS refers to the PHP dependencies that need to be installed in Docker.
# https://github.com/docker-library/php/blob/master/8.3/alpine3.20/cli/Dockerfile
# https://www.php.net/manual/en/install.pecl.phpize.php

log info $"========================================\n\n"
log info $"Setting user to root"
timeit {^buildah config --user root $smartctl_exporter}


log info "========================================\n\n"
log info "Running apk add shadow"
timeit {^buildah run $smartctl_exporter -- sh -c "apk add shadow"}

log info $"========================================\n\n"
log info $"Exposing port 9633"
timeit {^buildah config --port 9633 $smartctl_exporter}


# if $environment != "prod" {
# 	log info "========================================\n\n"
# 	log info "Running apk add linux-headers"
# 	timeit {^buildah run $smartctl_exporter -- sh -c $"apk add linux-headers"}

# 	# log info "========================================\n\n"
# 	# log info "Running pecl install xdebug"
# 	# timeit {^buildah run $smartctl_exporter -- bash -c $"echo | pecl install xdebug-($config.xdebug.version)"}
# }

log info $"========================================\n\n"
log info $"Setting user to nobody"
timeit {^buildah config --user nobody $smartctl_exporter}

log info $"========================================\n\n"
log info $"Setting entrypoint to /bin/smartctl_exporter"
timeit {^buildah config --entrypoint /bin/smartctl_exporter $smartctl_exporter}

# Publish the container as an image (in buildah).
let image = (^buildah commit $smartctl_exporter $image_name)
log info $"Built image '($image_name)' version '($image_version)'"

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

mut output = "output.log"
if ("GITHUB_OUTPUT" in $env) {
	# Output the information to the GitHub action.
	$output = $env.GITHUB_OUTPUT
}
$"image=($image_name)\n" | save --append $output
$"tags=($image_version)\n" | save --append $output
