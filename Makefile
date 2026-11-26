# use go from PATH if it's there, else fall back to the default install path
GO := $(shell command -v go 2>/dev/null || echo /usr/local/go/bin/go)
SERVICES := registry ingestion sensor storage analytics

# container groups
SOA        := k3s-master k3s-node1 docker
MON        := prometheus-container
SIEM       := wazuh-container
MONITORING := $(MON) $(SIEM)
DNS        := dns-rogue fake-bank dns-resolver dns-victim
DDOS       := apache-victim load-client-a load-client-b
C2         := metasploit-c2 c2-victim
ALL        := $(SOA) $(MONITORING) $(DNS) $(DDOS) $(C2)

.PHONY: help build test vet smoke clean \
        bootstrap monitoring-setup soa-setup dns-setup ddos-setup c2-setup \
        monitoring-up monitoring-down soa-up dns-demo ddos-demo c2-demo \
        lab-down dashboards snapshot restore

help:
	@echo "From scratch: bootstrap -> monitoring-setup -> soa-setup -> dns-setup ddos-setup c2-setup  (see SETUP.md)"
	@echo "Build/test:   build  test  vet  smoke  clean"
	@echo "Run:          monitoring-up (leave running)  soa-up  dns-demo  ddos-demo  c2-demo"
	@echo "Lab:          monitoring-down  lab-down  dashboards  snapshot  restore"

# ---- Go ----
build:
	@mkdir -p bin
	@for s in $(SERVICES); do $(GO) build -o bin/$$s ./services/$$s; done

test:
	$(GO) test ./...

vet:
	$(GO) vet ./...

smoke:
	./scripts/smoke.sh

clean:
	rm -rf bin storage.db

# initial setup from clean VM
bootstrap:
	bash scripts/bootstrap.sh

monitoring-setup:
	bash deploy/prometheus/bringup.sh
	bash deploy/wazuh/bringup.sh

soa-setup:
	bash deploy/incus/bringup.sh && bash deploy/k8s/deploy.sh

dns-setup:
	bash threats/dns-hijack/bringup.sh && bash threats/dns-hijack/enroll-agent.sh

ddos-setup:
	bash threats/ddos/bringup.sh

c2-setup:
	bash threats/apt-c2/bringup.sh && bash threats/apt-c2/enroll-agent.sh

monitoring-up:
	incus start $(MONITORING) 2>/dev/null || true
	@echo "Prometheus: http://10.255.255.20:9090   Wazuh: https://10.255.255.21/"

monitoring-down:
	-incus stop $(MONITORING) 2>/dev/null

soa-up:
	incus start $(SOA) $(MON) 2>/dev/null || true
	@echo "waiting for k3s..."; sleep 20
	incus exec k3s-master -- kubectl -n ssle get pods -o wide

dns-demo:
	incus start $(SIEM) $(DNS) 2>/dev/null || true
	@sleep 10
	bash threats/dns-hijack/demo.sh

ddos-demo:
	incus start $(MONITORING) $(DDOS) 2>/dev/null || true
	@sleep 10
	@echo ">> heavy flood (cpu endpoint) -- watch response time + cpu climb:"
	bash threats/ddos/stress.sh
	@echo ">> graphs:    http://10.255.255.20:9090/graph  (response-time + cpu queries in DEMO-SCRIPT.md)"
	@echo ">> alerts:    http://10.255.255.20:9090/alerts"
	@echo ">> baseline (static page, optional): bash threats/ddos/attack.sh"
	@echo ">> proactive rate-limit response:   bash threats/ddos/response.sh"

c2-demo:
	incus start $(SIEM) $(C2) 2>/dev/null || true
	@sleep 10
	bash threats/apt-c2/attack.sh
	@echo ">> Wazuh (rule 100300 + firewall-drop): https://10.255.255.21/"

lab-down:
	-incus stop $(ALL) 2>/dev/null
	@echo "all lab containers stopped"

dashboards:
	@echo "Prometheus: http://10.255.255.20:9090        (alerts, targets, graphs)"
	@echo "Wazuh:      https://10.255.255.21/            (admin; password in .secrets/)"

#snapshot/restore
snapshot:
	@for c in $(ALL); do incus snapshot create $$c baseline 2>/dev/null && echo "snap $$c" || true; done

restore:
	@for c in $(ALL); do incus snapshot restore $$c baseline 2>/dev/null && echo "restored $$c" || true; done
