#!/usr/bin/env nu

# Are we running in the root namespace?
def isRootNamespace []: nothing -> bool {
	let namespace = (
		open /proc/self/uid_map
		| parse --regex '\s*(?<start_uid_namespace>[^\s]+)\s*(?<start_uid_host>[^\s]+)\s*(?<length_uid>[^\s]+)'
		| into int start_uid_namespace start_uid_host length_uid
	)
	mut root_namespace = false
	if ($namespace.start_uid_namespace.0 == 0) and ($namespace.start_uid_host.0 == 0) {
		$root_namespace = true
	}
	use std log
	log info $"namespace: ($namespace)"
	log info $"Root namespace: ($root_namespace)"
	return $root_namespace
}

# Are we running in a container?
# https://forums.docker.com/t/detect-you-are-running-in-a-docker-container-buildx/139673/4
def isContainer []: nothing -> bool {
	let cgroup = (open /proc/1/cgroup | str trim)
	mut container = false
	if ($cgroup == '0::/') {
		$container = true
	}
	use std log
	log info $"cgroup: '($cgroup)'"
	log info $"Container: ($container)"
	return $container
}

# Get the permissions from the seccomp.json.
def get_seccomp [
	--name: string		# Name of permission to get
]: nothing -> string {
	let seccomp = "/usr/share/containers/seccomp.json"
	if not ($seccomp | path exists) {
		use std log
		log error $"File does not exist: '($seccomp)'"
		return ""
	}
	return (open $seccomp | get syscalls | where {$name in $in.names} | get action.0)
}

def check_sysctl []: nothing -> nothing {
	use std log
	let unprivileged_userns_clone = "/proc/sys/kernel/unprivileged_userns_clone"
	if ($unprivileged_userns_clone | path exists) {
		log info $"unprivileged_userns_clone: (open $unprivileged_userns_clone | str trim)"
	} else {
		log info $"unprivileged_userns_clone: Permission does not exist"
	}
}

# Main script
def main [] {
	use std log

	# 'buildah mount' can not be run in userspace. This script needs to be run as 'buildah unshare build.nu'
	# This detects if we are in the host namespace and runs the script with 'unshare' if we are.
	# https://opensource.com/article/19/3/tips-tricks-rootless-buildah
	# https://unix.stackexchange.com/questions/619664/how-can-i-test-that-a-buildah-script-is-run-under-buildah-unshare
	let is_container = (isContainer)
	let is_root_namespace = (isRootNamespace)
	let unshare_permission = (get_seccomp --name "unshare")
	let clone_permission = (get_seccomp --name "clone")
	log info $"is_container: ($is_container)"
	log info $"is_root_namespace: ($is_root_namespace)"
	log info $"unshare_permission: ($unshare_permission)"
	log info $"clone_permission: ($clone_permission)"

	check_sysctl

	# log info "Running 'unshare --user id'"
	# try {
	#	^unshare --user id
	# } catch {|err|
	#	log warning $"Failed to run unshare --user: '($err.msg)'"
	# }

	# log info "Running 'unshare --mount id'"
	# try {
	#	^unshare --mount id
	# } catch {|err|
	#	log warning $"Failed to run unshare --mount: '($err.msg)'"
	# }

	if ($is_container) {
		log info "Detected container. Using chroot isolation."
		$env.BUILDAH_ISOLATION = "chroot"
	} else if ($is_root_namespace) {
		# unshare cannot be run in certain environments.
		# https://github.com/containers/buildah/issues/1901
		# Dockers/containerd blocks unshare and mount. Podman, Buildah, CRI-O do not.
		log info "Detected root namespace and not in container. Rerunning in a 'buildah unshare' environment."
		# ^buildah unshare ./build.nu
		# exit 0
	}

	let config = (if ("config.yml" | path exists) {open config.yml})

	# opensuse_leap image
	let opensuse_image_url = $"($config.opensuse_leap.url):($config.opensuse_leap.version)"

	log info $"========================================\n"
	log info $"Pulling opensuse_leap image"
	print $"^buildah from --isolation chroot ($opensuse_image_url)"
	let opensuse_ctr = (^buildah from --isolation chroot $opensuse_image_url)

	log info $"========================================\n"
	# Need to set the user to root to install the shadow package.
	log info "Installing base packages"
	^buildah run $opensuse_ctr -- sh -c "zypper install curl git tar gzip bzip2 zstd java-21-openjdk-devel buildah docker"

	# Publish the container as an image in buildah.
	let published_name = $config.published.name
	let published_version = $config.published.version

	let image = (^buildah commit --format docker $opensuse_ctr ([$published_name, $published_version] | str join ':'))
	log info $"Built image '($published_name)' version '($published_version)'"

	# Publish the image to Docker for use.
	^buildah push $image (["docker-daemon", $published_name, $published_version] | str join ':')
	log info $"Published image '($published_name)' version '($published_version)' to Docker."

	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		# Output the information to the GitHub action.
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	$"tags=($published_version)\n" | save --append $output

}