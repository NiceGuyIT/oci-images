#!/usr/bin/env nu

# Main script
def main [
	name					# Image name
] {
	use std log

	let config = (if ("config.yml" | path exists) {open config.yml})

	# Compute the WordPress Docker tag: e.g. 6.8.1-php8.4-fpm-alpine
	let wordpress_docker_tag = (
		[
			$config.wordpress.version
			$"php($config.php.version)"
			"fpm"
			"alpine"
		] | str join '-'
	)

	# Build debug/dev image or production?
	# "prod" == production, anything else == debug
	let environment = ($env.ENVIRONMENT? | default "debug")
	let install_xdebug = ($environment != "prod")

	# The image version does not include the WordPress version because the WordPress version is determined
	# by the data, not the image.
	let image_version = (
		[
			$"php($config.php.version)"
			$"redis($config.redis.version)"
			(if $install_xdebug {$"xdebug($config.xdebug.version)"})
		]
		| str join '-'
		| str trim --char '-'
	)

	let published_name = $config.published.name

	log info $"Building ($published_name):($image_version)"
	(^docker buildx build
		--build-arg $"WORDPRESS_TAG=($wordpress_docker_tag)"
		--build-arg $"REDIS_VERSION=($config.redis.version)"
		--build-arg $"XDEBUG_VERSION=($config.xdebug.version)"
		--build-arg $"INSTALL_XDEBUG=($install_xdebug)"
		--tag $"($published_name):($image_version)"
		--load
		.)

	log info $"Built image '($published_name):($image_version)'"

	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	$"tags=($image_version)\n" | save --append $output
}
