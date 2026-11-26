#!/usr/bin/env bash
# make the wazuh box and install the siem (manager + indexer + dashboard). slow
set -euo pipefail

IP=10.255.255.21

# the opensearch indexer needs this on the host kernel (containers share it)
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
sudo sysctl -w vm.max_map_count=262144

if ! incus info wazuh-container >/dev/null 2>&1; then
	incus init images:ubuntu/22.04 wazuh-container
	incus config device override wazuh-container eth0 ipv4.address="$IP"
	incus start wazuh-container
	sleep 8
fi

# IMPORTANT: stop the rest of the lab first so the indexer gets the cpu, or its
# startup times out and the whole install rolls back:
#   incus stop k3s-master k3s-node1 docker prometheus-container

incus exec wazuh-container -- bash -c '
set -e
apt-get update -qq && apt-get install -y -qq curl
cd /root
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
chmod +x wazuh-install.sh
./wazuh-install.sh -a -i
'

# stash the admin creds in the git-ignored .secrets/ so they're easy to find later
cd "$(dirname "$0")/../.."
mkdir -p .secrets
incus exec wazuh-container -- bash -c 'cd /root && tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt' > .secrets/wazuh-passwords.txt
chmod 600 .secrets/wazuh-passwords.txt

echo "done. creds saved to .secrets/wazuh-passwords.txt, dashboard at https://$IP/"
