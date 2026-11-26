#!/usr/bin/env bash
# make the k3s cluster + docker/registry box (needs the network + k3s profile)
# re-runnable: skips boxes that already exist
set -euo pipefail

REG_IP=10.255.255.10
MASTER_IP=10.255.255.11
NODE1_IP=10.255.255.12
IMAGE=images:debian/trixie

launch() {
	local name=$1 ip=$2
	if incus info "$name" >/dev/null 2>&1; then echo "$name exists, skipping"; return; fi
	incus init "$IMAGE" "$name" --profile k3s
	incus config device override "$name" eth0 ipv4.address="$ip"
	incus start "$name"
}

launch k3s-master "$MASTER_IP"
launch k3s-node1 "$NODE1_IP"
launch docker "$REG_IP"
sleep 5

# k3s server, traefik off to save RAM
incus exec k3s-master -- bash -c 'command -v k3s >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --node-ip '"$MASTER_IP"'" sh -; }'

TOKEN=$(incus exec k3s-master -- cat /var/lib/rancher/k3s/server/node-token)
incus exec k3s-node1 -- bash -c 'command -v k3s >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --node-ip '"$NODE1_IP"'" K3S_URL=https://'"$MASTER_IP"':6443 K3S_TOKEN='"$TOKEN"' sh -; }'

# both nodes pull from the local registry over http
for c in k3s-master k3s-node1; do
	incus exec "$c" -- mkdir -p /etc/rancher/k3s
	incus exec "$c" -- bash -c "cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  \"$REG_IP:5000\":
    endpoint:
      - \"http://$REG_IP:5000\"
EOF"
done
incus exec k3s-master -- systemctl restart k3s
incus exec k3s-node1 -- systemctl restart k3s-agent

# docker + registry; the daemon has to allow the http registry to push
incus exec docker -- bash -c 'command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh'
incus exec docker -- bash -c 'cat > /etc/docker/daemon.json <<EOF
{ "insecure-registries": ["'"$REG_IP"':5000"] }
EOF'
incus exec docker -- systemctl restart docker
incus exec docker -- bash -c 'docker inspect registry >/dev/null 2>&1 || docker run -d -p 5000:5000 --restart=always --name registry registry:2'

echo "cluster up. check: incus exec k3s-master -- kubectl get nodes"
