#!/usr/bin/env nu

# Build a single Tactical RMM component, or all of them when no argument is given.
#
# Usage:
#   ./build.nu                # build every component
#   ./build.nu backend        # build only the backend
#
# Valid component names are read from config.yml (components.<name>).
#
# Tags name the upstream release first and our packaging revision second, the way
# distribution packages are versioned: trmm1.5.1-2 is our second packaging of
# upstream 1.5.1. Publishing under the upstream version alone made two different
# builds of our packaging indistinguishable.

# Full tag set for a build: the exact tag, the upstream release on its own as the
# moving newest-packaging tag, and latest.
def image-tags [
	published_revision: string	# Our packaging revision, e.g. 2
	trmm_version: string		# Upstream release, e.g. 1.5.1
]: [nothing -> list<string>] {
	let upstream = $"trmm($trmm_version)"

	[
		$"($upstream)-($published_revision)"
		$upstream
		'latest'
	]
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
	let published_revision = ($config.published.revision | into string)
	let image_name = $comp.image_name
	let tags = (image-tags $published_revision $trmm_version)
	let tag_args = ($tags | each {|t| ['--tag' $"($image_name):($t)"]} | flatten)

	let context = ($env.FILE_PWD | path join $component)

	log info $"Building ($image_name) from ($context) with tags: ($tags | str join ', ')"
	(^docker buildx build
		--build-arg $"TRMM_VERSION=($trmm_version)"
		--build-arg $"IMAGE_REVISION=($published_revision)"
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
