#!/usr/bin/env bash
# wazuh agent on the resolver + the rules on the manager
set -euo pipefail
cd "$(dirname "$0")/../.."

AGENT=dns-resolver
MANAGER_IP=10.255.255.21

echo ">> installing wazuh-agent on $AGENT"
bash scripts/wazuh-agent-install.sh "$AGENT" "$MANAGER_IP"

echo ">> telling the agent to read the resolver decision log as json"
incus exec "$AGENT" -- bash -c '
grep -q "/var/log/dns-resolver/events.log" /var/ossec/etc/ossec.conf || \
sed -i "s#</ossec_config>#  <localfile>\n    <log_format>json</log_format>\n    <location>/var/log/dns-resolver/events.log</location>\n  </localfile>\n</ossec_config>#" /var/ossec/etc/ossec.conf
systemctl restart wazuh-agent
'

echo ">> installing custom rules on the manager"
incus file push deploy/wazuh/local_rules.xml wazuh-container/var/ossec/etc/rules/local_rules.xml
incus exec wazuh-container -- bash -c 'chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml && systemctl restart wazuh-manager'

echo "done, trigger a sinkhole then check alerts on the manager"
