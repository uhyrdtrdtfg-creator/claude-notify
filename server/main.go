package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"
)

type Config struct {
	Addr         string
	DataDir      string
	SharedSecret string
	APNS         APNSConfig
}

type NotifyRequest struct {
	UserID    string `json:"user_id"`
	Event     string `json:"event"`
	SessionID string `json:"session_id"`
	CWD       string `json:"cwd"`
	Title     string `json:"title"`
	Body      string `json:"body"`
}

type RegisterRequest struct {
	UserID      string `json:"user_id"`
	DeviceToken string `json:"device_token"`
}

type Server struct {
	cfg   Config
	store *Store
	apns  *APNSClient
}

func loadConfig() (Config, error) {
	cfg := Config{
		Addr:         envOr("ADDR", ":8080"),
		DataDir:      envOr("DATA_DIR", "./data"),
		SharedSecret: os.Getenv("SHARED_SECRET"),
		APNS: APNSConfig{
			KeyPath:    os.Getenv("APNS_KEY_PATH"),
			KeyID:      os.Getenv("APNS_KEY_ID"),
			TeamID:     os.Getenv("APNS_TEAM_ID"),
			BundleID:   os.Getenv("APNS_BUNDLE_ID"),
			Production: strings.EqualFold(os.Getenv("APNS_ENV"), "production"),
		},
	}
	if cfg.SharedSecret == "" {
		return cfg, errors.New("SHARED_SECRET is required")
	}
	if cfg.APNS.KeyPath == "" || cfg.APNS.KeyID == "" || cfg.APNS.TeamID == "" || cfg.APNS.BundleID == "" {
		return cfg, errors.New("APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID are required")
	}
	return cfg, nil
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	store, err := NewStore(cfg.DataDir)
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	apns, err := NewAPNSClient(cfg.APNS)
	if err != nil {
		log.Fatalf("apns: %v", err)
	}
	s := &Server{cfg: cfg, store: store, apns: apns}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("POST /v1/register", s.handleRegister)
	mux.HandleFunc("POST /v1/notify", s.handleNotify)
	mux.HandleFunc("GET /v1/history", s.handleHistory)

	srv := &http.Server{
		Addr:         cfg.Addr,
		Handler:      logRequests(mux),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	go func() {
		log.Printf("claude-notify listening on %s", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}

func logRequests(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		h.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	_, _ = w.Write([]byte("ok"))
}

func (s *Server) requireSecret(r *http.Request) bool {
	const prefix = "Bearer "
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, prefix) {
		return false
	}
	return strings.TrimPrefix(auth, prefix) == s.cfg.SharedSecret
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if !s.requireSecret(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if req.UserID == "" || req.DeviceToken == "" {
		http.Error(w, "user_id and device_token required", http.StatusBadRequest)
		return
	}
	if err := s.store.AddDevice(req.UserID, req.DeviceToken); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	log.Printf("registered device for user=%s token=%s…", req.UserID, short(req.DeviceToken))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleNotify(w http.ResponseWriter, r *http.Request) {
	if !s.requireSecret(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req NotifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if req.UserID == "" {
		req.UserID = "default"
	}

	record := NotificationRecord{
		UserID:    req.UserID,
		Event:     req.Event,
		SessionID: req.SessionID,
		CWD:       req.CWD,
		Title:     req.Title,
		Body:      req.Body,
		Timestamp: time.Now().UTC(),
	}
	if err := s.store.AppendHistory(record); err != nil {
		log.Printf("history append: %v", err)
	}

	tokens, err := s.store.Devices(req.UserID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	var wg sync.WaitGroup
	for _, tok := range tokens {
		tok := tok
		wg.Add(1)
		go func() {
			defer wg.Done()
			err := s.apns.Push(tok, req.Title, truncateAPNS(req.Body, 200), map[string]any{
				"event":     req.Event,
				"session":   req.SessionID,
				"cwd":       req.CWD,
				"timestamp": record.Timestamp.Format(time.RFC3339),
			})
			if err != nil {
				log.Printf("apns push (%s): %v", short(tok), err)
				if IsUnregisteredErr(err) {
					_ = s.store.RemoveDevice(req.UserID, tok)
					log.Printf("pruned dead device token %s", short(tok))
				}
			}
		}()
	}
	wg.Wait()

	w.Header().Set("Content-Type", "application/json")
	_, _ = fmt.Fprintf(w, `{"delivered":%d}`, len(tokens))
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	if !s.requireSecret(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	userID := r.URL.Query().Get("user_id")
	if userID == "" {
		userID = "default"
	}
	items, err := s.store.History(userID, 200)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(items)
}

// truncateAPNS trims body for the push banner only; the full text is stored in history.
// APNs total payload limit is 4 KB; keep the banner short and readable.
func truncateAPNS(s string, n int) string {
	s = strings.TrimSpace(s)
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	return string(runes[:n-1]) + "…"
}

func short(s string) string {
	if len(s) <= 8 {
		return s
	}
	return s[:8]
}
