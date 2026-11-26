#!/usr/bin/env bash
# install + start a wazuh agent in a container, pointed at the manager
# usage: wazuh-agent-install.sh <container> <manager-ip>
set -euo pipefail

C=$1
MGR=$2

incus exec "$C" -- bash -c '
set -e
apt-get update -qq
apt-get install -y -qq gpg curl >/dev/null
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring \
  --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq
# pin to the newest 4.14.x, the agent cant be newer than the 4.14 manager
VER=$(apt-cache madison wazuh-agent 2>/dev/null | awk "/ 4\.14\./ {print \$3; exit}")
WAZUH_MANAGER="'"$MGR"'" apt-get install -y -qq "wazuh-agent${VER:+=$VER}"
systemctl daemon-reload && systemctl enable --now wazuh-agent
'
