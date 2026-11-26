package main
// risk scoring for a domain, bounded penalties add up to 0-100, which picks an action

type Attributes struct {
	Category      string `json:"category"`        // phishing, malware, suspicious, benign, unknown
	Reports       int    `json:"reports"`         // abuse reports seen
	DomainAgeDays int    `json:"domain_age_days"` // how long the domain has existed
	DNSSEC        bool   `json:"dnssec"`          // is the domain DNSSEC-signed
	IPReputation  string `json:"ip_reputation"`   // bad, suspicious, clean, unknown
}

type Breakdown struct {
	Category     int `json:"category"`
	Reports      int `json:"reports"`
	DomainAge    int `json:"domain_age"`
	DNSSEC       int `json:"dnssec"`
	IPReputation int `json:"ip_reputation"`
	Total        int `json:"total"`
}

type Action string

const (
	ActionResolve  Action = "resolve"
	ActionLog      Action = "log"
	ActionWarn     Action = "warn"
	ActionSinkhole Action = "sinkhole"
)

func categoryScore(c string) int {
	switch c {
	case "phishing", "malware":
		return 30
	case "suspicious":
		return 15
	case "benign":
		return 0
	default: // unknown
		return 5
	}
}

func reportsScore(n int) int {
	if n < 0 {
		return 0
	}
	if n > 20 {
		return 20
	}
	return n
}

// newer domains are riskier: fresh registrations are a classic phishing tell
func ageScore(days int) int {
	switch {
	case days < 0: // unknown age
		return 5
	case days < 30:
		return 20
	case days < 90:
		return 10
	case days < 365:
		return 5
	default:
		return 0
	}
}

func dnssecScore(signed bool) int {
	if signed {
		return 0
	}
	return 10
}

func ipRepScore(r string) int {
	switch r {
	case "bad":
		return 20
	case "suspicious":
		return 10
	case "clean":
		return 0
	default: // unknown
		return 5
	}
}

func Score(a Attributes) Breakdown {
	b := Breakdown{
		Category:     categoryScore(a.Category),
		Reports:      reportsScore(a.Reports),
		DomainAge:    ageScore(a.DomainAgeDays),
		DNSSEC:       dnssecScore(a.DNSSEC),
		IPReputation: ipRepScore(a.IPReputation),
	}
	b.Total = b.Category + b.Reports + b.DomainAge + b.DNSSEC + b.IPReputation
	return b
}

func Decide(score int) Action {
	switch {
	case score >= 75:
		return ActionSinkhole
	case score >= 50:
		return ActionWarn
	case score >= 25:
		return ActionLog
	default:
		return ActionResolve
	}
}
