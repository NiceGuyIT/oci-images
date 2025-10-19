#!/usr/bin/env nu

# https://github.com/devcontainers/features/blob/main/src/docker-in-docker/install.sh
# https://github.com/microsoft/vscode-dev-containers
# https://github.com/microsoft/vscode-dev-containers/tree/main/containers/docker-from-docker

mount -t securityfs none /sys/kernel/security
mount -t tmpfs none /tmp

# mkdir /sys/fs/cgroup/init

# This doesn't work
# open /sys/fs/cgroup/cgroup.procs | save --force /sys/fs/cgroup/init/cgroup.procs
# open /sys/fs/cgroup/cgroup.controllers | sed -e 's/ / +/g' -e 's/^/+/' | save --force /sys/fs/cgroup/cgroup.subtree_control

dockerd --default-address-pool base=10.210.0.0/16,size=24
