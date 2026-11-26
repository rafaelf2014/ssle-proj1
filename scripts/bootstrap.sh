#!/usr/bin/env bash
# host setup for a fresh debian vm: incus, go, the network, k3s profile, sysctls
# safe to re-run
set -euo pipefail

echo ">> packages"
sudo apt-get update -qq
sudo apt-get install -y -qq incus git curl make ca-certificates

echo ">> go toolchain"
if [ ! -x /usr/local/go/bin/go ]; then
	GOVER=$(curl -s https://go.dev/VERSION?m=text | head -1)
	curl -fsSLo /tmp/go.tgz "https://go.dev/dl/${GOVER}.linux-amd64.tar.gz"
	sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
	echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' | sudo tee /etc/profile.d/go.sh >/dev/null
fi

echo ">> incus group + init"
sudo adduser "$USER" incus-admin >/dev/null 2>&1 || true
sudo systemctl enable --now incus
sudo incus admin init --minimal 2>/dev/null || true

echo ">> isolated network incus-default"
if ! sudo incus network show incus-default >/dev/null 2>&1; then
	sudo incus profile device remove default eth0 2>/dev/null || true
	sudo incus network delete incusbr0 2>/dev/null || true
	sudo incus network create incus-default ipv4.address=10.255.255.1/24 ipv4.nat=true ipv6.address=none
	sudo incus profile device add default eth0 nic network=incus-default name=eth0
fi

echo ">> k3s profile"
if ! sudo incus profile show k3s >/dev/null 2>&1; then
	sudo incus profile create k3s
	sudo incus profile set k3s security.privileged=true security.nesting=true \
		linux.kernel_modules=ip_tables,ip6_tables,nf_nat,overlay,br_netfilter
	printf 'lxc.apparmor.profile=unconfined\nlxc.cgroup.devices.allow=a *:* rwm\nlxc.cap.drop=' \
		| sudo incus profile set k3s raw.lxc -
	sudo incus profile device add k3s kmsg unix-char source=/dev/kmsg path=/dev/kmsg
	sudo incus profile device add k3s eth0 nic network=incus-default name=eth0
	sudo incus profile device add k3s root disk path=/ pool=default
fi

echo ">> host sysctls (k3s + opensearch)"
sudo tee /etc/sysctl.d/99-ssle-lab.conf >/dev/null <<EOF
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
vm.max_map_count=262144
EOF
sudo sysctl --system >/dev/null

echo "bootstrap done. log out/in (or run: newgrp incus-admin) so incus works without sudo"
