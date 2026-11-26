#!/usr/bin/env bash
# build every service image and push it to the local registry (runs on the docker box)
set -euo pipefail

REGISTRY="${REGISTRY:-10.255.255.10:5000}"
TAG="${TAG:-dev}"
SRC="${SRC:-$(cd "$(dirname "$0")/../.." && pwd)}"
SERVICES=(registry ingestion sensor storage analytics)

for svc in "${SERVICES[@]}"; do
	img="$REGISTRY/ssle-$svc:$TAG"
	echo ">> building $img"
	docker build -f "$SRC/deploy/docker/Dockerfile" --build-arg SERVICE="$svc" -t "$img" "$SRC"
	docker push "$img"
done

echo ">> registry catalog:"
curl -fsS "http://$REGISTRY/v2/_catalog"
