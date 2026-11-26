#!/usr/bin/env bash
# push the prometheus config + rules and reload
set -euo pipefail
cd "$(dirname "$0")/../.."

incus file push deploy/prometheus/prometheus.yml prometheus-container/etc/prometheus/prometheus.yml
incus exec prometheus-container -- mkdir -p /etc/prometheus/rules
incus file push deploy/prometheus/rules/alerts.yml prometheus-container/etc/prometheus/rules/alerts.yml
incus exec prometheus-container -- chown -R prometheus:prometheus /etc/prometheus

incus exec prometheus-container -- promtool check config /etc/prometheus/prometheus.yml
incus exec prometheus-container -- systemctl reload prometheus \
	|| incus exec prometheus-container -- systemctl restart prometheus

echo "prometheus UI: http://10.255.255.20:9090"
