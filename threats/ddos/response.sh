#!/usr/bin/env bash
# apply the nftables rate limit and show one client throttled, the other fine
set -euo pipefail

VICTIM=apache-victim
URL="http://10.255.255.22/"

# clear any leftover firewall-drop from a prior Wazuh response so the burst runs
incus exec "$VICTIM" -- iptables -F 2>/dev/null || true
echo ">> applying per-client rate limit"
incus exec "$VICTIM" -- nft -f /etc/nftables-ratelimit.nft
incus exec "$VICTIM" -- nft list table inet ratelimit | grep "limit rate"

echo ">> noisy client floods (throughput should get clamped to the limit)"
incus exec load-client-a -- ab -r -n 40 -c 2 -s 2 "$URL" 2>/dev/null | grep -E "Requests per second"

echo ">> offending IP is now tracked/throttled:"
incus exec "$VICTIM" -- nft list set inet ratelimit throttled | grep -A2 elements || true

echo ">> a different client is unaffected:"
incus exec load-client-b -- curl -s -o /dev/null -w "client-b -> %{http_code}\n" --max-time 3 "$URL"

echo ">> to clear the rule: incus exec $VICTIM -- nft delete table inet ratelimit"
