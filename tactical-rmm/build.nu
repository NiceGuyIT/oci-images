#!/usr/bin/env nu

# Build a single Tactical RMM component, or all of them when no argument is given.
#
# Usage:
#   ./build.nu                # build every component
#   ./build.nu backend        # build only the backend
#
# Valid component names are read from config.yml (components.<name>).

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
	let image_name = $comp.image_name
	let image_version = $trmm_version

	let context = ($env.FILE_PWD | path join $component)

	log info $"Building ($image_name):($image_version) from ($context)"
	(^docker buildx build
		--build-arg $"TRMM_VERSION=($trmm_version)"
		--build-arg $"BASE_IMAGE=($comp.base_image)"
		--build-arg $"BASE_TAG=($comp.base_tag)"
		--tag $"($image_name):($image_version)"
		--load
		$context)

	log info $"Built image '($image_name):($image_version)'"

	# Output for CI. Each component is built in its own job, so each run writes
	# a single image=/tags= pair to GITHUB_OUTPUT.
	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($image_name)\n" | save --append $output
	$"tags=($image_version)\n" | save --append $output
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
