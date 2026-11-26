// naming deals with the hierarchical service id (region.dc.rack.node.service.instance)
package naming

import (
	"fmt"
	"strings"
)

type ID struct {
	Region   string
	DC       string
	Rack     string
	Node     string
	Service  string
	Instance string
}

const partCount = 6

func Parse(s string) (ID, error) {
	parts := strings.Split(s, ".")
	if len(parts) != partCount {
		return ID{}, fmt.Errorf("naming: want %d parts, got %d in %q", partCount, len(parts), s)
	}
	for i, p := range parts {
		if strings.TrimSpace(p) == "" {
			return ID{}, fmt.Errorf("naming: empty segment at position %d in %q", i+1, s)
		}
	}
	return ID{parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]}, nil
}

func (id ID) String() string {
	return strings.Join([]string{id.Region, id.DC, id.Rack, id.Node, id.Service, id.Instance}, ".")
}

// just the where-it-runs bits, handy to tack onto an event
func (id ID) Location() map[string]string {
	return map[string]string{
		"region": id.Region,
		"dc":     id.DC,
		"rack":   id.Rack,
		"node":   id.Node,
	}
}
