#!/usr/bin/env bash
# watch for an outbound connection to the handler and log it as json for wazuh
set -u

PORT="${C2_PORT:-4444}"
LOG="${C2_LOG:-/var/log/c2-monitor/events.log}"
INTERVAL="${C2_INTERVAL:-5}"
mkdir -p "$(dirname "$LOG")"

declare -A seen   # remember connections already reported so we don't re-log every cycle

while true; do
	# grab the ip ending in :PORT, that's the handler we want to block
	while read -r line; do
		remote=$(echo "$line" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:$PORT" | head -1)
		[ -z "$remote" ] && continue
		# the local ip:port is unique per connection, use it as the dedup key
		lep=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | grep -v ":$PORT\$" | head -1)
		[ -n "${seen[$lep]:-}" ] && continue
		seen[$lep]=1
		rip=${remote%:*}
		proc=$(echo "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
		ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
		printf '{"event":"c2_egress","timestamp":"%s","srcip":"%s","remote":"%s","process":"%s"}\n' \
			"$ts" "$rip" "$remote" "$proc" >> "$LOG"
	done < <(ss -Htnp state established "( dport = :$PORT )" 2>/dev/null)
	sleep "$INTERVAL"
done
