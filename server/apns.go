package main

import (
	"fmt"
	"strings"

	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/payload"
	"github.com/sideshow/apns2/token"
)

type APNSConfig struct {
	KeyPath    string
	KeyID      string
	TeamID     string
	BundleID   string
	Production bool
}

type APNSClient struct {
	cli      *apns2.Client
	bundleID string
}

func NewAPNSClient(cfg APNSConfig) (*APNSClient, error) {
	authKey, err := token.AuthKeyFromFile(cfg.KeyPath)
	if err != nil {
		return nil, fmt.Errorf("load key: %w", err)
	}
	tok := &token.Token{
		AuthKey: authKey,
		KeyID:   cfg.KeyID,
		TeamID:  cfg.TeamID,
	}
	cli := apns2.NewTokenClient(tok)
	if cfg.Production {
		cli = cli.Production()
	} else {
		cli = cli.Development()
	}
	return &APNSClient{cli: cli, bundleID: cfg.BundleID}, nil
}

// Push sends a single alert notification to the given device token.
func (a *APNSClient) Push(deviceToken, title, body string, custom map[string]any) error {
	thread := stringOr(custom["session"], "claude-notify")
	pl := payload.NewPayload().
		AlertTitle(title).
		AlertBody(body).
		Sound("default").
		Badge(1).
		MutableContent().
		ThreadID(thread)
	for k, v := range custom {
		pl = pl.Custom(k, v)
	}
	n := &apns2.Notification{
		DeviceToken: deviceToken,
		Topic:       a.bundleID,
		Payload:     pl,
	}
	res, err := a.cli.Push(n)
	if err != nil {
		return err
	}
	if !res.Sent() {
		return fmt.Errorf("apns %d: %s", res.StatusCode, res.Reason)
	}
	return nil
}

func stringOr(v any, fallback string) string {
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return fallback
}

// IsUnregisteredErr reports whether the error is APNs saying the device token
// is invalid and we should drop it.
func IsUnregisteredErr(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "Unregistered") ||
		strings.Contains(msg, "BadDeviceToken") ||
		strings.Contains(msg, "DeviceTokenNotForTopic")
}
