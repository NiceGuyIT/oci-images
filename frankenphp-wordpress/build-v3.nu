#!/usr/bin/env nu


def copy-caddy [
	caddy_builder: string			# Caddy builder image
	frankenphp_builder: string		# FrankenPHP builder image
]: nothing -> nothing {
	let caddy_mnt = (^buildah mount $caddy_builder)
	let frankenphp_mnt = (^buildah mount $frankenphp_builder)

	mkdir $"($frankenphp_mnt)/build"
	mkdir $"($frankenphp_mnt)/build/caddy"

	# Set working dir
	^buildah config --workingdir /build $frankenphp_builder

	print $"caddy_mnt: ($caddy_mnt)"
	print $"frankenphp_mnt: ($frankenphp_mnt)"

	# "path join" does not handle joining mounted directories. Join the directories as a string.
    print $"This does not include the mount path: ([$caddy_mnt, "/usr/bin/"] | path join)"
    print $"This includes the mount path: ($caddy_mnt)/usr/bin/"
	cp $"($caddy_mnt)/usr/bin/xcaddy" $"($frankenphp_mnt)/usr/bin/"

	# Copy cache middleware into the build directory
	cp -r ./sidekick/middleware/cache $"($frankenphp_mnt)/build/"

	print (ls -l $"($frankenphp_mnt)/build/")
}

def build-caddy [
	frankenphp_builder: string		# FrankenPHP builder image
]: nothing -> nothing {
	let build_dir = '/build'

	# Build xcaddy in the build directory
	# buildah run $frankenphp_builder 'ls .'
	# return
	# let build_cmd =  [
	# 	/usr/bin/xcaddy build
	# 	--output /usr/local/bin/frankenphp
	# 	# --with github.com/dunglas/frankenphp=/build/
	# 	--with github.com/dunglas/frankenphp/caddy=/build/caddy/
	# 	--with github.com/dunglas/caddy-cbrotli
	# 	--with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=/build/cache
	# ]
	let build_cmd = [
		/usr/bin/xcaddy build
		--output /usr/local/bin/frankenphp
		--with github.com/dunglas/frankenphp=./
		--with github.com/dunglas/frankenphp/caddy=./caddy
		--with github.com/dunglas/caddy-cbrotli
		--with github.com/dunglas/mercure/caddy
        --with github.com/dunglas/vulcain/caddy
		# --with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=/build/cache
	]
	# let build_cmd =  [
	# 	ls -l /build /build/caddy /build/cache
	# ]
	let php_includes = (^buildah run $frankenphp_builder php-config --includes)
	let php_ldflags = (^buildah run $frankenphp_builder php-config --ldflags)
	let php_libs = (^buildah run $frankenphp_builder php-config --libs)
	let env_args = [
		# Both
		--env CGO_ENABLED=1
		--env XCADDY_SETCAP=1

		# frankenwp
		# https://github.com/StephenMiracle/frankenwp/blob/main/Dockerfile#L14
		# --env XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath'

		# FrankenPHP
		# https://frankenphp.dev/docs/docker/#how-to-install-more-caddy-modules
		--env `XCADDY_GO_BUILD_FLAGS=-ldflags='-w -s' -tags=nobadger,nomysql,nopgx`

		--env $"CGO_CFLAGS=($php_includes)"
		--env $"CGO_LDFLAGS=($php_ldflags) ($php_libs)"
	]

	# frankenwp and Docker PHP uses `install-php-extensions` to build the PHP extensions.
	# FrankenPHP uses `php-config` to build the PHP extensions.
	# See https://frankenphp.dev/docs/static/#extensions

	# buildah run $frankenphp_builder -- sh -c 'go version'
	# buildah run $frankenphp_builder -- sh -c $build_cmd
	print $"^buildah run --workingdir /build ...($env_args) ($frankenphp_builder) -- ...$build_cmd"
	^buildah run --workingdir /build ...$env_args $frankenphp_builder -- ...$build_cmd
	log info "xcaddy built"
}

def build-php-extensions [
	frankenphp_builder: string		# FrankenPHP builder image
]: nothing -> nothing {
	# List of system dependencies required for building PHP extensions.
	let packages = [
		curl
		tar
		ca-certificates
		libxml2-dev
		libjpeg-dev
		libpng-dev
		libwebp-dev
		libfreetype6-dev
		libzip-dev
		libicu-dev
		libmagickwand-dev
	]

	^buildah run $frankenphp_builder apt-get update
	^buildah run $frankenphp_builder apt-get install -y ...$packages

	# The PHP Docker image seems to use the docker-php-extension-installer script; they reference and link to it.
	# It's not clear if the "docker-php-ext-install" command is syntactic sugar over "install-php-extensions".
	#   docker-php-ext-install: https://hub.docker.com/_/php/#how-to-install-more-php-extensions
	#   install-php-extensions: https://github.com/mlocati/docker-php-extension-installer

	let php_extensions = [
		bcmath
		exif
		gd
		intl
		imagick/imagick@master
		mysqli
		pdo
		pdo_mysql
		opcache
		soap
		zip
	]
	# Install PHP extensions for WordPress
	^buildah run $frankenphp_builder install-php-extensions ...$php_extensions
}

# Build the image
def build-image [] {
	use std log
	let image_name = "frankenwp"

	# TODO: Look into PHP 8.4 
	let php_version = "8.4"
	let frankenphp_version = "1.9"
	let caddy_version = "2.10"
	let wp_version = "latest"
	# let wp_version = "6.8.2-php8.3-fpm"

	let frankenphp_builder = (^buildah from $"docker.io/dunglas/frankenphp:builder-php($php_version)")
	let frankenphp_runner = (^buildah from $"docker.io/dunglas/frankenphp:($frankenphp_version)-php($php_version)")
	let caddy_builder = (^buildah from docker.io/caddy:($caddy_version)-builder)
	let wp = (^buildah from $"docker.io/wordpress:($wp_version)")

	copy-caddy $caddy_builder $frankenphp_builder
	build-caddy $frankenphp_builder
	build-php-extensions $frankenphp_builder

	if false {
		# Increase PHP memory limit to avoid memory exhaustion with wp-cli
		buildah run $frankenphp_builder sh -c 'echo "memory_limit = 512M" > /usr/local/etc/php/conf.d/99-memory-limit.ini'

		# # Copy php.ini-production to php.ini
		# buildah run $frankenphp_builder cp $env.PHP_INI_DIR/php.ini-production $env.PHP_INI_DIR/php.ini

		# # Copy custom php.ini (assumes php.ini exists in your build context)
		# buildah copy $frankenphp_builder php.ini $env.PHP_INI_DIR/conf.d/wp.ini

		# Copy WordPress source from wp image
		buildah copy --from $wp $frankenphp_builder /usr/src/wordpress /usr/src/wordpress

		# Copy PHP conf.d from wp image
		buildah copy --from $wp $frankenphp_builder /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d/

		# Copy docker-entrypoint.sh from wp image
		buildah copy --from $wp $frankenphp_builder /usr/local/bin/docker-entrypoint.sh /usr/local/bin/
	}

	# # Permissions
	# buildah run $frankenphp_builder chown -R www-data:www-data /var/www/html

	# Download Caddyfile from frankenwp GitHub repository
	^buildah run $frankenphp_builder curl -o /etc/caddy/Caddyfile https://raw.githubusercontent.com/dunglas/frankenwp/main/Caddyfile

	# Copy mu-plugins to the wp-content volume
	# buildah copy $frankenphp_builder wp-content/mu-plugins /var/www/html/wp-content/mu-plugins

	# Expose FrankenPHP default port
	buildah config --port 8080 $frankenphp_builder

	# Entrypoint/command
	buildah config --cmd '["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]' $frankenphp_builder

	# Commit the image
	buildah commit $frankenphp_builder $"docker-daemon:($image_name):custom"

	echo $"✅ Image ($image_name) built successfully"

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

	# Build the image using buildah in a root namespace.
	build-image

}
