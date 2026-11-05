package triggers

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

const testSecret = "test-secret-123"

func signBody(body []byte, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

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

func signedRequest(t *testing.T, method, target string, body []byte, secret string) *http.Request {
	t.Helper()
	req := httptest.NewRequest(method, target, strings.NewReader(string(body)))
	if secret != "" {
		req.Header.Set("X-Hub-Signature-256", signBody(body, secret))
	}
	return req
}

func TestWebhookHandler_Success(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	body := []byte(`{"ref":"main"}`)
	req := signedRequest(t, http.MethodPost, "/deploy", body, testSecret)
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

func TestWebhookHandler_MissingSignature_401(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	req := signedRequest(t, http.MethodPost, "/deploy", []byte("{}"), "")
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestWebhookHandler_InvalidSignature_401(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	req := signedRequest(t, http.MethodPost, "/deploy", []byte("{}"), testSecret)
	req.Header.Set("X-Hub-Signature-256", "sha256=deadbeef")
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestWebhookHandler_TamperedBody_401(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	signed := []byte(`{"ref":"main"}`)
	sig := signBody(signed, testSecret)

	// Attacker reuses the captured signature with a modified payload
	req := httptest.NewRequest(http.MethodPost, "/deploy", strings.NewReader(`{"ref":"pwned"}`))
	req.Header.Set("X-Hub-Signature-256", sig)
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestWebhookHandler_WrongSecret_401(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	body := []byte("{}")
	req := signedRequest(t, http.MethodPost, "/deploy", body, "attacker-secret")
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestWebhookHandler_NotFound(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	body := []byte("{}")
	req := signedRequest(t, http.MethodPost, "/unknown", body, testSecret)
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rec.Code)
	}
}

func TestWebhookHandler_MethodNotAllowed(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8089, testSecret)

	req := httptest.NewRequest(http.MethodGet, "/deploy", nil)
	rec := httptest.NewRecorder()

	ws.handleRequest(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected status 405, got %d", rec.Code)
	}
}

func TestWebhookServer_StartWithoutSecret_FailsClosed(t *testing.T) {
	t.Setenv("EVENTOPS_WEBHOOK_SECRET", "")
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8091, "")

	if err := ws.Start(); err == nil {
		t.Fatal("expected Start() to fail closed without a secret, got nil error")
	} else if !strings.Contains(err.Error(), "EVENTOPS_WEBHOOK_SECRET") {
		t.Fatalf("expected error to name EVENTOPS_WEBHOOK_SECRET, got: %v", err)
	}
}

func TestWebhookServer_Lifecycle(t *testing.T) {
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8098, testSecret)

	if err := ws.Start(); err != nil {
		t.Fatalf("failed to start webhook server: %v", err)
	}

	time.Sleep(100 * time.Millisecond)

	body := strings.NewReader("")
	req, err := http.NewRequest(http.MethodPost, "http://127.0.0.1:8098/deploy", body)
	if err != nil {
		t.Fatalf("failed to build request: %v", err)
	}
	req.Header.Set("X-Hub-Signature-256", signBody([]byte(""), testSecret))
	resp, err := http.DefaultClient.Do(req)
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

func TestWebhookServer_SecretFromEnv(t *testing.T) {
	t.Setenv("EVENTOPS_WEBHOOK_SECRET", testSecret)
	re := setupTestRuleEngine()
	ws := NewWebhookServer(re, "127.0.0.1", 8092, "")

	if ws.secret != testSecret {
		t.Fatalf("expected secret to be resolved from EVENTOPS_WEBHOOK_SECRET")
	}
}
