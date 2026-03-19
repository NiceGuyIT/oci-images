#!/bin/sh
# Wrapper script to invoke WP-CLI via FrankenPHP's embedded PHP interpreter.
exec /usr/local/bin/frankenphp php-cli /usr/local/bin/wp-cli.phar "$@"
