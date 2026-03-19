#!/usr/bin/env nu

# Main script
def main [] {
	use std log

	let config = (if ("config.yml" | path exists) {open config.yml})

	let coredns_version = $config.coredns.version
	let alias_module = $config.alias_plugin.module
	let published_name = $config.published.name
	let published_version = $config.published.version

	log info $"Building ($published_name):($published_version)"
	(^docker buildx build
		--build-arg $"COREDNS_VERSION=($coredns_version)"
		--build-arg $"ALIAS_PLUGIN_MODULE=($alias_module)"
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
