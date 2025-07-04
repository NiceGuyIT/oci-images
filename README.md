# OCI Images

This repo has two OCI images.

## smartctl_exporter

The `smartctl_exporter` image runs as the "nobody" user.

## WordPress

The `wordpress` image has the following libraries compiled in.

- php
  - pdo
  - pdo_mysql
  - soap
- redis
- xdebug (optional)
