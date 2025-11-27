#!/usr/bin/env nu

# Are we running in the root namespace?
def is-root-namespace []: nothing -> bool {
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
def is-container []: nothing -> bool {
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
def get-seccomp [
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

# Check the unprivileged_userns_clone permission in sysctl
def check-sysctl []: nothing -> nothing {
	use std log
	let unprivileged_userns_clone = "/proc/sys/kernel/unprivileged_userns_clone"
	if ($unprivileged_userns_clone | path exists) {
		log info $"unprivileged_userns_clone: (open $unprivileged_userns_clone | str trim)"
	} else {
		log info $"unprivileged_userns_clone: Permission does not exist"
	}
}

# Check if the environment is suitable for buildah.
export def check-environment []: nothing -> nothing {
	use std log

	# 'buildah mount' can not be run in userspace. This script needs to be run as 'buildah unshare build.nu'
	# This detects if we are in the host namespace and runs the script with 'unshare' if we are.
	# https://opensource.com/article/19/3/tips-tricks-rootless-buildah
	# https://unix.stackexchange.com/questions/619664/how-can-i-test-that-a-buildah-script-is-run-under-buildah-unshare
	let is_container = (is-container)
	let is_root_namespace = (is-root-namespace)
	let unshare_permission = (get-seccomp --name "unshare")
	let clone_permission = (get-seccomp --name "clone")
	log info $"is_container: ($is_container)"
	log info $"is_root_namespace: ($is_root_namespace)"
	log info $"unshare_permission: ($unshare_permission)"
	log info $"clone_permission: ($clone_permission)"

	check-sysctl

	log info "Running 'unshare --user id'"
	try {
		^unshare --user id
	} catch {|err|
		log warning $"Failed to run unshare --user: '($err.msg)'"
	}

	log info "Running 'unshare --mount id'"
	try {
		^unshare --mount id
	} catch {|err|
		log warning $"Failed to run unshare --mount: '($err.msg)'"
	}

	if ($is_container) {
		log info "Detected container. Using chroot isolation."
		$env.BUILDAH_ISOLATION = "chroot"
	} else if ($is_root_namespace) {
		if not ('BUILD_ARGS' in $env) {
			log error $"Build arguments ('BUILD_ARGS') not set."
			exit 1
		}
		# unshare cannot be run in certain environments.
		# https://github.com/containers/buildah/issues/1901
		# Dockers/containerd blocks unshare and mount. Podman, Buildah, CRI-O do not.
		log info "Detected root namespace and not in container. Rerunning in a 'buildah unshare' environment."
		^buildah unshare ./build.nu $env.BUILD_ARGS
		exit 0
	}
}