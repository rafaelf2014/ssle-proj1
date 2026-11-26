#!/usr/bin/env bash
# make the capped apache target + two load clients + the exporters and agent
# (attack.sh applies the caps, not this)
set -euo pipefail
cd "$(dirname "$0")/../.."

VICTIM_IP=10.255.255.22
A_IP=10.255.255.28
B_IP=10.255.255.29
WAZUH_IP=10.255.255.21

incus start prometheus-container 2>/dev/null || true

launch() { # name ip
	if incus info "$1" >/dev/null 2>&1; then echo "   $1 exists"; return; fi
	incus init images:debian/trixie "$1"
	incus config device override "$1" eth0 ipv4.address="$2"
	incus start "$1"
}

echo ">> launching"
launch apache-victim "$VICTIM_IP"
launch load-client-a "$A_IP"
launch load-client-b "$B_IP"
sleep 6
for c in apache-victim load-client-a load-client-b; do
	incus exec "$c" -- bash -c 'rm -f /etc/resolv.conf; echo "nameserver 10.255.255.1" > /etc/resolv.conf'
done

echo ">> apache-victim: apache + page + node_exporter + nftables (rule staged, applied by response.sh)"
incus exec apache-victim -- bash -c 'apt-get update -qq && apt-get install -y -qq apache2 prometheus-node-exporter nftables curl'
incus file push threats/ddos/index.html apache-victim/var/www/html/index.html
incus file push threats/ddos/ratelimit.nft apache-victim/etc/nftables-ratelimit.nft
# cpu-heavy cgi endpoint for the stress test
incus exec apache-victim -- bash -c 'command -v python3 >/dev/null || apt-get install -y -qq python3; a2enmod -q cgid'
incus file push threats/ddos/cgi-bin/work apache-victim/usr/lib/cgi-bin/work
incus exec apache-victim -- chmod +x /usr/lib/cgi-bin/work
incus exec apache-victim -- bash -c '
	systemctl restart apache2
	systemctl enable --now prometheus-node-exporter'

echo ">> apache-victim: iptables (for firewall-drop) + wazuh agent + feed access.log"
incus exec apache-victim -- bash -c 'command -v iptables >/dev/null || (apt-get update -qq && apt-get install -y -qq iptables)'
bash scripts/wazuh-agent-install.sh apache-victim "$WAZUH_IP"
incus exec apache-victim -- bash -c '
grep -q "/var/log/apache2/access.log" /var/ossec/etc/ossec.conf || \
sed -i "s#</ossec_config>#  <localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/apache2/access.log</location>\n  </localfile>\n</ossec_config>#" /var/ossec/etc/ossec.conf
systemctl restart wazuh-agent'

echo ">> manager: install the DoS burst rule + active-response"
incus file push deploy/wazuh/local_rules.xml wazuh-container/var/ossec/etc/rules/local_rules.xml
incus file push deploy/wazuh/active-response.conf wazuh-container/tmp/active-response.conf
incus exec wazuh-container -- bash -c '
chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml
grep -q "rules_id>100400" /var/ossec/etc/ossec.conf || cat /tmp/active-response.conf >> /var/ossec/etc/ossec.conf
rm -f /tmp/active-response.conf
systemctl restart wazuh-manager'

echo ">> load clients: ab"
for c in load-client-a load-client-b; do
	incus exec "$c" -- bash -c 'apt-get update -qq && apt-get install -y -qq apache2-utils curl'
done

echo ">> prometheus: blackbox exporter + updated config + ddos rules"
incus exec prometheus-container -- bash -c 'apt-get update -qq && apt-get install -y -qq prometheus-blackbox-exporter && systemctl enable --now prometheus-blackbox-exporter'
incus file push deploy/prometheus/prometheus.yml prometheus-container/etc/prometheus/prometheus.yml
incus file push deploy/prometheus/rules/ddos.yml prometheus-container/etc/prometheus/rules/ddos.yml
incus exec prometheus-container -- bash -c 'chown -R prometheus:prometheus /etc/prometheus; promtool check config /etc/prometheus/prometheus.yml && (systemctl reload prometheus || systemctl restart prometheus)'

echo "done. victim=$VICTIM_IP clients=$A_IP,$B_IP"
