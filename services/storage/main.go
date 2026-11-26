package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/ua-ssle/proj1/services/pkg/server"
)

var db *DB

func main() {
	id := server.ResolveID("storage")
	addr := server.Env("LISTEN_ADDR", ":5002")
	selfURL := server.Env("SELF_URL", "http://127.0.0.1:5002")
	registryURL := server.Env("REGISTRY_URL", "http://127.0.0.1:5050")
	dsn := server.Env("DB_PATH", "storage.db")

	var err error
	db, err = OpenDB(dsn)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	svc, err := server.New(id, addr, selfURL)
	if err != nil {
		panic(err)
	}
	svc.EnableRegistry(registryURL)
	svc.Handle("POST /store", handleStore)
	svc.Handle("GET /temperatures", handleQuery)

	if err := svc.Run(context.Background()); err != nil {
		panic(err)
	}
}

type storeBody struct {
	DeviceID    string  `json:"device_id"`
	Temperature float64 `json:"temperature"`
}

func handleStore(w http.ResponseWriter, r *http.Request) {
	var b storeBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil || b.DeviceID == "" {
		http.Error(w, "bad body", http.StatusBadRequest)
		return
	}
	if err := db.Store(b.DeviceID, b.Temperature); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	readings, err := db.Query(r.URL.Query().Get("device_id"), limit)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(readings)
}
