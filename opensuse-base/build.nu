#!/usr/bin/env nu

# Using openSUSE Leap as the base, build.nu creates two images: base and dev. The base image is

# Load the configuration
def load-config []: [nothing -> any, string -> any] {
	try {
		mut config = ($in | default "config.yml" | open)
		# Full version tag: v0.7.2-leap-16.0
		$config.published.base.version = ([
			$config.published.version   # v0.7.2
			$config.opensuse.name       # leap
			$config.opensuse.version    # 16.0
		] | str join '-')
		$config.published.dev.version = ([
			$config.published.version
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
		# Semver tags for version compatibility
		let version_parts = ($config.published.version | split row '.')
		let major_version = ($version_parts | first 1 | str join)
		let minor_version = ($version_parts | first 2 | str join '.')
		# Major version tag: v0-leap-16.0
		$config.published.base.major_version = ([
			$major_version
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
		$config.published.dev.major_version = ([
			$major_version
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
		# Minor version tag: v0.7-leap-16.0
		$config.published.base.minor_version = ([
			$minor_version
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
		$config.published.dev.minor_version = ([
			$minor_version
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
		# Latest tags: "latest" and "latest-leap-16.0"
		$config.published.base.latest = 'latest'
		$config.published.dev.latest = 'latest'
		$config.published.base.latest_os = ([
			'latest'
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
		$config.published.dev.latest_os = ([
			'latest'
			$config.opensuse.name
			$config.opensuse.version
		] | str join '-')
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
def install-packages [
	name					# Image name
]: any -> any {
	use std log
	let config = $in

	# Refresh the repos, update the system, and install packages.
	# Note: The semicolon separates the commands because they are joined with a space.
	# Quotes are needed to prevent Nushell from interpreting the semicolon as the end of the list.
	let cmd = ([
		zypper --non-interactive --gpg-auto-import-keys refresh ';'
		zypper --non-interactive update ';'
		zypper --non-interactive install ($config.packages | get $name | str join ' ') ';'
		zypper --non-interactive clean --all ';'
	] | str join ' ')

	log info $"========================================\n"
	log info $"[install-packages] cmd: ($cmd)"
	^buildah run $config.buildah.container -- /bin/sh -c $'($cmd)'
	$config
}


# Install single-file binaries
def install-binaries []: any -> any {
	let config = $in
	use std log

	# Save the binaries to a mounted directory rather than scripting something inside the container.
	let mountpoint = (^buildah mount $config.buildah.container)
	const bin_path = '/usr/local/bin'

	log info $"========================================\n"
	log info $"[install-binaries] mountpoint: ($mountpoint)"
	$config.binaries.list
	| par-each --threads 4 {|it|
		let filename = ($it.file? | default $it.name)
		let url = (
			{
				"scheme": "https"
				"host": $config.binaries.host
				"path": (
					[
						'public'
						$nu.os-info.name
						$nu.os-info.arch
						$it.name
						$it.version
						$filename
					] | path join
				)
			} | url join
		)
		log info $"[install-binaries] Installing binary: '($filename)'"
		http get $url | save ($"($mountpoint)($bin_path)/($filename)")
		chmod a+rx $"($mountpoint)($bin_path)/($filename)"
	}
	^buildah umount $config.buildah.container
	$config
}


# Add the user to the container
def add-user []: any -> any {
	let config = $in
	use std log

	# Add the "dev" user and configure their environment
	const container_user = 'dev'
	let sudoer_text = $"'# User rules for ($container_user)\\n($container_user) ALL=\(ALL) NOPASSWD:ALL\\n'"
	let chezmoi_text = (
		{
			"sourceDir": $"/home/($container_user)/projects/dotfiles",
			"data": {
				"git": {
					"email": "me@example.com",
					"name": "my name"
				}
			}
		} | to json --raw
	)

	# Using nu as a shell prevents JetBrains and VSCode from connecting to the container (using SSH).
	const login_shell = '/usr/bin/bash'
	let cmd = ([
		echo "/usr/local/bin/nu" >/etc/shells ';'
		useradd --groups 'users,docker' --shell $login_shell --create-home $container_user ';'
		echo -e $sudoer_text > $"/etc/sudoers.d/50-($container_user)-user" ';'
		mkdir -p ~($container_user)/projects ~($container_user)/.config/chezmoi ~($container_user)/.bun ';'
		git clone --depth 1 $config.dotfiles.repo ~($container_user)/projects/dotfiles ';'
		echo $"'($chezmoi_text)'" > ~($container_user)/.config/chezmoi/chezmoi.jsonc ';'
		chown -R dev:users ~($container_user) ';'
		# TODO: Set the umask before running chezmoi
		#su --login --command "'sh -c \'umask\''" $container_user ';'
		su --login --command "'/usr/local/bin/chezmoi apply --no-tty --no-pager'" $container_user ';'
	] | str join ' ')

	log info $"========================================\n"
	log info $"[build-image] Creating ($container_user) user. cmd: ($cmd)"
	^buildah run $config.buildah.container -- /bin/sh -c $'($cmd)'
	^buildah config --user $container_user $config.buildah.container
	$config
}


# Install user scripts
def install-user-scripts [
	name					# Image name
]: any -> any {
	let config = $in
	use std log

	# Add the "dev" user and configure their environment
	const container_user = 'dev'
	const container_shell = '/usr/local/bin/nu'
	const rustup = '/tmp/rustup.sh'
	const rustup_url = 'https://sh.rustup.rs'

	# TODO: Verify this works.
	let bun = (
		$config.bun
		| get $name
		| each {|it|
			$"^bun install --global ($it)"
		}
		| to text
	)

	# TODO: uv tool install
    let uv = (
        $config.uv
        | get $name
        | each {|it|
            $"^uv tool install ($it)"
        }
        | to text
    )

	let rust_version = ($config.rust?.version? | default "stable")

	# Execute the scripts as the user.
	# Note: Escapes are allowed in double quotes but not single quotes or backticks.
	let cmd = $"
		# nvm and node
		nvm-install.nu

		# Install global NPM packages using bun
		($bun)
		# List all packages installed to verify
		^bun pm ls --global

		# Install global Python packages using uv
		($uv)
		^uv tool list

		# Rustup
		http get ($rustup_url) | save ($rustup)
		if \('($rustup)' | path exists\) {
			print 'Downloaded rustup. Installing rustup...'
			chmod a+x ($rustup)
			^($rustup) -y --no-modify-path --default-toolchain ($rust_version)
			rm ($rustup)
		} else {
			print 'Failed to download rustup'
		}
	"

	# These debugging statements can be added inside the cmd.
	# print '========== Chezmoi status =========='
	# print \(^chezmoi status --force --no-tty --no-pager\)
	# print $'========== ls -la \($env.HOME\) =========='
	# print \(ls -la $env.HOME\)
	# print '========== /proc/self/mountinfo =========='
	# print \(open --raw /proc/self/mountinfo\)
	# print '========== ls -la / =========='
	# print \(ls -la /\)
	# print '========== $env / =========='
	# print \($env\)

	log info $"========================================\n"
	log info $"[install-user-scripts] Installing Rustup ($rust_version) for `($container_user)`"
	log info $"[install-user-scripts] cmd: ($cmd)"
	print ""
	^buildah run --user $container_user $config.buildah.container -- $container_shell --login --commands $cmd
	$config
}


# Publish the image to buildah's local storage for the GitHub Action to push.
def publish-image [
	name					# Image name
]: any -> any {
	use std log
	let config = $in

	# Commit the container as an image in buildah's local storage.
	let published_name = ($config.published | get $name | get name)
	let published_version = ($config.published | get $name | get version)
	let published_major_version = ($config.published | get $name | get major_version)
	let published_minor_version = ($config.published | get $name | get minor_version)
	let published_latest = ($config.published | get $name | get latest)
	let published_latest_os = ($config.published | get $name | get latest_os)
	let image_name = ([
		($config.published | get $name | get name)
		($config.published | get $name | get version)
	]| str join ':')
	let image_name_major = ([$published_name $published_major_version] | str join ':')
	let image_name_minor = ([$published_name $published_minor_version] | str join ':')
	let image_name_latest = ([$published_name $published_latest] | str join ':')
	let image_name_latest_os = ([$published_name $published_latest_os] | str join ':')

	let image = (^buildah commit --format docker $config.buildah.container $image_name)
	log info $"[publish-image] Built image '($image_name)'"

	# Tag with major and minor versions for semver compatibility
	^buildah tag $image $image_name_major
	log info $"[publish-image] Tagged image '($image_name_major)'"
	^buildah tag $image $image_name_minor
	log info $"[publish-image] Tagged image '($image_name_minor)'"
	# Tag with latest labels for convenience
	^buildah tag $image $image_name_latest
	log info $"[publish-image] Tagged image '($image_name_latest)'"
	^buildah tag $image $image_name_latest_os
	log info $"[publish-image] Tagged image '($image_name_latest_os)'"

	# Output to a log file...
	mut output = $config.output.log
	if ("GITHUB_OUTPUT" in $env) {
		# ...unless we are in a GitHub action.
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	$"tags=($published_version) ($published_minor_version) ($published_major_version) ($published_latest) ($published_latest_os)\n" | save --append $output

	$config
}

# Build the image
def build-image [
	name					# Image name
]: any -> any {
	use std log
	mut config = $in

	# opensuse image
	$config.image.url = $"($config.opensuse.url):($config.opensuse.version)"

	log info $"[build-image] ========================================\n"
	log info $"[build-image] Pulling opensuse image from '($config.image.url)'"
	$config.buildah.container = (^buildah from $config.image.url)

	# Install the packages
	$config
	| install-packages $name
	| install-binaries
	| add-user
	| install-user-scripts $name
}

# Main script
def main [
	name					# Image name
] {
	if not ($name in [base dev]) {
		use std log
		log error $"Invalid image name: ($name). Valid names are: 'base', 'dev'"
	}

	# Check if the environment is suitable for Buildah. This execs the calling script in the user namespace
	# using "buildah unshare build.nu"
	# Use environment variable to pass the args
	$env.BUILD_ARGS = $name
	use ../buildah-wrapper.nu *
	check-environment

	# Order matters! The container ID set in build-image and used throughout the other functions.
	load-config
	| build-image $name
	| publish-image $name
}