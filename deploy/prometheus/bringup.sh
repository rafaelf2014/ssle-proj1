#!/usr/bin/env bash
# make the prometheus box, install prometheus, apply the config
set -euo pipefail
cd "$(dirname "$0")/../.."

IP=10.255.255.20
if ! incus info prometheus-container >/dev/null 2>&1; then
	incus init images:debian/trixie prometheus-container
	incus config device override prometheus-container eth0 ipv4.address="$IP"
	incus start prometheus-container
	sleep 6
fi

incus exec prometheus-container -- bash -c \
	'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq prometheus'

bash deploy/prometheus/apply.sh
