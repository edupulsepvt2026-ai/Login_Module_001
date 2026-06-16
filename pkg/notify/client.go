package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
}

func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (c *Client) SendSMS(ctx context.Context, phone, message string) error {
	return c.send(ctx, map[string]any{
		"kind":    "sms",
		"to":      phone,
		"message": message,
	})
}

func (c *Client) SendEmail(ctx context.Context, to, subject, body string) error {
	return c.send(ctx, map[string]any{
		"kind":    "email",
		"to":      to,
		"subject": subject,
		"body":    body,
	})
}

func (c *Client) send(ctx context.Context, payload map[string]any) error {
	b, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.baseURL+"/api/v1/notify", bytes.NewReader(b))
	if err != nil {
		return fmt.Errorf("notify: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("notify: request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		return fmt.Errorf("notify: omnichannel returned %d", resp.StatusCode)
	}
	return nil
}
