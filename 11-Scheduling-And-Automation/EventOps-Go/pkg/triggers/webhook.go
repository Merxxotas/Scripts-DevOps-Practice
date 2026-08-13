// Package triggers implements HTTP Webhook and fsnotify File Watcher event triggers.
package triggers

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/executor"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/logger"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

// WebhookServer manages HTTP listener for incoming webhook triggers.
type WebhookServer struct {
	ruleEngine *ruleengine.RuleEngine
	host       string
	port       int
	server     *http.Server
}

// ResponsePayload defines JSON API response format.
type ResponsePayload struct {
	Status  string `json:"status"`
	Rule    string `json:"rule,omitempty"`
	Message string `json:"message"`
}

// NewWebhookServer constructs a WebhookServer instance.
func NewWebhookServer(re *ruleengine.RuleEngine, host string, port int) *WebhookServer {
	return &WebhookServer{
		ruleEngine: re,
		host:       host,
		port:       port,
	}
}

// Start launches the HTTP server in a background goroutine.
func (ws *WebhookServer) Start() error {
	addr := fmt.Sprintf("%s:%d", ws.host, ws.port)
	mux := http.NewServeMux()
	mux.HandleFunc("/", ws.handleRequest)

	ws.server = &http.Server{
		Addr:    addr,
		Handler: mux,
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
