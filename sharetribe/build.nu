#!/usr/bin/env nu

# Main script
def main [] {
	use std log

	let config = (if ("config.yml" | path exists) {open config.yml})

	let published_name = $config.published.name
	let published_version = $config.published.version

	log info $"Building ($published_name):($published_version)"
	(^docker buildx build
		--build-arg $"SHARETRIBE_TAG=($config.sharetribe.tag)"
		--build-arg $"NODE_VERSION=($config.node.version)"
		--tag $"($published_name):($published_version)"
		--load
		.)

	log info $"Built image '($published_name):($published_version)'"

	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	$"tags=($published_version)\n" | save --append $output
}
