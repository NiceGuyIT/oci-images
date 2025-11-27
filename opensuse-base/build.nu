#!/usr/bin/env nu

# Using openSUSE Leap as the base, build.nu creates two images: base and dev. The base image is

# Load the configuration
def load-config []: [nothing -> any, string -> any] {
	try {
		mut config = ($in | default "config.yml" | open)
		$config.published.base.version = ([
			$config.published.version   # v0.5.0
			$config.opensuse.name       # leap
			$config.opensuse.version    # 16.0
		] | str join '-')
		$config.published.dev.version = ([
			$config.published.version
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

	let bun = (
		$config.bun
		| get $name
		| each {|it|
			$"^bun install --global ($it)"
		}
		| to text
	)

	# Execute the scripts as the user.
	# Note: Escapes are allowed in double quotes but not single quotes or backticks.
	let cmd = $"
		# nvm and node
		nvm-install.nu

		# Prettier and Cspell
		($bun)

		# Rustup
		http get ($rustup_url) | save ($rustup)
		if \('($rustup)' | path exists\) {
			print 'Downloaded rustup. Installing rustup...'
			chmod a+x ($rustup)
			^($rustup) -y --no-modify-path
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
	log info $"[install-user-scripts] Installing Rustup for `($container_user)`"
	log info $"[install-user-scripts] cmd: ($cmd)"
	print ""
	^buildah run --user $container_user $config.buildah.container -- $container_shell --login --commands $cmd
	$config
}


# Publish the image to the Docker registry.
def publish-image [
	name					# Image name
]: any -> any {
	use std log
	let config = $in

	# Publish the container as an image in buildah.
	let published_name = ($config.published | get $name | get name)
	let published_version = $config.published.version
	let image_name = ([
		($config.published | get $name | get name)
		($config.published | get $name | get version)
	]| str join ':')
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