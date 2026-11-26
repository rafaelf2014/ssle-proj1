#!/usr/bin/env bash
# make the kali attacker (with metasploit) and the victim box. slow metasploit is big
set -euo pipefail

C2_IP=10.255.255.26
VICTIM_IP=10.255.255.27

launch() { # name ip image
	if incus info "$1" >/dev/null 2>&1; then echo "   $1 exists"; return; fi
	incus init "$3" "$1"
	incus config device override "$1" eth0 ipv4.address="$2"
	incus start "$1"
}

echo ">> launching"
launch metasploit-c2 "$C2_IP" images:kali
launch c2-victim "$VICTIM_IP" images:debian/trixie
sleep 6
for c in metasploit-c2 c2-victim; do
	incus exec "$c" -- bash -c 'rm -f /etc/resolv.conf; echo "nameserver 10.255.255.1" > /etc/resolv.conf'
done

echo ">> installing metasploit on the kali box (slow)"
incus exec metasploit-c2 -- bash -c 'apt-get update -qq && apt-get install -y metasploit-framework --fix-missing'

echo "done. now run enroll-agent.sh for the victim-side detection"
