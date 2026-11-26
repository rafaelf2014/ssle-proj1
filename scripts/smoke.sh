#!/usr/bin/env bash
# run the five services locally, test the whole chain, tear down. no containers
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$PATH:/usr/local/go/bin"

BIN=$(mktemp -d)
DB="$BIN/storage.db"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
	rm -rf "$BIN"
}
trap cleanup EXIT

echo "building..."
go build -o "$BIN/registry"  ./services/registry
go build -o "$BIN/storage"   ./services/storage
go build -o "$BIN/ingestion" ./services/ingestion
go build -o "$BIN/analytics" ./services/analytics

wait_health() {
	local url=$1 name=$2
	for _ in $(seq 1 50); do
		if curl -fsS "$url/healthz" >/dev/null 2>&1; then return 0; fi
		sleep 0.1
	done
	echo "FAIL: $name did not become healthy at $url" >&2
	return 1
}

start() { "$@" & PIDS+=($!); }

echo "starting services..."
start env SERVICE_ID=eu-pt.aveiro-dc1.rack1.k3s-master.registry.1 LISTEN_ADDR=:5050 "$BIN/registry"
wait_health http://127.0.0.1:5050 registry

start env SERVICE_ID=eu-pt.aveiro-dc1.rack3.k3s-node1.storage.1 LISTEN_ADDR=:5002 \
	SELF_URL=http://127.0.0.1:5002 DB_PATH="$DB" "$BIN/storage"
wait_health http://127.0.0.1:5002 storage

start env SERVICE_ID=eu-pt.aveiro-dc1.rack2.k3s-node1.ingestion.1 LISTEN_ADDR=:5001 \
	SELF_URL=http://127.0.0.1:5001 STORAGE_URL=http://127.0.0.1:5002 "$BIN/ingestion"
wait_health http://127.0.0.1:5001 ingestion

start env SERVICE_ID=eu-pt.aveiro-dc1.rack2.k3s-node1.analytics.1 LISTEN_ADDR=:5003 \
	SELF_URL=http://127.0.0.1:5003 STORAGE_URL=http://127.0.0.1:5002 "$BIN/analytics"
wait_health http://127.0.0.1:5003 analytics

echo "feeding readings through ingestion..."
for temp in 20.0 22.0 24.0; do
	curl -fsS -X POST http://127.0.0.1:5001/ingest \
		-H 'Content-Type: application/json' \
		-d "{\"device_id\":\"sensor-1\",\"temperature\":$temp}" >/dev/null
done

echo
echo "GET /average (expect average 22, count 3):"
AVG=$(curl -fsS http://127.0.0.1:5003/average)
echo "  $AVG"
echo "$AVG" | grep -q '"count":3' || { echo "FAIL: wrong count" >&2; exit 1; }
echo "$AVG" | grep -q '"average":22' || { echo "FAIL: wrong average" >&2; exit 1; }

echo
echo "GET /services (expect storage, ingestion, analytics registered with location):"
curl -fsS http://127.0.0.1:5050/services
echo
curl -fsS http://127.0.0.1:5050/services | grep -q '"rack":"rack3"' || { echo "FAIL: location missing" >&2; exit 1; }

echo
echo "SMOKE OK"
