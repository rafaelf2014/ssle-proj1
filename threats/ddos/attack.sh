#!/usr/bin/env bash
# bounded load test: cap the target, baseline, then the paired burst (<=80 reqs)
set -euo pipefail

VICTIM=apache-victim
URL="http://10.255.255.22/"

cap()   { incus config set $VICTIM limits.cpu=1 limits.memory=256MiB; }
uncap() { incus config unset $VICTIM limits.cpu || true; incus config unset $VICTIM limits.memory || true; }

# pull just the lines we care about out of ab output
ab_run() { # client n c label
	echo "--- $4 (client $1, n=$2 c=$3) ---"
	incus exec "$1" -- ab -n "$2" -c "$3" -s 5 "$URL" 2>/dev/null \
		| grep -E "Requests per second|Time per request|Failed requests|Non-2xx|Percentage of the requests served within.*95%" || true
}

cpu_busy() {
	incus exec "$VICTIM" -- bash -c "grep '^cpu ' /proc/stat" | awk '{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; print 1-idle/total}'
}

echo "=== capping target (cpu=1, mem=256MiB) ==="
cap
# wait for apache to actually answer before measuring
for i in $(seq 1 30); do
	incus exec load-client-a -- curl -fsS --max-time 3 "$URL" >/dev/null 2>&1 && break
	sleep 2
done

echo "=== baseline: client-a only, concurrency 1 ==="
ab_run load-client-a 40 1 baseline

echo "=== attack: both clients, concurrency 2, started together ==="
incus exec load-client-a -- ab -n 40 -c 2 -s 5 "$URL" >/tmp/aba.txt 2>&1 &
incus exec load-client-b -- ab -n 40 -c 2 -s 5 "$URL" >/tmp/abb.txt 2>&1 &
wait
for f in /tmp/aba.txt /tmp/abb.txt; do
	echo "--- $f ---"
	grep -E "Requests per second|Time per request|Failed requests|Non-2xx|Percentage of the requests served within.*95%" "$f" || true
done

echo "=== target CPU busy fraction right after burst ==="
cpu_busy

echo "=== restoring caps ==="
uncap
echo "done"
