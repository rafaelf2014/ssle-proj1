package main

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"math/rand"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/ua-ssle/proj1/services/pkg/server"
)

var httpClient = &http.Client{Timeout: 3 * time.Second}

func main() {
	id := server.ResolveID("sensor")
	addr := server.Env("LISTEN_ADDR", ":5004")
	selfURL := server.Env("SELF_URL", "http://127.0.0.1:5004")
	registryURL := server.Env("REGISTRY_URL", "http://127.0.0.1:5050")
	ingestionURL := server.Env("INGESTION_URL", "http://127.0.0.1:5001")
	deviceID := server.Env("DEVICE_ID", "sensor-1")

	svc, err := server.New(id, addr, selfURL)
	if err != nil {
		panic(err)
	}
	svc.EnableRegistry(registryURL)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go loop(ctx, ingestionURL, deviceID)

	if err := svc.Run(ctx); err != nil {
		panic(err)
	}
}

type reading struct {
	DeviceID    string  `json:"device_id"`
	Temperature float64 `json:"temperature"`
}

// fire off a reading every 5s until ctx is cancelled
func loop(ctx context.Context, ingestionURL, deviceID string) {
	t := time.NewTicker(5 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			send(ingestionURL, reading{DeviceID: deviceID, Temperature: sample()})
		}
	}
}

// room temp with a little jitter
func sample() float64 {
	return 20 + rand.Float64()*5
}

func send(ingestionURL string, rd reading) {
	body, _ := json.Marshal(rd)
	resp, err := httpClient.Post(ingestionURL+"/ingest", "application/json", bytes.NewReader(body))
	if err != nil {
		slog.Warn("send failed", "err", err)
		return
	}
	resp.Body.Close()
}
