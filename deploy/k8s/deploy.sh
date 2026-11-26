#!/usr/bin/env bash
# build+push the images and apply the k8s manifests
set -euo pipefail

cd "$(dirname "$0")/../.."

echo ">> syncing source to the docker box"
incus exec docker -- rm -rf /root/ssle
incus exec docker -- mkdir -p /root/ssle
tar --exclude=.git --exclude=bin --exclude='*.db' -czf - go.mod go.sum services deploy \
	| incus exec docker -- tar -C /root/ssle -xzf -

echo ">> building + pushing images"
incus exec docker -- bash -c 'SRC=/root/ssle REGISTRY=10.255.255.10:5000 bash /root/ssle/deploy/docker/build-push.sh'

echo ">> applying manifests"
tar -C deploy/k8s -czf - . | incus exec k3s-master -- bash -c 'mkdir -p /root/k8s && tar -C /root/k8s -xzf -'
incus exec k3s-master -- kubectl apply -f /root/k8s/

echo ">> pods:"
incus exec k3s-master -- kubectl -n ssle get pods -o wide
