#!/usr/bin/env bash
# make the rogue resolver, fake bank, protective resolver and victim boxes
set -euo pipefail
cd "$(dirname "$0")/../.."

GO=${GO:-/usr/local/go/bin/go}
ROGUE_IP=10.255.255.23
BANK_IP=10.255.255.24
RESOLVER_IP=10.255.255.25
VICTIM_IP=10.255.255.30

echo ">> building binaries"
CGO_ENABLED=0 $GO build -o bin/fake-bank ./threats/dns-hijack/fake-bank
CGO_ENABLED=0 $GO build -o bin/dns-resolver ./threats/dns-hijack/resolver

launch() { # name ip
	if incus info "$1" >/dev/null 2>&1; then echo "   $1 exists"; return; fi
	incus init images:debian/trixie "$1"
	incus config device override "$1" eth0 ipv4.address="$2"
	incus start "$1"
}

echo ">> launching containers"
launch dns-rogue "$ROGUE_IP"
launch fake-bank "$BANK_IP"
launch dns-resolver "$RESOLVER_IP"
launch dns-victim "$VICTIM_IP"
sleep 6

# point apt at the bridge resolver and free up port 53 on the dns boxes
prep() {
	incus exec "$1" -- bash -c '
		systemctl disable --now systemd-resolved 2>/dev/null || true
		rm -f /etc/resolv.conf; echo "nameserver 10.255.255.1" > /etc/resolv.conf'
}
for c in dns-rogue fake-bank dns-resolver dns-victim; do prep "$c"; done

echo ">> dns-rogue: dnsmasq"
incus exec dns-rogue -- bash -c 'apt-get update -qq && apt-get install -y -qq dnsmasq'
incus file push threats/dns-hijack/dnsmasq.conf dns-rogue/etc/dnsmasq.conf
incus exec dns-rogue -- bash -c 'dnsmasq --test && systemctl restart dnsmasq && systemctl enable dnsmasq'

echo ">> fake-bank: login clone"
incus file push bin/fake-bank fake-bank/usr/local/bin/fake-bank
incus exec fake-bank -- bash -c 'cat > /etc/systemd/system/fake-bank.service <<EOF
[Unit]
Description=fake-bank (fictional lab login)
After=network.target
[Service]
ExecStart=/usr/local/bin/fake-bank
Environment=LISTEN_ADDR=:80
Environment=SINK_PATH=/var/log/fake-bank/creds.log
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now fake-bank'

echo ">> dns-resolver: protective resolver"
incus exec dns-resolver -- mkdir -p /etc/dns-resolver
incus file push bin/dns-resolver dns-resolver/usr/local/bin/dns-resolver
incus file push threats/dns-hijack/resolver/feed.json dns-resolver/etc/dns-resolver/feed.json
incus exec dns-resolver -- bash -c 'cat > /etc/systemd/system/dns-resolver.service <<EOF
[Unit]
Description=protective scoring resolver
After=network.target
[Service]
ExecStart=/usr/local/bin/dns-resolver
Environment=SERVICE_ID=eu-pt.aveiro-dc1.rack5.dns-resolver.dns-resolver.1
Environment=DNS_ADDR=:53
Environment=LISTEN_ADDR=:5005
Environment=SELF_URL=http://'"$RESOLVER_IP"':5005
Environment=REGISTRY_URL=http://10.255.255.11:30050
Environment=FEED_PATH=/etc/dns-resolver/feed.json
Environment=EVENTS_LOG=/var/log/dns-resolver/events.log
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now dns-resolver'

echo ">> dns-victim: lookup tools"
incus exec dns-victim -- bash -c 'apt-get update -qq && apt-get install -y -qq dnsutils curl'

echo "done. rogue=$ROGUE_IP bank=$BANK_IP resolver=$RESOLVER_IP victim=$VICTIM_IP"
