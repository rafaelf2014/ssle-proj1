package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"time"

	"github.com/ua-ssle/proj1/services/pkg/server"
)

var httpClient = &http.Client{Timeout: 3 * time.Second}

func main() {
	id := server.ResolveID("analytics")
	addr := server.Env("LISTEN_ADDR", ":5003")
	selfURL := server.Env("SELF_URL", "http://127.0.0.1:5003")
	registryURL := server.Env("REGISTRY_URL", "http://127.0.0.1:5050")
	storageURL := server.Env("STORAGE_URL", "http://127.0.0.1:5002")

	svc, err := server.New(id, addr, selfURL)
	if err != nil {
		panic(err)
	}
	svc.EnableRegistry(registryURL)
	svc.Handle("GET /average", averageHandler(storageURL))

	if err := svc.Run(context.Background()); err != nil {
		panic(err)
	}
}

type reading struct {
	Temperature float64 `json:"temperature"`
}

type Stats struct {
	Count   int     `json:"count"`
	Average float64 `json:"average"`
	Min     float64 `json:"min"`
	Max     float64 `json:"max"`
}

func averageHandler(storageURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := storageURL + "/temperatures"
		if dev := r.URL.Query().Get("device_id"); dev != "" {
			u += "?device_id=" + url.QueryEscape(dev)
		}
		resp, err := httpClient.Get(u)
		if err != nil {
			http.Error(w, "storage unreachable", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		var readings []reading
		if err := json.NewDecoder(resp.Body).Decode(&readings); err != nil {
			http.Error(w, "bad storage response", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(computeStats(readings))
	}
}

func computeStats(readings []reading) Stats {
	if len(readings) == 0 {
		return Stats{}
	}
	s := Stats{Count: len(readings), Min: readings[0].Temperature, Max: readings[0].Temperature}
	var sum float64
	for _, r := range readings {
		sum += r.Temperature
		s.Min = min(s.Min, r.Temperature)
		s.Max = max(s.Max, r.Temperature)
	}
	s.Average = sum / float64(len(readings))
	return s
}
