// Package triggers implements HTTP Webhook and fsnotify File Watcher event triggers.
package triggers

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/executor"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/logger"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

const (
	// SecretEnvVar carries the shared HMAC secret; it is never read from rules.json.
	SecretEnvVar = "EVENTOPS_WEBHOOK_SECRET"
	// maxBodyBytes is a hard cap on webhook payloads (1 MB).
	maxBodyBytes = 1 << 20
)

// WebhookServer manages HTTP listener for incoming webhook triggers.
//
// The shared HMAC secret is taken from the `secret` argument or, when empty,
// from the EVENTOPS_WEBHOOK_SECRET environment variable. Starting without a
// secret fails closed: Start returns an error instead of exposing an
// unauthenticated listener.
type WebhookServer struct {
	ruleEngine *ruleengine.RuleEngine
	host       string
	port       int
	secret     string
	server     *http.Server
}

// ResponsePayload defines JSON API response format.
type ResponsePayload struct {
	Status  string `json:"status"`
	Rule    string `json:"rule,omitempty"`
	Message string `json:"message"`
}

// NewWebhookServer constructs a WebhookServer instance.
func NewWebhookServer(re *ruleengine.RuleEngine, host string, port int, secret string) *WebhookServer {
	if secret == "" {
		secret = os.Getenv(SecretEnvVar)
	}
	return &WebhookServer{
		ruleEngine: re,
		host:       host,
		port:       port,
		secret:     secret,
	}
}

// Start launches the HTTP server in a background goroutine.
//
// It fails closed: without a configured HMAC secret it returns an error
// instead of binding a listener that anyone can trigger.
func (ws *WebhookServer) Start() error {
	if ws.secret == "" {
		return fmt.Errorf("%s is not set; refusing to start the webhook listener: set it to a strong shared secret (e.g. 'openssl rand -hex 32')", SecretEnvVar)
	}

	addr := fmt.Sprintf("%s:%d", ws.host, ws.port)
	mux := http.NewServeMux()
	mux.HandleFunc("/", ws.handleRequest)

	ws.server = &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("failed to bind webhook server on %s: %w", addr, err)
	}

	logger.Info("WebhookServer", "Webhook Server listening on http://%s", addr)

	go func() {
		if err := ws.server.Serve(listener); err != nil && err != http.ErrServerClosed {
			logger.Error("WebhookServer", "Server error: %v", err)
		}
	}()

	return nil
}

func (ws *WebhookServer) handleRequest(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(ResponsePayload{
			Status:  "error",
			Message: "Method Not Allowed. Use POST.",
		})
		return
	}

	endpointPath := strings.Split(r.URL.Path, "?")[0]

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		// A body over the cap is a distinct verdict from unparseable framing:
		// 413 means "too big", 401 means "I cannot trust these bytes". A
		// truncated chunked stream ends without io.EOF and must not be trusted.
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			logger.Warn("WebhookServer", "Rejected POST %s: body exceeds %d bytes", endpointPath, maxBodyBytes)
			w.WriteHeader(http.StatusRequestEntityTooLarge)
			_ = json.NewEncoder(w).Encode(ResponsePayload{
				Status:  "error",
				Message: "Request body too large or unreadable",
			})
			return
		}

		logger.Warn("WebhookServer", "Rejected POST %s: malformed body framing", endpointPath)
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(ResponsePayload{
			Status:  "error",
			Message: "Missing or invalid signature",
		})
		return
	}

	if !ws.signatureValid(r.Header.Get("X-Hub-Signature-256"), body) {
		logger.Warn("WebhookServer", "Rejected POST %s: missing or invalid X-Hub-Signature-256", endpointPath)
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(ResponsePayload{
			Status:  "error",
			Message: "Missing or invalid signature",
		})
		return
	}

	logger.Info("WebhookServer", "Received POST request on %s", endpointPath)

	rule := ws.ruleEngine.MatchWebhook(endpointPath)
	if rule == nil {
		logger.Warn("WebhookServer", "No webhook rule matching endpoint '%s'", endpointPath)
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(ResponsePayload{
			Status:  "error",
			Message: fmt.Sprintf("No webhook rule matching endpoint '%s'", endpointPath),
		})
		return
	}

	logger.Info("WebhookServer", "Triggering rule '%s' for endpoint '%s'", rule.Name, endpointPath)
	executor.ExecuteAsync(rule.Action, rule.Name)

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(ResponsePayload{
		Status:  "success",
		Rule:    rule.Name,
		Message: "Action triggered successfully",
	})
}

// signatureValid verifies the X-Hub-Signature-256 HMAC-SHA256 over the raw body.
func (ws *WebhookServer) signatureValid(provided string, body []byte) bool {
	if !strings.HasPrefix(provided, "sha256=") {
		return false
	}
	mac := hmac.New(sha256.New, []byte(ws.secret))
	mac.Write(body)
	expected := "sha256=" + hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(provided))
}

// Stop shuts down the HTTP server gracefully.
func (ws *WebhookServer) Stop() error {
	if ws.server != nil {
		logger.Info("WebhookServer", "Stopping Webhook Server...")
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		err := ws.server.Shutdown(ctx)
		logger.Info("WebhookServer", "Webhook Server stopped.")
		return err
	}
	return nil
}
