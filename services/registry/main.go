package main

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/ua-ssle/proj1/services/pkg/server"
)

var store = NewStore(30 * time.Second)

func main() {
	id := server.ResolveID("registry")
	addr := server.Env("LISTEN_ADDR", ":5050")
	selfURL := server.Env("SELF_URL", "http://127.0.0.1:5050")

	svc, err := server.New(id, addr, selfURL)
	if err != nil {
		panic(err)
	}

	stop := make(chan struct{})
	defer close(stop)
	store.startReaper(stop)

	svc.Handle("POST /register", handleRegister)
	svc.Handle("DELETE /unregister", handleUnregister)
	svc.Handle("GET /services", handleListAll)
	svc.Handle("GET /services/{name}", handleListByName)

	if err := svc.Run(context.Background()); err != nil {
		panic(err)
	}
}

type regBody struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	URL  string `json:"url"`
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var b regBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if err := store.Upsert(b.ID, b.Name, b.URL); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func handleUnregister(w http.ResponseWriter, r *http.Request) {
	var b regBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	store.Remove(b.ID)
	w.WriteHeader(http.StatusNoContent)
}

func handleListAll(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, store.List())
}

func handleListByName(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, store.ByName(r.PathValue("name")))
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}
