#!/usr/bin/env nu

# Load the configuration
def load-config []: [nothing -> any, string -> any] {
	try {
		mut config = ($in | default "config.yml" | open)
		$config.published.version = $"v($config.opensuse_leap.version)-(date now | format date '%Y%m%d')"
		# TODO: Make this configurable.
		$config.output.log = 'output.log'
		$config
	} catch {|err|
		use std log
		log error $"[load-config] Failed to load config: ($err.msg)"
		exit 1
	}
}

# Install system packages
def install-packages []: any -> any {
	use std log
	let config = $in

	# Refresh the repos, update the system, and install packages.
	# Note 1: The semicolon separates the commands because they are joined with a space.
	# Note 2: Quotes are needed to prevent Nushell from interpreting the semicolon as the end of the list.
	let cmd = ([
		zypper --non-interactive --gpg-auto-import-keys 'refresh;'
		zypper --non-interactive 'update;'
		zypper --non-interactive install ($config.packages | str join ' ');
		zypper --non-interactive clean '--all;'
	] | str join ' ')

	log info $"========================================\n"
	log info $"[build-image] cmd: ($cmd)"
	^buildah run $config.buildah.container -- sh -c $'($cmd)'
	$config
}

def publish-image []: any -> any {
	use std log
	let config = $in

	# Publish the container as an image in buildah.
	let published_name = $config.published.name
	let published_version = $config.published.version
	let image_name = ([$config.published.name, $config.published.version] | str join ':')
	let docker_image_name = (['docker-daemon', $image_name] | str join ':')

	let image = (^buildah commit --format docker $config.buildah.container $image_name)
	log info $"[publish-image] Built image '($image_name)'"

	# Publish the image to Docker for use.
	^buildah push $image $docker_image_name
	log info $"[publish-image] Published image '($docker_image_name)' to Docker"

	# Output to a log file...
	mut output = $config.output.log
	if ("GITHUB_OUTPUT" in $env) {
		# ...unless we are in a GitHub action.
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	$"tags=($published_version)\n" | save --append $output

	$config
}

# Build the image
def build-image []: any -> any {
	use std log
	mut config = $in

	# opensuse_leap image
	$config.image.url = $"($config.opensuse_leap.url):($config.opensuse_leap.version)"

	log info $"[build-image] ========================================\n"
	log info $"[build-image] Pulling opensuse_leap image from '($config.image.url)'"
	$config.buildah.container = (^buildah from $config.image.url)

	# Install the packages
	$config | install-packages
}

# Main script
def main [] {
	use std log

	# Check if the environment is suitable for Buildah. This execs the calling script in the user namespace
	# using "buildah unshare buildnu"
	use ../buildah-wrapper.nu *
	check-environment

	load-config
	| build-image
	| publish-image
}