#!/usr/bin/env nu

# Build a rust-builder image variant via `docker buildx build --target <variant>`.
# Tags are computed from config.yml and written to $GITHUB_OUTPUT (CI) or output.log (local).

const valid_variants = ['base' 'dioxus' 'dioxus-desktop']

# Load config.yml and derive the version-tag suffixes used to tag every image.
def load-config []: [nothing -> any] {
	try {
		let config = (open config.yml)

		# Suffix common to every tag for the base image: <rust>-<debian>.
		let base_suffix = ([
			$"rust($config.rust.version)"
			$config.debian.variant
		] | str join '-')

		# Suffix for the dioxus + dioxus-desktop variants additionally encodes
		# the pinned dioxus-cli version.
		let dioxus_suffix = ([
			$"dioxus($config.dioxus.version)"
			$base_suffix
		] | str join '-')

		# Semver-compatible shortened versions.
		let version_parts = ($config.published.version | split row '.')
		let major = ($version_parts | first 1 | str join)
		let minor = ($version_parts | first 2 | str join '.')

		$config
		| upsert published.major_version $major
		| upsert published.minor_version $minor
		| upsert published.base_suffix $base_suffix
		| upsert published.dioxus_suffix $dioxus_suffix
	} catch {|err|
		use std log
		log error $"[load-config] Failed to load config: ($err.msg)"
		exit 1
	}
}

# Compute the tag list for a given variant.
def compute-tags [config: any, variant: string]: [nothing -> list<string>] {
	# 'base' uses the rust+debian suffix only; dioxus and dioxus-desktop also
	# encode the dioxus-cli version.
	let suffix = if $variant == 'base' {
		$config.published.base_suffix
	} else {
		$config.published.dioxus_suffix
	}

	[
		$"($config.published.version)-($suffix)"
		$"($config.published.minor_version)-($suffix)"
		$"($config.published.major_version)-($suffix)"
		$"latest-($suffix)"
		'latest'
	]
}

# Main script.
def main [
	variant		# Stage to build: base | dioxus | dioxus-desktop
] {
	use std log

	if not ($variant in $valid_variants) {
		log error $"Invalid variant: ($variant). Valid: ($valid_variants | str join ', ')"
		exit 1
	}

	let config = (load-config)
	let image = ($config.published.variants | get $variant | get name)
	let tags = (compute-tags $config $variant)
	let tag_args = ($tags | each {|t| ['--tag' $"($image):($t)"]} | flatten)

	log info $"Building ($image) target=($variant) with tags: ($tags | str join ', ')"

	(^docker buildx build
		--target $variant
		--build-arg $"RUST_VERSION=($config.rust.version)"
		--build-arg $"DEBIAN_VARIANT=($config.debian.variant)"
		--build-arg $"DIOXUS_CLI_VERSION=($config.dioxus.version)"
		...$tag_args
		--load
		.)

	log info $"Built image '($image)' with ($tags | length) tags"

	# Output for CI / local debugging.
	mut output = "output.log"
	if ("GITHUB_OUTPUT" in $env) {
		$output = $env.GITHUB_OUTPUT
	}
	$"image=($image)\n" | save --append $output
	$"tags=($tags | str join ' ')\n" | save --append $output
}
