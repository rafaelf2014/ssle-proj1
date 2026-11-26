// shared bootstrap for every service: metrics, health, logging, registration, shutdown
package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/ua-ssle/proj1/services/pkg/health"
	"github.com/ua-ssle/proj1/services/pkg/metrics"
	"github.com/ua-ssle/proj1/services/pkg/naming"
	"github.com/ua-ssle/proj1/services/pkg/regclient"
)

type Service struct {
	RawID   string
	ID      naming.ID
	Name    string
	Addr    string
	SelfURL string

	mux     *http.ServeMux
	metrics *metrics.Metrics
	reg     *regclient.Client
	log     *slog.Logger
}

// parse the id and wire up /healthz and /metrics
func New(rawID, addr, selfURL string) (*Service, error) {
	id, err := naming.Parse(rawID)
	if err != nil {
		return nil, err
	}
	m := metrics.New(rawID)
	s := &Service{
		RawID:   rawID,
		ID:      id,
		Name:    id.Service,
		Addr:    addr,
		SelfURL: selfURL,
		mux:     http.NewServeMux(),
		metrics: m,
		log:     slog.With("service", id.Service, "id", rawID),
	}
	s.mux.Handle("GET /healthz", health.Handler())
	s.mux.Handle("GET /metrics", m.Handler())
	return s, nil
}

func (s *Service) Handle(pattern string, h http.HandlerFunc) {
	s.mux.Handle(pattern, h)
}

func (s *Service) Logger() *slog.Logger { return s.log }

// Metrics exposes the metrics handle so a service can register extra collectors
func (s *Service) Metrics() *metrics.Metrics { return s.metrics }

// sign in to the registry on start, sign out on shutdown
func (s *Service) EnableRegistry(registryURL string) {
	s.reg = regclient.New(registryURL, s.RawID, s.Name, s.SelfURL)
}

// serve until we catch a signal or ctx gets cancelled
func (s *Service) Run(ctx context.Context) error {
	ctx, stop := signal.NotifyContext(ctx, syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	srv := &http.Server{Addr: s.Addr, Handler: s.metrics.Middleware(s.mux)}

	if s.reg != nil {
		if err := s.reg.Register(ctx); err != nil {
			s.log.Warn("initial registration failed", "err", err)
		}
		s.reg.StartHeartbeat(ctx, 10*time.Second)
	}

	errc := make(chan error, 1)
	go func() {
		s.log.Info("listening", "addr", s.Addr)
		errc <- srv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		s.log.Info("shutting down")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if s.reg != nil {
		if err := s.reg.Unregister(shutdownCtx); err != nil {
			s.log.Warn("unregister failed", "err", err)
		}
	}
	return srv.Shutdown(shutdownCtx)
}

// value of key, or def if unset
func Env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return def
}

// build this instance id, use SERVICE_ID if set, else assemble it from the
// prefix + node + service + pod name
func ResolveID(service string) string {
	if v := os.Getenv("SERVICE_ID"); v != "" {
		return v
	}
	host, _ := os.Hostname()
	prefix := Env("SERVICE_ID_PREFIX", "eu-pt.aveiro-dc1.rack1")
	node := firstNonEmpty(os.Getenv("NODE_NAME"), host, "local")
	instance := firstNonEmpty(os.Getenv("POD_NAME"), host, "1")
	return strings.Join([]string{prefix, node, service, instance}, ".")
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
