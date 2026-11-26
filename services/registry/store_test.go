package main

import (
	"testing"
	"time"
)

const sampleID = "eu-pt.aveiro-dc1.rack3.k3s-node1.storage.1"

func TestUpsertAndList(t *testing.T) {
	s := NewStore(time.Minute)
	if err := s.Upsert(sampleID, "", "http://10.255.255.5:5002"); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	got := s.List()
	if len(got) != 1 || got[0].Name != "storage" || got[0].Location["rack"] != "rack3" {
		t.Fatalf("unexpected list: %+v", got)
	}
}

func TestUpsertRejectsBadID(t *testing.T) {
	s := NewStore(time.Minute)
	if err := s.Upsert("not-hierarchical", "", "http://x"); err == nil {
		t.Fatal("expected error for malformed ID")
	}
}

func TestRemove(t *testing.T) {
	s := NewStore(time.Minute)
	_ = s.Upsert(sampleID, "", "http://x")
	s.Remove(sampleID)
	if len(s.List()) != 0 {
		t.Fatal("expected empty after remove")
	}
}

func TestExpiry(t *testing.T) {
	s := NewStore(10 * time.Second)
	now := time.Now()
	s.now = func() time.Time { return now }
	_ = s.Upsert(sampleID, "", "http://x")

	now = now.Add(30 * time.Second) // pretend it's gone quiet past the ttl
	if len(s.List()) != 0 {
		t.Fatal("expected stale instance to be filtered")
	}
	s.reap()
	if len(s.items) != 0 {
		t.Fatal("expected stale instance to be reaped")
	}
}

func TestByName(t *testing.T) {
	s := NewStore(time.Minute)
	_ = s.Upsert("eu-pt.aveiro-dc1.rack3.k3s-node1.storage.1", "", "http://a")
	_ = s.Upsert("eu-pt.aveiro-dc1.rack3.k3s-node1.storage.2", "", "http://b")
	_ = s.Upsert("eu-pt.aveiro-dc1.rack3.k3s-node1.analytics.1", "", "http://c")
	if n := len(s.ByName("storage")); n != 2 {
		t.Fatalf("want 2 storage instances, got %d", n)
	}
}
