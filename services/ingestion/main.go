package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"time"

	"github.com/ua-ssle/proj1/services/pkg/server"
)

var httpClient = &http.Client{Timeout: 3 * time.Second}

func main() {
	id := server.ResolveID("ingestion")
	addr := server.Env("LISTEN_ADDR", ":5001")
	selfURL := server.Env("SELF_URL", "http://127.0.0.1:5001")
	registryURL := server.Env("REGISTRY_URL", "http://127.0.0.1:5050")
	storageURL := server.Env("STORAGE_URL", "http://127.0.0.1:5002")

	svc, err := server.New(id, addr, selfURL)
	if err != nil {
		panic(err)
	}
	svc.EnableRegistry(registryURL)
	svc.Handle("POST /ingest", ingestHandler(storageURL))

	if err := svc.Run(context.Background()); err != nil {
		panic(err)
	}
}

type reading struct {
	DeviceID    string  `json:"device_id"`
	Temperature float64 `json:"temperature"`
}

// check the reading, then hand it off to storage
func ingestHandler(storageURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var rd reading
		if err := json.NewDecoder(r.Body).Decode(&rd); err != nil || rd.DeviceID == "" {
			http.Error(w, "bad body", http.StatusBadRequest)
			return
		}
		body, _ := json.Marshal(rd)
		resp, err := httpClient.Post(storageURL+"/store", "application/json", bytes.NewReader(body))
		if err != nil {
			http.Error(w, "storage unreachable", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		io.Copy(io.Discard, resp.Body)
		if resp.StatusCode >= 300 {
			http.Error(w, "storage rejected reading", http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusAccepted)
	}
}
