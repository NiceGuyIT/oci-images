#!/usr/bin/env nu

# Main script
def main [] {
	use std log

	let config = (if ("config.yml" | path exists) {open config.yml})

	let smartctl_version = $config.smartctl_exporter.version
	let image_name = $config.smartctl_noroot.name
	let image_tag = $config.smartctl_noroot.version

	log info $"Building ($image_name):($image_tag)"
	(^docker buildx build
		--build-arg $"SMARTCTL_VERSION=($smartctl_version)"
		--tag $"($image_name):($image_tag)"
		--load
		.)

	log info $"Built image '($image_name):($image_tag)'"

	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($image_name)\n" | save --append $output
	$"tags=($image_tag)\n" | save --append $output
}
