// signs a service into the registry and keeps it alive with heartbeats
package regclient

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

type Client struct {
	registryURL string
	id          string
	name        string
	selfURL     string
	http        *http.Client
}

func New(registryURL, id, name, selfURL string) *Client {
	return &Client{
		registryURL: registryURL,
		id:          id,
		name:        name,
		selfURL:     selfURL,
		http:        &http.Client{Timeout: 3 * time.Second},
	}
}

type payload struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	URL  string `json:"url"`
}

func (c *Client) Register(ctx context.Context) error {
	return c.post(ctx, http.MethodPost, "/register")
}

func (c *Client) Unregister(ctx context.Context) error {
	return c.post(ctx, http.MethodDelete, "/unregister")
}

func (c *Client) post(ctx context.Context, method, path string) error {
	body, _ := json.Marshal(payload{ID: c.id, Name: c.name, URL: c.selfURL})
	req, err := http.NewRequestWithContext(ctx, method, c.registryURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("registry %s %s: status %d", method, path, resp.StatusCode)
	}
	return nil
}

// re-register on each tick; the registry drops instances that go quiet
func (c *Client) StartHeartbeat(ctx context.Context, interval time.Duration) {
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				if err := c.Register(ctx); err != nil {
					slog.Warn("heartbeat failed", "err", err)
				}
			}
		}
	}()
}
