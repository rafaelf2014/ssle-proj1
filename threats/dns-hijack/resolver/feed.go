package main

import (
	"encoding/json"
	"os"
	"strings"
)

type Feed struct {
	SinkholeIP string                `json:"sinkhole_ip"`
	Upstreams  []string              `json:"upstreams"`
	Domains    map[string]Attributes `json:"domains"`
}

func LoadFeed(path string) (*Feed, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var f Feed
	if err := json.Unmarshal(raw, &f); err != nil {
		return nil, err
	}
	return &f, nil
}

// look up a domain; anything not in the feed is "unknown" and scores low
func (f *Feed) Lookup(domain string) (Attributes, bool) {
	if a, ok := f.Domains[strings.ToLower(domain)]; ok {
		return a, true
	}
	return Attributes{Category: "unknown", DomainAgeDays: -1, DNSSEC: true, IPReputation: "unknown"}, false
}
