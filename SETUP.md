# Setup: building the lab from scratch

Everything here runs on one Debian 13 VM and stays on an isolated Incus bridge
(10.255.255.0/24). All the steps are `make` targets; this file is just the order
and what to expect.

## Prerequisites
- Debian 13 ("trixie") VM with **sudo**, outbound internet, 16 GiB RAM recommended and as many
  vCPUs as you can give it (8 works, more is better CPU).
- Run every `make` from the repo root.
- **Do not install Docker on the host**, it only goes inside the k3s-profile
  containers (Incus + Docker on the same host break each other).

## Build order (one time, kinda slow)

```
make bootstrap          # host: incus, go, make, isolated network, k3s profile, sysctls
make monitoring-setup   # prometheus box + wazuh box (manager/indexer/dashboard)
make soa-setup          # 2-node k3s + local registry, build+push images, deploy services
make dns-setup          # rogue dns, fake bank, scoring resolver, victim, + wazuh agent
make ddos-setup         # capped apache, 2 load clients, exporters, + wazuh agent
make c2-setup           # kali+metasploit box, victim, egress monitor, + wazuh agent
make snapshot           # optional: save a clean baseline of every box
```

## Running it

```
make monitoring-up      # start prometheus + wazuh, leave them running
make soa-up             # start the k3s SOA stack, show the pods
make dns-demo           # hijack -> protective resolver sinkholes it
make ddos-demo          # bounded load; then: bash threats/ddos/response.sh
make c2-demo            # reverse shell -> wazuh detects -> firewall-drop
```

Dashboards (also printed by `make dashboards`):
- Prometheus: http://10.255.255.20:9090
- Wazuh: https://10.255.255.21/ (`admin`, password in `.secrets/`)

## Lab control
```
make lab-down           # stop every container
make monitoring-down    # stop just prometheus + wazuh
make restore            # roll every box back to the snapshot baseline
```

On a low-vCPU host, run one scenario at a time (`make lab-down` between heavy runs).
`make help` lists everything.
