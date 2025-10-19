#!/usr/bin/env nu


def build-image [] {
	use std log
	let image_name = "frankenwp"

	# TODO: Look into PHP 8.4 
	let php_version = "8.4"
	let wp_version = "latest"
	# let wp_version = "6.8.2-php8.3-fpm"


	let frankenphp_builder = (^buildah from $"docker.io/dunglas/frankenphp:builder-php($php_version)")
	let caddy_builder = (^buildah from docker.io/caddy:builder)
	let wp = (^buildah from $"docker.io/wordpress:($wp_version)")

	let caddy_mnt = (^buildah mount $caddy_builder)
	let frankenphp_mnt = (^buildah mount $frankenphp_builder)

	mkdir $"($frankenphp_mnt)/build"
	mkdir $"($frankenphp_mnt)/build/caddy"

	# Set working dir
	buildah config --workingdir /build $frankenphp_builder

	# TODO: fix this
	# Copy xcaddy

	# mkdir /tmp/caddy_builder /tmp/frankenphp_builder

    # print (ls $"($caddy_mnt)/usr/bin")
    # print (ls $frankenphp_mnt)
	print $"caddy_mnt: ($caddy_mnt)"
	print $"frankenphp_mnt: ($frankenphp_mnt)"

	# "path join" does not handle joining mounted directories. Join the directories as a string.
    print ([$caddy_mnt, "/usr/bin/"] | path join)
    print $"($caddy_mnt)/usr/bin/"
    # print (ls $"($caddy_mnt)/usr/bin/")
    #  print (glob $"([$caddy_builder, "/usr/bin/"] | path join)/x*")

	cp $"($caddy_mnt)/usr/bin/xcaddy" $"($frankenphp_mnt)/usr/bin/"

    # print (ls -l $"($frankenphp_mnt)/usr/bin/xcaddy")

	# Copy cache middleware into the build directory
	cp -r ./sidekick/middleware/cache $"($frankenphp_mnt)/build/"

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
		# --with github.com/dunglas/frankenphp=/build/
		--with github.com/dunglas/frankenphp/caddy
		--with github.com/dunglas/caddy-cbrotli
		--with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=/build/cache
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
	# FrankenPHP uses `php-config` to build the PHP extensions. See https://frankenphp.dev/docs/static/#extensions

	# buildah run $frankenphp_builder -- sh -c 'go version'
	# buildah run $frankenphp_builder -- sh -c $build_cmd
	print $"^buildah run --workingdir /build ...($env_args) ($frankenphp_builder) -- ...$build_cmd"
	^buildah run --workingdir /build ...$env_args $frankenphp_builder -- ...$build_cmd
	log info "xcaddy built"


	# # CGO must be enabled to build FrankenPHP
	# buildah config --env CGO_ENABLED=1 $frankenphp_builder
	# buildah config --env XCADDY_SETCAP=1 $frankenphp_builder
	# buildah config --env XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath' $frankenphp_builder

	# Install deps
	buildah run $frankenphp_builder apt-get update
	buildah run $frankenphp_builder apt-get install -y curl tar ca-certificates libxml2-dev

		# Install system dependencies required for PHP extensions
	buildah run $frankenphp_builder apt-get update
	buildah run $frankenphp_builder apt-get install -y libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev libzip-dev libicu-dev libmagickwand-dev

	# Install required PHP extensions for WordPress
	buildah run $frankenphp_builder install-php-extensions bcmath exif gd intl mysqli zip imagick/imagick@master opcache

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


	# Add $_SERVER['ssl'] = true; when env USE_SSL = true is set to the wp-config.php file here: /usr/local/bin/wp-config-docker.php
	# buildah run $frankenphp_builder sed -i 's/<?php/<?php if (!!getenv("FORCE_HTTPS")) { $_SERVER["HTTPS"] = "on"; } define( "FS_METHOD", "direct" ); set_time_limit(300); /g' /usr/src/wordpress/wp-config-docker.php

	# # Adding WordPress CLI
	# buildah run $frankenphp_builder curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
	# buildah run $frankenphp_builder chmod +x wp-cli.phar
	# buildah run $frankenphp_builder mv wp-cli.phar /usr/local/bin/wp

	# # Initialize WordPress in /var/www/html
	# buildah run $frankenphp_builder wp core download --path=/var/www/html --allow-root
	# # Create wp-config.php using wp-cli
	# buildah run $frankenphp_builder wp config create --path=/var/www/html --dbname=wordpress --dbuser=wordpress --dbpass=wordpress --dbhost=localhost --skip-check --allow-root

	# # Install MySQL server and mysqld_safe
	# buildah run $frankenphp_builder apt-get update
	# buildah run $frankenphp_builder apt-get install -y mariadb-server mariadb-client mariadb-common

	# # Initialize MySQL data directory
	# buildah run $frankenphp_builder bash -c 'mysqld --user=mysql --datadir=/var/lib/mysql'

	# # Start MySQL server in the background for setup
	# buildah run $frankenphp_builder bash -c 'mysqld_safe --datadir=/var/lib/mysql & sleep 10 && mysql -u root -e "CREATE DATABASE IF NOT EXISTS wordpress; CREATE USER IF NOT EXISTS '\''wordpress'\''@'\''localhost'\'' IDENTIFIED BY '\''wordpress'\''; GRANT ALL PRIVILEGES ON wordpress.* TO '\''wordpress'\''@'\''localhost'\''; FLUSH PRIVILEGES;"'

	# # Install WordPress using WP-CLI
	# buildah run $frankenphp_builder wp core install --path=/var/www/html --url="http://localhost" --title="FrankenWP" --admin_user="admin" --admin_password="password" --admin_email="admin@example.com" --skip-email --allow-root

	# # Permissions
	# buildah run $frankenphp_builder chown -R www-data:www-data /var/www/html

	# Download Caddyfile from frankenwp GitHub repository
	buildah run $frankenphp_builder curl -o /etc/caddy/Caddyfile https://raw.githubusercontent.com/dunglas/frankenwp/main/Caddyfile

	# Copy mu-plugins to the wp-content volume
	# buildah copy $frankenphp_builder wp-content/mu-plugins /var/www/html/wp-content/mu-plugins

	# Add mysql
	buildah run $frankenphp_builder docker-php-ext-install pdo pdo_mysql soap



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

	# Check if the environment is suitable for Buildah. This execs the calling script in the user namespace
	# using "buildah unshare buildnu"
	use ../buildah-wrapper.nu *
	check-environment

	# Build the image using buildah in a root namespace.
	build-image
}
