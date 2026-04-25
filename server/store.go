package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

type NotificationRecord struct {
	UserID    string    `json:"user_id"`
	Event     string    `json:"event"`
	SessionID string    `json:"session_id"`
	CWD       string    `json:"cwd"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Timestamp time.Time `json:"timestamp"`
}

// Store persists device tokens and notification history to JSON files on disk.
// Good enough for a single-user MVP; swap for SQLite when it hurts.
type Store struct {
	dir     string
	mu      sync.Mutex
	devices map[string]map[string]struct{} // user_id -> set of device tokens
}

func NewStore(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	s := &Store{dir: dir, devices: map[string]map[string]struct{}{}}
	if err := s.loadDevices(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) devicesFile() string { return filepath.Join(s.dir, "devices.json") }

func (s *Store) historyFile(user string) string {
	return filepath.Join(s.dir, fmt.Sprintf("history-%s.jsonl", sanitize(user)))
}

func sanitize(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '-', c == '_':
			out = append(out, c)
		default:
			out = append(out, '_')
		}
	}
	if len(out) == 0 {
		return "default"
	}
	return string(out)
}

func (s *Store) loadDevices() error {
	data, err := os.ReadFile(s.devicesFile())
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var raw map[string][]string
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	for u, toks := range raw {
		set := map[string]struct{}{}
		for _, t := range toks {
			set[t] = struct{}{}
		}
		s.devices[u] = set
	}
	return nil
}

func (s *Store) saveDevicesLocked() error {
	raw := map[string][]string{}
	for u, set := range s.devices {
		for t := range set {
			raw[u] = append(raw[u], t)
		}
	}
	data, err := json.MarshalIndent(raw, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.devicesFile() + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, s.devicesFile())
}

func (s *Store) AddDevice(userID, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.devices[userID]; !ok {
		s.devices[userID] = map[string]struct{}{}
	}
	s.devices[userID][token] = struct{}{}
	return s.saveDevicesLocked()
}

func (s *Store) RemoveDevice(userID, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if set, ok := s.devices[userID]; ok {
		delete(set, token)
	}
	return s.saveDevicesLocked()
}

func (s *Store) Devices(userID string) ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	set := s.devices[userID]
	out := make([]string, 0, len(set))
	for t := range set {
		out = append(out, t)
	}
	sort.Strings(out)
	return out, nil
}

func (s *Store) AppendHistory(rec NotificationRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	f, err := os.OpenFile(s.historyFile(rec.UserID), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	return json.NewEncoder(f).Encode(rec)
}

func (s *Store) History(userID string, limit int) ([]NotificationRecord, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	f, err := os.Open(s.historyFile(userID))
	if err != nil {
		if os.IsNotExist(err) {
			return []NotificationRecord{}, nil
		}
		return nil, err
	}
	defer f.Close()
	dec := json.NewDecoder(f)
	var all []NotificationRecord
	for dec.More() {
		var rec NotificationRecord
		if err := dec.Decode(&rec); err != nil {
			break
		}
		all = append(all, rec)
	}
	sort.Slice(all, func(i, j int) bool { return all[i].Timestamp.After(all[j].Timestamp) })
	if limit > 0 && len(all) > limit {
		all = all[:limit]
	}
	return all, nil
}
