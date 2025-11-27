#!/usr/bin/env nu

# Main script
def main [
	name					# Image name
] {
	use std log

	# Check if the environment is suitable for Buildah. This execs the calling script in the user namespace
	# using "buildah unshare build.nu"
	# Use environment variable to pass the args
	$env.BUILD_ARGS = $name
	use ../buildah-wrapper.nu *
	check-environment

	let config = (if ("config.yml" | path exists) {open config.yml})

	# smartctl_exporter image
	let smartctl_image_url = $"($config.smartctl_exporter.url):($config.smartctl_exporter.version)"

	log info $"========================================\n"
	log info $"Pulling smartctl_exporter image"
	let smartctl_ctr = (^buildah from --isolation chroot $smartctl_image_url)

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

	let noroot_ctr = (^buildah commit --format docker $smartctl_ctr ([$noroot_name, $noroot_version] | str join ':'))
	log info $"Built image '($noroot_name)' version '($noroot_version)'"

	# Publish the image to Docker for use.
	^buildah push $noroot_ctr (["docker-daemon", $noroot_name, $noroot_version] | str join ':')
	log info $"Published image '($noroot_name)' version '($noroot_version)' to Docker."


	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		# Output the information to the GitHub action.
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($noroot_name)\n" | save --append $output
	$"tags=($noroot_version)\n" | save --append $output

}