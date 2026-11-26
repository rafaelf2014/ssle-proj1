package main

import (
	"math"
	"testing"
)

func TestComputeStats(t *testing.T) {
	got := computeStats([]reading{{20}, {22}, {24}})
	if got.Count != 3 || got.Min != 20 || got.Max != 24 {
		t.Fatalf("unexpected stats: %+v", got)
	}
	if math.Abs(got.Average-22) > 1e-9 {
		t.Fatalf("want average 22, got %v", got.Average)
	}
}

func TestComputeStatsEmpty(t *testing.T) {
	if got := computeStats(nil); got.Count != 0 {
		t.Fatalf("want zero stats, got %+v", got)
	}
}
