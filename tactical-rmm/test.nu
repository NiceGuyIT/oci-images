#!/usr/bin/env nu
#
# Functional test for a Tactical RMM deployment.
#
# Exercises every public protocol surface so a single run answers "is the stack
# healthy after my change?":
#
#   * DNS resolution for APP_HOST, API_HOST, MESH_HOST
#   * TLS handshake on each host
#   * HTTP -> HTTPS 301 redirect on each host
#   * Vue frontend SPA load and asset fetch
#   * Django REST API (X-API-KEY auth + reject on missing key)
#   * Django Channels websocket upgrade (/ws/dashinfo/)
#   * NATS websocket bridge upgrade (/natsws)
#   * Django static file serving (/static/)
#   * MeshCentral web UI reachable
#   * MeshCentral login (when --mesh-user / --mesh-pass supplied)
#
# All tests are read-only; nothing in the deployment is mutated.
#
# Usage:
#   ./test.nu --domain example.com --api-key <KEY>
#   ./test.nu --app-host rmm.x.com --api-host api.x.com --mesh-host mesh.x.com --api-key <KEY>
#   ./test.nu --domain example.com --api-key <KEY> --mesh-user tactical --mesh-pass secret --insecure
#
# Exit code: 0 when every test passes, 1 when any test fails.

use std log

# ----------------------------------------------------------------------------
# Helpers

# Resolve hosts from --domain or explicit overrides.
def resolve-hosts [
	domain: string
	app: string
	api: string
	mesh: string
]: nothing -> record {
	if not ($domain | is-empty) {
		return {
			app: $"rmm.($domain)"
			api: $"api.($domain)"
			mesh: $"mesh.($domain)"
		}
	}
	if ($app | is-empty) or ($api | is-empty) or ($mesh | is-empty) {
		log error "Provide --domain, or all three of --app-host / --api-host / --mesh-host"
		exit 2
	}
	{app: $app, api: $api, mesh: $mesh}
}

# Build the curl flag list that every request shares.
def curl-base [insecure: bool, timeout: int]: nothing -> list<string> {
	mut args = [
		"--silent"
		"--show-error"
		"--max-time" ($timeout | into string)
	]
	if $insecure {
		$args = ($args | append "--insecure")
	}
	$args
}

# Run curl and capture status code + body in a single call.
# Returns {code: int, body: string, ok: bool, error: string}.
def http-probe [
	url: string
	insecure: bool
	timeout: int
	--header (-H): list<string> = []
	--method (-X): string = "GET"
]: nothing -> record {
	mut args = (curl-base $insecure $timeout)
	$args = ($args | append ["--request" $method "--write-out" "\n%{http_code}"])
	for h in $header {
		$args = ($args | append ["--header" $h])
	}
	$args = ($args | append $url)

	let out = (^curl ...$args | complete)
	if $out.exit_code != 0 {
		return {
			code: 0
			body: ""
			ok: false
			error: $"curl exit ($out.exit_code): ($out.stderr | str trim)"
		}
	}

	let lines = ($out.stdout | lines)
	let code = ($lines | last | into int)
	let body = ($lines | drop 1 | str join "\n")
	{code: $code, body: $body, ok: true, error: ""}
}

# Run a websocket upgrade probe via curl. Expects HTTP 101 on success;
# 4xx is still useful evidence (proxy reached the upstream, upstream rejected
# unauthenticated request) so we surface the code and let the caller decide.
def ws-probe [
	url: string
	insecure: bool
	timeout: int
]: nothing -> record {
	mut args = (curl-base $insecure $timeout)
	$args = ($args | append [
		"--http1.1"
		"--include"
		"--output" "/dev/null"
		"--write-out" "%{http_code}"
		"--header" "Connection: Upgrade"
		"--header" "Upgrade: websocket"
		"--header" "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="
		"--header" "Sec-WebSocket-Version: 13"
		$url
	])
	let out = (^curl ...$args | complete)
	if $out.exit_code != 0 {
		return {code: 0, ok: false, error: $"curl exit ($out.exit_code)"}
	}
	{code: ($out.stdout | into int), ok: true, error: ""}
}

# Append a result row, print live status, return the updated list.
def record-result [
	results: list<record>
	name: string
	ok: bool
	detail: string
]: nothing -> list<record> {
	let tag = (if $ok { "[ PASS ]" } else { "[ FAIL ]" })
	print $"($tag) ($name) -- ($detail)"
	$results | append {name: $name, ok: $ok, detail: $detail}
}

# ----------------------------------------------------------------------------
# Individual test groups

def test-dns [hosts: record, results: list<record>]: nothing -> list<record> {
	mut r = $results
	for host in [$hosts.app $hosts.api $hosts.mesh] {
		let probe = (^getent hosts $host | complete)
		let ok = ($probe.exit_code == 0)
		let detail = (if $ok { ($probe.stdout | str trim) } else { "no DNS record" })
		$r = (record-result $r $"dns ($host)" $ok $detail)
	}
	$r
}

def test-tls [
	hosts: record
	insecure: bool
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	mut r = $results
	for host in [$hosts.app $hosts.api $hosts.mesh] {
		let probe = (http-probe $"https://($host)/" $insecure $timeout)
		let ok = ($probe.ok and $probe.code > 0)
		let detail = (if $probe.ok {
			$"HTTP ($probe.code)"
		} else {
			$probe.error
		})
		$r = (record-result $r $"tls ($host)" $ok $detail)
	}
	$r
}

def test-redirects [
	hosts: record
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	mut r = $results
	for host in [$hosts.app $hosts.api $hosts.mesh] {
		# Plain HTTP, follow no redirects, expect 301.
		let probe = (http-probe $"http://($host)/" false $timeout)
		let ok = ($probe.code == 301)
		let detail = $"HTTP ($probe.code)"
		$r = (record-result $r $"http->https redirect ($host)" $ok $detail)
	}
	$r
}

def test-frontend [
	hosts: record
	insecure: bool
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	mut r = $results
	let url = $"https://($hosts.app)/"
	let probe = (http-probe $url $insecure $timeout)
	let ok = ($probe.code == 200 and ($probe.body | str contains "<div id=\"app\""))
	let detail = $"HTTP ($probe.code), SPA root marker ('<div id=\"app\"') ($ok)"
	$r = (record-result $r "frontend SPA loads" $ok $detail)

	# Pull a hashed asset URL out of the SPA HTML and fetch it. Vue/Vite emit
	# /assets/ or hashed JS filenames in the document head.
	let asset = (
		$probe.body
		| parse --regex '(?P<u>/(?:assets|js)/[A-Za-z0-9._-]+\.(?:js|css))'
		| get --optional u.0
	)
	if ($asset | is-empty) {
		return (record-result $r "frontend asset fetch" false "no asset URL found in SPA HTML")
	}
	let asset_probe = (http-probe $"https://($hosts.app)($asset)" $insecure $timeout)
	let asset_ok = ($asset_probe.code == 200)
	$r = (record-result $r "frontend asset fetch" $asset_ok $"GET ($asset) -> HTTP ($asset_probe.code)")
	$r
}

def test-backend [
	hosts: record
	api_key: string
	insecure: bool
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	mut r = $results
	let api = $"https://($hosts.api)"
	let auth = [$"X-API-KEY: ($api_key)"]

	# Reject missing key
	let unauth = (http-probe $"($api)/core/version/" $insecure $timeout)
	let unauth_ok = ($unauth.code == 401 or $unauth.code == 403)
	$r = (record-result $r "backend rejects missing API key" $unauth_ok $"HTTP ($unauth.code) [expected 401 or 403]")

	# Authenticated reads
	let endpoints = [
		"core/version/"
		"core/dashinfo/"
		"clients/"
		"agents/"
		"alerts/"
		"scripts/"
		"checks/"
		"tasks/"
		"automation/policies/"
	]
	for ep in $endpoints {
		let probe = (http-probe --header $auth $"($api)/($ep)" $insecure $timeout)
		let ok = ($probe.code >= 200 and $probe.code < 300)
		$r = (record-result $r $"backend GET /($ep)" $ok $"HTTP ($probe.code)")
	}
	$r
}

def test-static [
	hosts: record
	insecure: bool
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	# We don't know which exact static file exists, so prove nginx is serving
	# the /static/ tree at all: a missing file under /static/ must come back as
	# 404 from nginx (file not found), not 502/503/504 (upstream unreachable).
	let probe = (http-probe $"https://($hosts.api)/static/__healthcheck__.txt" $insecure $timeout)
	let ok = ($probe.code == 404 or ($probe.code >= 200 and $probe.code < 300))
	let detail = $"HTTP ($probe.code) [404 from disk means nginx /static/ routing is healthy]"
	record-result $results "nginx serves /static/" $ok $detail
}

def test-websockets [
	hosts: record
	insecure: bool
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	mut r = $results

	# Django Channels: nginx must proxy /ws/ to tactical-websockets. Without
	# Knox auth the upstream returns 4xx, but the proxy hop must work.
	let dash = (ws-probe $"https://($hosts.api)/ws/dashinfo/" $insecure $timeout)
	let dash_ok = ($dash.code == 101 or ($dash.code >= 400 and $dash.code < 500))
	$r = (record-result $r "websocket /ws/dashinfo/ upgrade reaches upstream" $dash_ok $"HTTP ($dash.code)")

	# NATS websocket bridge
	let nats = (ws-probe $"https://($hosts.api)/natsws" $insecure $timeout)
	let nats_ok = ($nats.code == 101 or ($nats.code >= 400 and $nats.code < 500))
	$r = (record-result $r "websocket /natsws upgrade reaches NATS" $nats_ok $"HTTP ($nats.code)")
	$r
}

def test-mesh [
	hosts: record
	mesh_user: string
	mesh_pass: string
	insecure: bool
	timeout: int
	results: list<record>
]: nothing -> list<record> {
	mut r = $results
	let mesh = $"https://($hosts.mesh)"

	let root = (http-probe $mesh $insecure $timeout)
	let root_ok = ($root.code == 200 and ($root.body | str contains "MeshCentral"))
	$r = (record-result $r "MeshCentral web UI loads" $root_ok $"HTTP ($root.code), MeshCentral marker present ($root_ok)")

	if ($mesh_user | is-empty) or ($mesh_pass | is-empty) {
		print "       (mesh login skipped: --mesh-user / --mesh-pass not provided)"
		return $r
	}

	# MeshCentral's login endpoint accepts form-encoded creds and either sets a
	# session cookie (success) or 4xx (bad creds). Use --include so the response
	# headers land in stdout and we can grep for Set-Cookie.
	mut args = (curl-base $insecure $timeout)
	$args = ($args | append [
		"--include"
		"--data-urlencode" $"username=($mesh_user)"
		"--data-urlencode" $"password=($mesh_pass)"
		$"($mesh)/login-handler"
	])
	let login = (^curl ...$args | complete)
	let login_ok = ($login.stdout | str contains "Set-Cookie")
	let detail = (if $login_ok {
		"Set-Cookie present"
	} else {
		"no Set-Cookie -- auth rejected or endpoint moved"
	})
	$r = (record-result $r "MeshCentral login accepts credentials" $login_ok $detail)
	$r
}

# ----------------------------------------------------------------------------
# Main

def main [
	--domain: string = ""           # Root domain; APP/API/MESH derived as rmm./api./mesh.
	--app-host: string = ""         # Override APP_HOST (e.g. rmm.example.com)
	--api-host: string = ""         # Override API_HOST
	--mesh-host: string = ""        # Override MESH_HOST
	--api-key: string               # X-API-KEY for the Django backend (required)
	--mesh-user: string = ""        # MeshCentral admin username (optional)
	--mesh-pass: string = ""        # MeshCentral admin password (optional)
	--insecure                      # Skip TLS verification (use for self-signed certs)
	--timeout: int = 10             # Per-request timeout in seconds
] {
	if ($api_key | is-empty) {
		log error "--api-key is required"
		exit 2
	}

	let hosts = (resolve-hosts $domain $app_host $api_host $mesh_host)
	let started = (date now)

	print "Tactical RMM functional test"
	print $"  app:    https://($hosts.app)"
	print $"  api:    https://($hosts.api)"
	print $"  mesh:   https://($hosts.mesh)"
	print $"  insecure TLS: ($insecure)"
	print $"  timeout: ($timeout)s"
	print ""

	mut results = []
	$results = (test-dns $hosts $results)
	$results = (test-tls $hosts $insecure $timeout $results)
	$results = (test-redirects $hosts $timeout $results)
	$results = (test-frontend $hosts $insecure $timeout $results)
	$results = (test-backend $hosts $api_key $insecure $timeout $results)
	$results = (test-static $hosts $insecure $timeout $results)
	$results = (test-websockets $hosts $insecure $timeout $results)
	$results = (test-mesh $hosts $mesh_user $mesh_pass $insecure $timeout $results)

	let elapsed = ((date now) - $started)
	let passed = ($results | where ok | length)
	let failed = ($results | where { |r| not $r.ok } | length)
	let total = ($results | length)

	print ""
	print $"-----------------------------------------------------------"
	print $"($passed) passed, ($failed) failed, ($total) total -- elapsed ($elapsed)"

	if $failed > 0 {
		print ""
		print "Failed tests:"
		for r in ($results | where { |x| not $x.ok }) {
			print $"  - ($r.name): ($r.detail)"
		}
		exit 1
	}
}
