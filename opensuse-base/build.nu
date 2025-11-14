#!/usr/bin/env nu

# Load the configuration
def load-config []: [nothing -> any, string -> any] {
	try {
		mut config = ($in | default "config.yml" | open)
		$config.published.version = ([
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
def install-packages []: any -> any {
	use std log
	let config = $in

	# Refresh the repos, update the system, and install packages.
	# Note: The semicolon separates the commands because they are joined with a space.
	# Quotes are needed to prevent Nushell from interpreting the semicolon as the end of the list.
	let cmd = ([
		zypper --non-interactive --gpg-auto-import-keys refresh ';'
		zypper --non-interactive update ';'
		zypper --non-interactive install ($config.packages.list | str join ' ') ';'
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

# Install user scripts
def install-user-scripts []: any -> any {
	let config = $in
	use std log

	# Add the "dev" user and configure their environment
	const container_user = 'dev'
	const container_shell = '/usr/local/bin/nu'

	# Execute the scripts as the user.
	let cmd = ([
		use claude.nu * ';'
		claude download ';'
		nvm-install.nu ';'
		# Use this for debugging purposes.
		# '$env.PATH' ';'
	] | str join ' ')

	log info $"========================================\n"
	log info $"[install-user-scripts] Installing user scripts for `($container_user)`"
	log info $"[install-user-scripts] cmd: ($cmd)"
	print ""
	^buildah run --user $container_user $config.buildah.container -- $container_shell --login --commands $'($cmd)'
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
		su --login --command "'/usr/local/bin/chezmoi apply'" $container_user
	] | str join ' ')

	log info $"========================================\n"
	log info $"[build-image] Creating ($container_user) user. cmd: ($cmd)"
	^buildah run $config.buildah.container -- /bin/sh -c $'($cmd)'
	^buildah config --user $container_user $config.buildah.container
	# ^buildah config --shell '/bin/sh -c' $config.buildah.container
	$config
}

# Publish the image to the Docker registry.
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

	# opensuse image
	$config.image.url = $"($config.opensuse.url):($config.opensuse.version)"

	log info $"[build-image] ========================================\n"
	log info $"[build-image] Pulling opensuse image from '($config.image.url)'"
	$config.buildah.container = (^buildah from $config.image.url)
	# $config.buildah.container = 'b0cc9405ec4d'

	# Install the packagesz
	$config
	| install-packages
	| install-binaries
	| add-user
	| install-user-scripts

	# TODO: Add programs:
	# yarn: https://yarnpkg.com/getting-started/install
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