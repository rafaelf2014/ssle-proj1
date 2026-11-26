package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestIngestForwards(t *testing.T) {
	var got string
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		got = string(b)
		w.WriteHeader(http.StatusCreated)
	}))
	defer storage.Close()

	h := ingestHandler(storage.URL)
	req := httptest.NewRequest(http.MethodPost, "/ingest", strings.NewReader(`{"device_id":"dev-1","temperature":21.5}`))
	rec := httptest.NewRecorder()
	h(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("want 202, got %d", rec.Code)
	}
	if !strings.Contains(got, `"device_id":"dev-1"`) {
		t.Fatalf("storage did not receive reading, got %q", got)
	}
}

func TestIngestRejectsBadBody(t *testing.T) {
	h := ingestHandler("http://unused")
	req := httptest.NewRequest(http.MethodPost, "/ingest", strings.NewReader(`{}`))
	rec := httptest.NewRecorder()
	h(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}
