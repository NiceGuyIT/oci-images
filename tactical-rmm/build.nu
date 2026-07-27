#!/usr/bin/env nu

# Build a single Tactical RMM component, or all of them when no argument is given.
#
# Usage:
#   ./build.nu                # build every component
#   ./build.nu backend        # build only the backend
#
# Valid component names are read from config.yml (components.<name>).
#
# Tags encode our version first and the upstream release as a suffix, matching
# the rust-builder-* images: v1.0.0-trmm1.5.1. Publishing under the upstream
# version alone made two different builds of our packaging indistinguishable.

# Full tag set for a build: exact version, the moving minor and major aliases,
# and latest both with and without the upstream suffix. Same shape as
# rust-builder-glibc/build.nu.
def image-tags [
	published_version: string	# Our version, e.g. v1.0.0
	trmm_version: string		# Upstream release, e.g. 1.5.1
]: [nothing -> list<string>] {
	let suffix = $"trmm($trmm_version)"
	let parts = ($published_version | split row '.')

	# uniq because a version shorter than major.minor.patch collapses the aliases
	# onto each other, and a repeated tag would be pushed twice.
	[
		$"($published_version)-($suffix)"
		$"($parts | first 2 | str join '.')-($suffix)"
		$"($parts | first 1 | str join)-($suffix)"
		$"latest-($suffix)"
		'latest'
	] | uniq
}

def build-component [
	component: string			# Component key in config.yml (backend, frontend, ...)
	config: record				# Parsed config.yml record
] {
	use std log

	if not ($component in ($config.components | columns)) {
		let valid = ($config.components | columns | str join ', ')
		log error $"Invalid component: ($component). Valid components are: ($valid)"
		exit 1
	}

	let comp = ($config.components | get $component)
	let trmm_version = $config.tacticalrmm.version
	let published_version = $config.published.version
	let image_name = $comp.image_name
	let tags = (image-tags $published_version $trmm_version)
	let tag_args = ($tags | each {|t| ['--tag' $"($image_name):($t)"]} | flatten)

	let context = ($env.FILE_PWD | path join $component)

	log info $"Building ($image_name) from ($context) with tags: ($tags | str join ', ')"
	(^docker buildx build
		--build-arg $"TRMM_VERSION=($trmm_version)"
		--build-arg $"IMAGE_VERSION=($published_version)"
		--build-arg $"BASE_IMAGE=($comp.base_image)"
		--build-arg $"BASE_TAG=($comp.base_tag)"
		...$tag_args
		--load
		$context)

	log info $"Built image '($image_name)' as ($tags | str join ', ')"

	# Output for CI. Each component is built in its own job, so each run writes
	# a single image=/tags= pair to GITHUB_OUTPUT. The push step splits tags on
	# spaces and pushes each one.
	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($image_name)\n" | save --append $output
	$"tags=($tags | str join ' ')\n" | save --append $output
}

def main [
	component?: string			# Component name (backend, frontend, meshcentral, nats, nginx). Omit to build all.
] {
	use std log

	let config_path = ($env.FILE_PWD | path join "config.yml")
	let config = (open $config_path)

	if ($component | is-empty) {
		log info "No component specified, building all components"
		for name in ($config.components | columns) {
			build-component $name $config
		}
	} else {
		build-component $component $config
	}
}
