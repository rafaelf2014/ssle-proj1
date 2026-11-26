package main

import (
	"sort"
	"sync"
	"time"

	"github.com/ua-ssle/proj1/services/pkg/naming"
)

type Instance struct {
	ID       string            `json:"id"`
	Name     string            `json:"name"`
	URL      string            `json:"url"`
	Health   string            `json:"health"`
	LastSeen time.Time         `json:"last_seen"`
	Location map[string]string `json:"location"`
}

type Store struct {
	mu    sync.RWMutex
	ttl   time.Duration
	items map[string]Instance
	now   func() time.Time // injectable for tests
}

func NewStore(ttl time.Duration) *Store {
	return &Store{ttl: ttl, items: map[string]Instance{}, now: time.Now}
}

// add or refresh an instance; location comes from the id
func (s *Store) Upsert(id, name, url string) error {
	parsed, err := naming.Parse(id)
	if err != nil {
		return err
	}
	if name == "" {
		name = parsed.Service
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[id] = Instance{
		ID:       id,
		Name:     name,
		URL:      url,
		Health:   "up",
		LastSeen: s.now(),
		Location: parsed.Location(),
	}
	return nil
}

func (s *Store) Remove(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.items, id)
}

func (s *Store) List() []Instance {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Instance, 0, len(s.items))
	for _, in := range s.items {
		if s.fresh(in) {
			out = append(out, in)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

func (s *Store) ByName(name string) []Instance {
	out := make([]Instance, 0)
	for _, in := range s.List() {
		if in.Name == name {
			out = append(out, in)
		}
	}
	return out
}

func (s *Store) fresh(in Instance) bool {
	return s.now().Sub(in.LastSeen) <= s.ttl
}

// drop anything thats gone quiet past the ttl
func (s *Store) reap() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, in := range s.items {
		if !s.fresh(in) {
			delete(s.items, id)
		}
	}
}

func (s *Store) startReaper(stop <-chan struct{}) {
	go func() {
		t := time.NewTicker(s.ttl)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				s.reap()
			}
		}
	}()
}
