package naming

import "testing"

func TestParseValid(t *testing.T) {
	in := "eu-pt.aveiro-dc1.rack3.k3s-node1.analytics.7"
	id, err := Parse(in)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id.Service != "analytics" || id.Instance != "7" || id.Node != "k3s-node1" {
		t.Fatalf("wrong parse: %+v", id)
	}
	if id.String() != in {
		t.Fatalf("round-trip mismatch: %q != %q", id.String(), in)
	}
}

func TestParseRejectsBadInput(t *testing.T) {
	for _, in := range []string{
		"too.few.parts",
		"a.b.c.d.e.f.g",
		"a.b..d.e.f",
		"",
	} {
		if _, err := Parse(in); err == nil {
			t.Errorf("expected error for %q, got none", in)
		}
	}
}

func TestLocation(t *testing.T) {
	id, _ := Parse("eu-pt.aveiro-dc1.rack3.k3s-node1.analytics.7")
	loc := id.Location()
	if loc["rack"] != "rack3" || loc["region"] != "eu-pt" {
		t.Fatalf("wrong location: %v", loc)
	}
}
