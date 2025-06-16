#!/usr/bin/env nu
use std log


let config = (open config.yml)


let environment = ($env.ENVIRONMENT | default "debug")

# Image name

let image_name = $"smartctl-exporter-noroot"


let smartctl_exporter_tag = $config.smartctl_exporter.version
let image_version = $"smartctl-exporter-noroot-($smartctl_exporter_tag)"

let smartctl_exporter = (^buildah from $"docker.io/prometheuscommunity/smartctl-exporter:($smartctl_exporter_tag)")




log info $"========================================\n\n"
log info $"Setting user to root"
timeit {^buildah config --user root $smartctl_exporter}


log info "========================================\n\n"
log info "Running apk add shadow"
timeit {^buildah run $smartctl_exporter -- sh -c "apk add shadow"}

log info $"========================================\n\n"
log info $"Exposing port 9633"
timeit {^buildah config --port 9633 $smartctl_exporter}




log info $"========================================\n\n"
log info $"Setting user to nobody"
timeit {^buildah config --user nobody $smartctl_exporter}

log info $"========================================\n\n"
log info $"Setting entrypoint to /bin/smartctl_exporter"
timeit {^buildah config --entrypoint /bin/smartctl_exporter $smartctl_exporter}

# Publish the container as an image (in buildah).
let image = (^buildah commit $smartctl_exporter $image_name)
log info $"Built image '($image_name)' version '($image_version)'"

# Publish the image to Docker for use.
^buildah push $image $"docker-daemon:($image_name):($image_version)"
log info $"Published image '($image_name)' version '($image_version)' to Docker."



mut output = "output.log"
if ("GITHUB_OUTPUT" in $env) {
	# Output the information to the GitHub action.
	$output = $env.GITHUB_OUTPUT
}
$"image=($image_name)\n" | save --append $output
$"tags=($image_version)\n" | save --append $output
