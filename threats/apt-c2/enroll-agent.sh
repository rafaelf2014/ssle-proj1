#!/usr/bin/env bash
# wazuh agent + monitor on the victim, and the c2 rule + response on the manager
set -euo pipefail
cd "$(dirname "$0")/../.."

VICTIM=c2-victim
MANAGER_IP=10.255.255.21

# firewall-drop needs iptables present on the victim
echo ">> iptables + wazuh agent on $VICTIM"
incus exec "$VICTIM" -- bash -c 'apt-get update -qq && apt-get install -y -qq iptables >/dev/null'
bash scripts/wazuh-agent-install.sh "$VICTIM" "$MANAGER_IP"

echo ">> deploy the egress monitor"
incus file push threats/apt-c2/c2-monitor.sh "$VICTIM"/usr/local/bin/c2-monitor.sh
incus exec "$VICTIM" -- bash -c '
chmod +x /usr/local/bin/c2-monitor.sh
cat > /etc/systemd/system/c2-monitor.service <<EOF
[Unit]
Description=C2 egress monitor
After=network.target
[Service]
ExecStart=/usr/local/bin/c2-monitor.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF
grep -q "/var/log/c2-monitor/events.log" /var/ossec/etc/ossec.conf || \
sed -i "s#</ossec_config>#  <localfile>\n    <log_format>json</log_format>\n    <location>/var/log/c2-monitor/events.log</location>\n  </localfile>\n</ossec_config>#" /var/ossec/etc/ossec.conf
systemctl daemon-reload
systemctl enable --now c2-monitor
systemctl restart wazuh-agent
'

echo ">> manager: install C2 rule + active-response, restart"
incus file push deploy/wazuh/local_rules.xml wazuh-container/var/ossec/etc/rules/local_rules.xml
incus file push deploy/wazuh/active-response.conf wazuh-container/tmp/active-response.conf
incus exec wazuh-container -- bash -c '
chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml
grep -q "rules_id>100300" /var/ossec/etc/ossec.conf || cat /tmp/active-response.conf >> /var/ossec/etc/ossec.conf
rm -f /tmp/active-response.conf
systemctl restart wazuh-manager'

echo "done"
