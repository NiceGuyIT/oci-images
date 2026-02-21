#!/usr/bin/env nu

# Load the configuration and compute all version tags
def load-config []: [nothing -> any, string -> any] {
	try {
		mut config = ($in | default "config.yml" | open)
		# Full version tag: v1.0.0-leap-16.0
		$config.published.base.version = ([
			$config.published.version
			$config.opensuse.name
			$config.opensuse.version
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
		# Major version tag: v1-leap-16.0
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
		# Minor version tag: v1.0-leap-16.0
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
		$config
	} catch {|err|
		use std log
		log error $"[load-config] Failed to load config: ($err.msg)"
		exit 1
	}
}

# Main script
def main [
	name					# Image name: base or dev
] {
	use std log

	if not ($name in [base dev]) {
		log error $"Invalid image name: ($name). Valid names are: 'base', 'dev'"
		exit 1
	}

	let config = (load-config)

	let published_name = ($config.published | get $name | get name)
	let published_version = ($config.published | get $name | get version)
	let published_major_version = ($config.published | get $name | get major_version)
	let published_minor_version = ($config.published | get $name | get minor_version)
	let published_latest = ($config.published | get $name | get latest)
	let published_latest_os = ($config.published | get $name | get latest_os)

	# setup.nu reads config.yml directly; only nu bootstrap args needed
	let nu_version = ($config.binaries.list | where name == 'nu' | first | get version)
	let binaries_host = $config.binaries.host
	let opensuse_version = $config.opensuse.version

	# Build with docker buildx, selecting the target stage
	let tags = [
		$"($published_name):($published_version)"
		$"($published_name):($published_major_version)"
		$"($published_name):($published_minor_version)"
		$"($published_name):($published_latest)"
		$"($published_name):($published_latest_os)"
	]
	let tag_args = ($tags | each {|t| ["--tag" $t]} | flatten)

	log info $"Building ($published_name) target=($name) with tags: ($tags | str join ', ')"
	(^docker buildx build
		--target $name
		--build-arg $"OPENSUSE_VERSION=($opensuse_version)"
		--build-arg $"NU_VERSION=($nu_version)"
		--build-arg $"BINARIES_HOST=($binaries_host)"
		...$tag_args
		--load
		.)

	log info $"Built image '($published_name)' with ($tags | length) tags"

	# Output for CI
	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($published_name)\n" | save --append $output
	let tag_values = ([
		$published_version
		$published_minor_version
		$published_major_version
		$published_latest
		$published_latest_os
	] | str join ' ')
	$"tags=($tag_values)\n" | save --append $output
}
