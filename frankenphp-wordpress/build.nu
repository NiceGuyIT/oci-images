#!/usr/bin/env nu

# Main script
def main [] {
	use std log

	let config = (if ("config.yml" | path exists) {open config.yml})

	let php_version = $config.php.version
	let php_extensions = ($config.php.extensions | str replace --all "\n" "" | str trim)
	let caddy_modules = ($config.caddy_modules | str replace --all "\n" "" | str trim)
	let published_name = $config.published.name
	let published_version = $config.published.version

	# Build args common to all builds
	mut args = [
		--build-arg $"PHP_VERSION=($php_version)"
		--build-arg $"PHP_EXTENSIONS=($php_extensions)"
		--build-arg $"XCADDY_ARGS=($caddy_modules)"
		--tag $"($published_name):($published_version)"
		--load
	]

	# Pass GitHub token as Docker secret for pre-built downloads (avoids API rate limits)
	let github_token = ($env | get -i GITHUB_TOKEN | default ($env | get -i GH_TOKEN | default ""))
	if $github_token != "" {
		let token_file = "/tmp/github-token"
		$github_token | save $token_file
		$args = ($args | prepend [--secret $"id=github-token,src=($token_file)"])
	}

	log info $"Building ($published_name):($published_version)"
	(^docker buildx build ...$args .)

	log info $"Built image '($published_name):($published_version)'"

	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	$"tags=($published_version)\n" | save --append $output
}
