package main

import (
	"context"
	"log/slog"
	"net"
	"os"
	"strings"
	"time"

	"github.com/miekg/dns"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/ua-ssle/proj1/services/pkg/server"
)

var (
	feed      *Feed
	eventsLog *slog.Logger
	decisions *prometheus.CounterVec
)

func main() {
	id := server.ResolveID("dns-resolver")
	httpAddr := server.Env("LISTEN_ADDR", ":5005")
	selfURL := server.Env("SELF_URL", "http://10.255.255.25:5005")
	registryURL := server.Env("REGISTRY_URL", "http://10.255.255.11:30050")
	dnsAddr := server.Env("DNS_ADDR", ":53")
	feedPath := server.Env("FEED_PATH", "/etc/dns-resolver/feed.json")
	eventsPath := server.Env("EVENTS_LOG", "/var/log/dns-resolver/events.log")

	var err error
	feed, err = LoadFeed(feedPath)
	if err != nil {
		panic(err)
	}
	eventsLog = newEventsLogger(eventsPath, id)

	svc, err := server.New(id, httpAddr, selfURL)
	if err != nil {
		panic(err)
	}
	svc.EnableRegistry(registryURL)

	decisions = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name:        "dns_decisions_total",
		Help:        "DNS queries by policy action.",
		ConstLabels: prometheus.Labels{"service_id": id},
	}, []string{"action"})
	svc.Metrics().Registry().MustRegister(decisions)

	dns.HandleFunc(".", handle)
	for _, net := range []string{"udp", "tcp"} {
		s := &dns.Server{Addr: dnsAddr, Net: net}
		go func() {
			if err := s.ListenAndServe(); err != nil {
				slog.Error("dns server stopped", "net", net, "err", err)
			}
		}()
	}
	slog.Info("protective resolver up", "dns", dnsAddr, "http", httpAddr, "id", id)

	if err := svc.Run(context.Background()); err != nil {
		panic(err)
	}
}

func handle(w dns.ResponseWriter, r *dns.Msg) {
	q := r.Question[0]
	name := strings.TrimSuffix(strings.ToLower(q.Name), ".")

	attrs, known := feed.Lookup(name)
	bd := Score(attrs)
	action := Decide(bd.Total)
	decisions.WithLabelValues(string(action)).Inc()

	client, _, _ := net.SplitHostPort(w.RemoteAddr().String())
	logEvent(client, name, dns.TypeToString[q.Qtype], bd, action, known)

	if action == ActionSinkhole {
		w.WriteMsg(sinkholeReply(r, q))
		return
	}
	w.WriteMsg(forward(r))
}

// blocked domains answer with the sinkhole ip; non-A queries come back empty
func sinkholeReply(r *dns.Msg, q dns.Question) *dns.Msg {
	m := new(dns.Msg)
	m.SetReply(r)
	if q.Qtype == dns.TypeA {
		rr, err := dns.NewRR(q.Name + " 60 IN A " + feed.SinkholeIP)
		if err == nil {
			m.Answer = append(m.Answer, rr)
		}
	}
	return m
}

func forward(r *dns.Msg) *dns.Msg {
	c := &dns.Client{Timeout: 3 * time.Second}
	for _, up := range feed.Upstreams {
		if resp, _, err := c.Exchange(r, up); err == nil {
			return resp
		}
	}
	m := new(dns.Msg)
	m.SetRcode(r, dns.RcodeServerFailure)
	return m
}

func logEvent(client, qname, qtype string, bd Breakdown, action Action, known bool) {
	level := slog.LevelInfo
	switch action {
	case ActionWarn:
		level = slog.LevelWarn
	case ActionSinkhole:
		level = slog.LevelError
	}
	// key is "decision" not "action": wazuh not like "action"
	eventsLog.Log(context.Background(), level, "dns_decision",
		"client", client, "qname", qname, "qtype", qtype,
		"score", bd.Total, "decision", string(action), "in_feed", known,
		"breakdown", bd,
	)
}

// one json object per line so wazuh can read it
func newEventsLogger(path, id string) *slog.Logger {
	_ = os.MkdirAll(dirOf(path), 0o755)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		slog.Warn("cannot open events log, using stdout", "err", err)
		return slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service_id", id)
	}
	return slog.New(slog.NewJSONHandler(f, nil)).With("service_id", id)
}

func dirOf(path string) string {
	if i := strings.LastIndex(path, "/"); i >= 0 {
		return path[:i]
	}
	return "."
}
