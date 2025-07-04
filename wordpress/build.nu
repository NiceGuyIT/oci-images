#!/usr/bin/env nu

# Are we running in the root namespace?
def isRootNamespace []: nothing -> bool {
	let namespace = (
		open /proc/self/uid_map
		| parse --regex '\s*(?<start_uid_namespace>[^\s]+)\s*(?<start_uid_host>[^\s]+)\s*(?<length_uid>[^\s]+)'
		| into int start_uid_namespace start_uid_host length_uid
	)
	mut root_namespace = false
	if ($namespace.start_uid_namespace.0 == 0) and ($namespace.start_uid_host.0 == 0) {
		$root_namespace = true
	}
	use std log
	log info $"namespace: ($namespace)"
	log info $"Root namespace: ($root_namespace)"
	return $root_namespace
}

# Are we running in a container?
# https://forums.docker.com/t/detect-you-are-running-in-a-docker-container-buildx/139673/4
def isContainer []: nothing -> bool {
	let cgroup = (open /proc/1/cgroup | str trim)
	mut container = false
	if ($cgroup == '0::/') {
		$container = true
	}
	use std log
	log info $"cgroup: '($cgroup)'"
	log info $"Container: ($container)"
	return $container
}

# Get the permissions from the seccomp.json.
def get_seccomp [
	--name: string		# Name of permission to get
]: nothing -> string {
	let seccomp = "/usr/share/containers/seccomp.json"
	if not ($seccomp | path exists) {
		use std log
		log error $"File does not exist: '($seccomp)'"
		return ""
	}
	return (open $seccomp | get syscalls | where {$name in $in.names} | get action.0)
}

def check_sysctl []: nothing -> nothing {
	use std log
	let unprivileged_userns_clone = "/proc/sys/kernel/unprivileged_userns_clone"
	if ($unprivileged_userns_clone | path exists) {
		log info $"unprivileged_userns_clone: (open $unprivileged_userns_clone | str trim)"
	} else {
		log info $"unprivileged_userns_clone: Permission does not exist"
	}
}

# Main script
def main [] {
	use std log

	# 'buildah mount' can not be run in userspace. This script needs to be run as 'buildah unshare build.nu'
	# This detects if we are in the host namespace and runs the script with 'unshare' if we are.
	# https://opensource.com/article/19/3/tips-tricks-rootless-buildah
	# https://unix.stackexchange.com/questions/619664/how-can-i-test-that-a-buildah-script-is-run-under-buildah-unshare
	let is_container = (isContainer)
	let is_root_namespace = (isRootNamespace)
	let unshare_permission = (get_seccomp --name "unshare")
	let clone_permission = (get_seccomp --name "clone")
	log info $"is_container: ($is_container)"
	log info $"is_root_namespace: ($is_root_namespace)"
	log info $"unshare_permission: ($unshare_permission)"
	log info $"clone_permission: ($clone_permission)"

	check_sysctl

	log info "Running 'unshare --user id'"
	try {
		^unshare --user id
	} catch {|err|
		log warning $"Failed to run unshare --user: '($err.msg)'"
	}

	log info "Running 'unshare --mount id'"
	try {
		^unshare --mount id
	} catch {|err|
		log warning $"Failed to run unshare --mount: '($err.msg)'"
	}

	if ($is_container) {
		log info "Detected container. Using chroot isolation."
		$env.BUILDAH_ISOLATION = "chroot"
	} else if ($is_root_namespace) {
		# unshare cannot be run in certain environments.
		# https://github.com/containers/buildah/issues/1901
		# Dockers/containerd blocks unshare and mount. Podman, Buildah, CRI-O do not.
		log info "Detected root namespace and not in container. Rerunning in a 'buildah unshare' environment."
		^buildah unshare ./build.nu
		exit 0
	}

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
	let config = (if ("config.yml" | path exists) {open config.yml})

	# WordPress
	# Docker: https://hub.docker.com/_/wordpress
	# Download: https://wordpress.org/download/releases/
	# https://wordpress.org/documentation/article/wordpress-versions/#planned-versions
	let wordpress_docker_tag = (
		[
			$config.wordpress.version
			$"php($config.php.version)"
			"fpm"
			"alpine"
		] | str join '-'
	)

	# Build debug/dev image or production?
	# "prod" == production
	# anything else == debug
	let environment = ($env.ENVIRONMENT? | default "debug")

	# The image version does not include the WordPress version because the WordPress version is determined
	# by the data, not the image.
	let image_version = (
		[
			$"php($config.php.version)"
			$"redis($config.redis.version)"
			(if $environment != "prod" {$"xdebug($config.xdebug.version)"})
		]
		| str join '-'
		# $xdebug_version may be blank causing an extra '-' at the end of the string.
		| str trim --char '-'
	)

	let wordpress = (^buildah from $"docker.io/wordpress:($wordpress_docker_tag)")

	^buildah config --workingdir /var/www/html $wordpress

	# apt-get is not in alpine; use apk
	# TODO: Look into --virtual
	# https://github.com/docker-library/php/issues/769#issuecomment-517462110

	# Note: $PHPIZE_DEPS refers to the PHP dependencies that need to be installed in Docker.
	# https://github.com/docker-library/php/blob/master/8.3/alpine3.20/cli/Dockerfile
	# https://www.php.net/manual/en/install.pecl.phpize.php
	log info "========================================\n\n"
	log info "Running apk add pcre-dev libxml2-dev $PHPIZE_DEPS"
	timeit {^buildah run $wordpress -- bash -c "apk add pcre-dev libxml2-dev $PHPIZE_DEPS"}

	log info "========================================\n\n"
	log info "Running docker-php-ext-install pdo pdo_mysql soap"
	timeit {^buildah run $wordpress docker-php-ext-install pdo pdo_mysql soap}

	log info "========================================\n\n"
	log info "Running pecl install redis"
	timeit {^buildah run $wordpress -- bash -c $"echo | pecl install redis-($config.redis.version)"}

	log info $"========================================\n\n"
	log info $"Running docker-php-ext-enable redis"
	timeit {^buildah run $wordpress docker-php-ext-enable redis}

	if $environment != "prod" {
		log info "========================================\n\n"
		log info "Running apk add linux-headers"
		timeit {^buildah run $wordpress -- bash -c $"apk add linux-headers"}

		log info "========================================\n\n"
		log info "Running pecl install xdebug"
		timeit {^buildah run $wordpress -- bash -c $"echo | pecl install xdebug-($config.xdebug.version)"}

		log info $"========================================\n\n"
		log info $"Running docker-php-ext-enable xdebug"
		timeit {^buildah run $wordpress docker-php-ext-enable xdebug}
	}

	# Publish the container as an image in buildah.
	let published_name = $config.published.name

	# Publish the container as an image (in buildah).
	let image = (^buildah commit $wordpress $published_name)
	log info $"Built image '($published_name)' version '($image_version)'"

	# Publish the image to Docker for use.
	^buildah push $image $"docker-daemon:($published_name):($image_version)"
	log info $"Published image '($published_name)' version '($image_version)' to Docker."

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
	$"image=($published_name)\n" | save --append $output
	$"tags=($image_version)\n" | save --append $output

}
