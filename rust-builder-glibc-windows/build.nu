#!/usr/bin/env nu

# Build the rust-builder-glibc-windows image and emit tags + image name.

def load-config []: [nothing -> any] {
	try {
		let config = (open config.yml)

		let suffix = ([
			$"rust($config.rust.version)"
			$config.debian.variant
		] | str join '-')

		let parts = ($config.published.version | split row '.')
		let major = ($parts | first 1 | str join)
		let minor = ($parts | first 2 | str join '.')

		$config
		| upsert published.major_version $major
		| upsert published.minor_version $minor
		| upsert published.suffix $suffix
	} catch {|err|
		use std log
		log error $"[load-config] Failed to load config: ($err.msg)"
		exit 1
	}
}

def main [] {
	use std log

	let config = (load-config)
	let image = $config.published.name
	let s = $config.published.suffix

	let tags = [
		$"($config.published.version)-($s)"
		$"($config.published.minor_version)-($s)"
		$"($config.published.major_version)-($s)"
		$"latest-($s)"
		'latest'
	]
	let tag_args = ($tags | each {|t| ['--tag' $"($image):($t)"]} | flatten)

	log info $"Building ($image) with tags: ($tags | str join ', ')"

	(^docker buildx build
		--build-arg $"RUST_VERSION=($config.rust.version)"
		--build-arg $"DEBIAN_VARIANT=($config.debian.variant)"
		...$tag_args
		--load
		.)

	log info $"Built ($image) with ($tags | length) tags"

	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($image)\n" | save --append $output
	$"tags=($tags | str join ' ')\n" | save --append $output
}
