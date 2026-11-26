package main

import "testing"

func TestStoreAndQuery(t *testing.T) {
	db, err := OpenDB(":memory:")
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	for _, temp := range []float64{20.0, 21.5, 19.0} {
		if err := db.Store("dev-1", temp); err != nil {
			t.Fatalf("store: %v", err)
		}
	}
	_ = db.Store("dev-2", 100.0)

	all, err := db.Query("", 0)
	if err != nil {
		t.Fatalf("query: %v", err)
	}
	if len(all) != 4 {
		t.Fatalf("want 4 rows, got %d", len(all))
	}

	dev1, _ := db.Query("dev-1", 0)
	if len(dev1) != 3 {
		t.Fatalf("want 3 dev-1 rows, got %d", len(dev1))
	}

	limited, _ := db.Query("", 2)
	if len(limited) != 2 {
		t.Fatalf("want 2 rows with limit, got %d", len(limited))
	}
}
