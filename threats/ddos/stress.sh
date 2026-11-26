#!/usr/bin/env bash
# flood the cpu-heavy endpoint from both clients
# usage: stress.sh [duration_s] [concurrency] [workers_per_client]
set -uo pipefail

VICTIM=apache-victim
URL="http://10.255.255.22/cgi-bin/work"
DURATION="${1:-90}"      # must exceed the 1m "for:" on the latency/cpu alerts
CONC="${2:-40}"
WORKERS="${3:-3}"

# cap to 1 cpu so the flood has something to saturate
incus config set "$VICTIM" limits.cpu=1 limits.memory=256MiB
# clear any leftover firewall-drop so the flood gets through
incus exec "$VICTIM" -- iptables -F 2>/dev/null || true

echo ">> stressing $URL for ${DURATION}s (concurrency=$CONC, ${WORKERS} workers x 2 clients)"
pids=()
for c in load-client-a load-client-b; do
	for _ in $(seq 1 "$WORKERS"); do
		incus exec "$c" -- ab -t "$DURATION" -c "$CONC" -n 100000000 "$URL" >/dev/null 2>&1 &
		pids+=($!)
	done
done
wait "${pids[@]}" 2>/dev/null || true

echo ">> flood done. watch Prometheus: ApacheVictimCPUSaturated + ApacheHighLatency (fire after ~1m sustained)"
echo ">> cap left on so the graphs are readable; clear it with:"
echo "   incus config unset $VICTIM limits.cpu && incus config unset $VICTIM limits.memory"
