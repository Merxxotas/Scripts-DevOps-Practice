package triggers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

func setupTestRuleEngine() *ruleengine.RuleEngine {
	re := ruleengine.NewRuleEngine()
	_, _ = re.LoadFromConfig(&ruleengine.Config{
		Rules: []ruleengine.Rule{
			{
				Name:     "Test Deploy",
				Type:     "webhook",
				Endpoint: "/deploy",
				Action:   "echo 'webhook ok'",
			},
		},
	})
	return re
}

func TestWebhookHandler_Success(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089)

	req := httptest.NewRequest(http.MethodPost, "/deploy", nil)
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	var payload ResponsePayload
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to decode json response: %v", err)
	}

	if payload.Status != "success" || payload.Rule != "Test Deploy" {
		t.Errorf("unexpected payload: %+v", payload)
	}
}

func TestWebhookHandler_NotFound(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089)

	req := httptest.NewRequest(http.MethodPost, "/unknown", nil)
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rec.Code)
	}
}

func TestWebhookHandler_MethodNotAllowed(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089)

	req := httptest.NewRequest(http.MethodGet, "/deploy", nil)
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected status 405, got %d", rec.Code)
	}
}

func TestWebhookServer_Lifecycle(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8098)

	if err := ws.Start(); err != nil {
		t.Fatalf("failed to start webhook server: %v", err)
	}

	time.Sleep(100 * time.Millisecond)

	resp, err := http.Post("http://127.0.0.1:8098/deploy", "application/json", strings.NewReader(""))
	if err != nil {
		t.Fatalf("http post failed: %v", err)
	}
	_ = resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200 OK, got %d", resp.StatusCode)
	}

	if err := ws.Stop(); err != nil {
		t.Errorf("error stopping webhook server: %v", err)
	}
}
