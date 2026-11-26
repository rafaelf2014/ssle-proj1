package main

import "testing"

func TestScoreHijackedBankScoresSinkhole(t *testing.T) {
	// what the rogue path looks like: a fresh phishing domain on a bad IP
	a := Attributes{Category: "phishing", Reports: 15, DomainAgeDays: 5, DNSSEC: false, IPReputation: "bad"}
	b := Score(a)
	if b.Total != 95 {
		t.Fatalf("want total 95, got %d (%+v)", b.Total, b)
	}
	if got := Decide(b.Total); got != ActionSinkhole {
		t.Fatalf("want sinkhole, got %s", got)
	}
}

func TestScoreBenignResolves(t *testing.T) {
	a := Attributes{Category: "benign", Reports: 0, DomainAgeDays: 4000, DNSSEC: true, IPReputation: "clean"}
	b := Score(a)
	if b.Total != 0 {
		t.Fatalf("want total 0, got %d", b.Total)
	}
	if got := Decide(b.Total); got != ActionResolve {
		t.Fatalf("want resolve, got %s", got)
	}
}

func TestScoreUnknownStaysLow(t *testing.T) {
	// a domain we have nothing on should not be punished into a block
	a := Attributes{Category: "unknown", Reports: 0, DomainAgeDays: -1, DNSSEC: true, IPReputation: "unknown"}
	if got := Decide(Score(a).Total); got != ActionResolve {
		t.Fatalf("unknown domain should resolve, got %s", got)
	}
}

func TestDecideThresholds(t *testing.T) {
	cases := map[int]Action{0: ActionResolve, 24: ActionResolve, 25: ActionLog, 49: ActionLog, 50: ActionWarn, 74: ActionWarn, 75: ActionSinkhole, 100: ActionSinkhole}
	for score, want := range cases {
		if got := Decide(score); got != want {
			t.Errorf("score %d: want %s, got %s", score, want, got)
		}
	}
}

func TestScoreNeverExceeds100(t *testing.T) {
	a := Attributes{Category: "malware", Reports: 9999, DomainAgeDays: 0, DNSSEC: false, IPReputation: "bad"}
	if b := Score(a); b.Total > 100 {
		t.Fatalf("score exceeded 100: %d", b.Total)
	}
}
