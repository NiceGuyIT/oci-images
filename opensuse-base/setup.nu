#!/usr/bin/env nu

# Setup script that runs INSIDE the container during docker build.
# Subcommands are called from Dockerfile RUN steps.

const config_path = '/tmp/build/config.yml'
const bin_path = '/usr/local/bin'

# Install system packages via zypper
def "main install-packages" [
	--variant: string		# Variant: base or dev-extras
] {
	let config = (open $config_path)

	let packages = if $variant == "dev-extras" {
		# Only the packages in dev that aren't already in base
		let base_set = $config.packages.base
		$config.packages.dev | where {|pkg| $pkg not-in $base_set}
	} else {
		$config.packages | get $variant
	}

	print $"Installing ($variant) packages: ($packages | str join ' ')"
	^zypper --non-interactive --gpg-auto-import-keys refresh
	if $variant == "base" {
		# Only update during base install
		^zypper --non-interactive update
	}
	^zypper --non-interactive install ...($packages)
	^zypper --non-interactive clean --all
	print $"($variant) packages installed."
}

# Download all single-file binaries in parallel
def "main install-binaries" [] {
	let config = (open $config_path)

	print "Installing binaries..."
	# Skip the nu binary itself — it's already bootstrapped by the Dockerfile and is the
	# currently running process (overwriting would fail with "Text file busy").
	# Nu plugins (nu_plugin_*) are still installed.
	$config.binaries.list
	| where {|it| ($it.file? | default $it.name) != "nu" }
	| par-each --threads 4 {|it|
		let filename = ($it.file? | default $it.name)
		let url = (
			{
				"scheme": "https"
				"host": $config.binaries.host
				"path": (
					[
						'public'
						'linux'
						'x86_64'
						$it.name
						$it.version
						$filename
					] | path join
				)
			} | url join
		)
		print $"  Installing binary: '($filename)' from ($url)"
		http get $url | save $"($bin_path)/($filename)"
		chmod a+rx $"($bin_path)/($filename)"
	}
	print "Binaries installed."
}

# Create the dev user, configure sudo, clone dotfiles, run chezmoi
def "main add-user" [] {
	let config = (open $config_path)
	const container_user = 'dev'
	const login_shell = '/usr/bin/bash'

	let sudoer_text = $"# User rules for ($container_user)\n($container_user) ALL=\(ALL) NOPASSWD:ALL\n"
	let chezmoi_config = (
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

	# Register nu as a valid shell
	"/usr/local/bin/nu\n" | save --append /etc/shells

	# Create user with docker group access
	^useradd --groups 'users,docker' --shell $login_shell --create-home $container_user

	# Configure sudo
	$sudoer_text | save $"/etc/sudoers.d/50-($container_user)-user"

	# Create directories
	mkdir $"/home/($container_user)/projects"
	mkdir $"/home/($container_user)/.config/chezmoi"
	mkdir $"/home/($container_user)/.bun"

	# Clone dotfiles
	^git clone --depth 1 $config.dotfiles.repo $"/home/($container_user)/projects/dotfiles"

	# Write chezmoi config
	$chezmoi_config | save $"/home/($container_user)/.config/chezmoi/chezmoi.jsonc"

	# Fix ownership
	^chown -R $"($container_user):users" $"/home/($container_user)"

	# Apply chezmoi
	^su --login --command "/usr/local/bin/chezmoi apply --no-tty --no-pager" $container_user

	print "User setup complete."
}

# Install user-level tools (nvm, bun packages, uv tools, Rust)
# Called once during the base stage with --variant base
def "main install-user-tools" [
	--variant: string		# Variant: base or dev
] {
	let config = (open $config_path)
	let rust_version = ($config.rust?.version? | default "stable")

	# nvm and node
	nvm-install.nu

	# Install global NPM packages using bun
	$config.bun
	| get $variant
	| each {|it|
		print $"Installing bun package: ($it)"
		^bun install --global $it
	}
	^bun pm ls --global

	# Install global Python packages using uv
	$config.uv
	| get $variant
	| each {|it|
		print $"Installing uv tool: ($it)"
		^uv tool install $it
	}
	^uv tool list

	# Install Rust via rustup
	let rustup = '/tmp/rustup.sh'
	let rustup_url = 'https://sh.rustup.rs'
	http get $rustup_url | save $rustup
	if ($rustup | path exists) {
		print $"Downloaded rustup. Installing Rust ($rust_version)..."
		chmod a+x $rustup
		^$rustup -y --no-modify-path --default-toolchain $rust_version
		rm $rustup
	} else {
		print 'Failed to download rustup'
	}

	print $"User tools installed for variant: ($variant)"
}

# Install only the extra dev packages beyond base (bun and uv only).
# Called in the dev stage to avoid re-installing nvm, Rust, and base packages.
def "main install-dev-extras" [] {
	let config = (open $config_path)

	# Compute extra bun packages (dev minus base)
	let base_bun = ($config.bun.base)
	let dev_bun = ($config.bun.dev)
	let extra_bun = ($dev_bun | where {|pkg| $pkg not-in $base_bun})

	for pkg in $extra_bun {
		print $"Installing extra bun package: ($pkg)"
		^bun install --global $pkg
	}
	^bun pm ls --global

	# Compute extra uv tools (dev minus base)
	let base_uv = ($config.uv.base)
	let dev_uv = ($config.uv.dev)
	let extra_uv = ($dev_uv | where {|tool| $tool not-in $base_uv})

	for tool in $extra_uv {
		print $"Installing extra uv tool: ($tool)"
		^uv tool install $tool
	}
	^uv tool list

	print "Dev extras installed."
}

# Main entry point (shows usage)
def main [] {
	print "Usage: setup.nu <subcommand>"
	print "  install-packages --variant <base|dev-extras> - Install system packages via zypper"
	print "  install-binaries   - Download all single-file binaries"
	print "  add-user           - Create dev user and configure environment"
	print "  install-user-tools --variant <base|dev> - Install user-level tools"
	print "  install-dev-extras - Install only extra dev bun/uv packages"
}
