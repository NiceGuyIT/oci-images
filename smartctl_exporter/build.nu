#!/usr/bin/env nu
use std log

# Main script
def main [] {
	use std log

	# 'buildah mount' can not be run in userspace. This script needs to be run as 'buildah unshare build.nu'
	# This detects if we are in the host namespace and runs the script with 'unshare' if we are.
	# https://opensource.com/article/19/3/tips-tricks-rootless-buildah
	# https://unix.stackexchange.com/questions/619664/how-can-i-test-that-a-buildah-script-is-run-under-buildah-unshare
	let namespace = (
		open /proc/self/uid_map
		| parse --regex '\s*(?<start_uid_namespace>[^\s]+)\s*(?<start_uid_host>[^\s]+)\s*(?<length_uid>[^\s]+)'
	)
	if (($namespace.start_uid_namespace.0 | into int) == 0) and (($namespace.start_uid_host.0 | into int) == 0) {
		log info "Detected root namespace. Rerunning in a 'buildah unshare' environment."
		^buildah unshare ./build.nu
		exit 0
	}
	log info "Running in a 'buildah unshare' environment. Continuing..."

	let config = (if ("config.yml" | path exists) {open config.yml})

	# smartctl_exporter image
	let smartctl_image_url = $"($config.smartctl_exporter.url):($config.smartctl_exporter.version)"

	log info $"========================================\n"
	log info $"Pulling Nosey smartctl_exporter image"
	let smartctl_ctr = (^buildah from $smartctl_image_url)

	log info $"========================================\n"
	# Need to set the user to root to install the shadow package.
	log info "Installing the 'shadow' package"
	^buildah config --user root $smartctl_ctr
	^buildah run $smartctl_ctr -- sh -c "apk add shadow"
	^buildah config --user nobody $smartctl_ctr

	log info $"Exposing port 9633"
	^buildah config --port 9633 $smartctl_ctr

	log info $"Setting entrypoint to /bin/smartctl_exporter"
	^buildah config --entrypoint /bin/smartctl_exporter $smartctl_ctr

	# Publish the container as an image in buildah.
	let noroot_name = $config.smartctl_noroot.name
	let noroot_version = $config.smartctl_noroot.version

	let noroot_ctr = (^buildah commit $smartctl_ctr $noroot_name)
	log info $"Built image '($noroot_ctr)' version '($noroot_version)'"

	# Publish the image to Docker for use.
	^buildah push $noroot_ctr $"docker-daemon:($noroot_ctr):($noroot_version)"
	log info $"Published image '($noroot_name)' version '($noroot_version)' to Docker."


	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		# Output the information to the GitHub action.
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($noroot_name)\n" | save --append $output
	$"tags=($noroot_name)\n" | save --append $output

}