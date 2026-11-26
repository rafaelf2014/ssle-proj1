# Lab inventory

Isolated Incus bridge `incus-default`, 10.255.255.0/24, NAT on (package pulls only).
Static IPs are pinned via `incus config device override <c> eth0 ipv4.address=<ip>`.

| Container | IP | Role | Profile |
|---|---|---|---|
| (gateway) | 10.255.255.1 | bridge gateway | - |
| docker | 10.255.255.10 | image build box + local registry (:5000) | k3s |
| k3s-master | 10.255.255.11 | k3s server / control-plane | k3s |
| k3s-node1 | 10.255.255.12 | k3s agent | k3s |

Reserved for later phases (.20+):

| Container | IP | Role |
|---|---|---|
| prometheus-container | 10.255.255.20 | metrics + alerts |
| wazuh-container | 10.255.255.21 | SIEM |
| apache-victim | 10.255.255.22 | DDoS / shellshock target |
| dns-rogue | 10.255.255.23 | rogue dnsmasq |
| fake-bank | 10.255.255.24 | fictional login clone |
| dns-resolver | 10.255.255.25 | protective scoring resolver |
| metasploit-c2 | 10.255.255.26 | C2 operator (kali) |
| c2-victim | 10.255.255.27 | runs lab payload |
| load-client-a | 10.255.255.28 | ApacheBench source |
| load-client-b | 10.255.255.29 | ApacheBench source |

## Image registry
Local registry on the docker box at `10.255.255.10:5000` (plain HTTP, lab only).
Both k3s nodes trust it via `/etc/rancher/k3s/registries.yaml`.
Images tagged `10.255.255.10:5000/ssle-<svc>:dev`.
