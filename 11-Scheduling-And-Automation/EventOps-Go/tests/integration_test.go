package tests

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/logger"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/triggers"
)

func TestFullDaemonIntegration(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "eventops_go_integration_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	watchedFile := filepath.Join(tmpDir, "trigger_file.txt")
	outputLogFile := filepath.Join(tmpDir, "output_action.log")
	configFile := filepath.Join(tmpDir, "rules.json")
	daemonLogFile := filepath.Join(tmpDir, "eventops.log")

	_ = os.WriteFile(watchedFile, []byte("initial state\n"), 0644)

	var actionWebhook, actionFile string
	if runtime.GOOS == "windows" {
		actionWebhook = fmt.Sprintf("echo webhook ok >> \"%s\"", outputLogFile)
		actionFile = fmt.Sprintf("echo file ok >> \"%s\"", outputLogFile)
	} else {
		actionWebhook = fmt.Sprintf("echo 'webhook ok' >> '%s'", outputLogFile)
		actionFile = fmt.Sprintf("echo 'file ok' >> '%s'", outputLogFile)
	}

	cfgContent := ruleengine.Config{
		Rules: []ruleengine.Rule{
			{
				Name:     "E2E Webhook Rule",
				Type:     "webhook",
				Endpoint: "/e2e-webhook",
				Action:   actionWebhook,
			},
			{
				Name:      "E2E File Rule",
				Type:      "file_change",
				WatchPath: watchedFile,
				Action:    actionFile,
			},
		},
	}

	data, err := json.Marshal(cfgContent)
	if err != nil {
		t.Fatalf("failed to marshal rules json: %v", err)
	}
	_ = os.WriteFile(configFile, data, 0644)

	_, _ = logger.InitLogger(daemonLogFile, logger.DEBUG)

	re := ruleengine.NewRuleEngine()
	if _, err := re.LoadFromFile(configFile); err != nil {
		t.Fatalf("failed to load rule engine: %v", err)
	}

	ws := triggers.NewWebhookServer(re, "127.0.0.1", 8097)
	if err := ws.Start(); err != nil {
		t.Fatalf("failed to start webhook server: %v", err)
	}
	defer func() { _ = ws.Stop() }()

	watcher := triggers.NewFileWatcherManager(re, 0.5)
	if err := watcher.Start(); err != nil {
		t.Fatalf("failed to start file watcher: %v", err)
	}
	defer watcher.Stop()

	time.Sleep(200 * time.Millisecond)

	// 1. Trigger Webhook
	resp, err := http.Post("http://127.0.0.1:8097/e2e-webhook", "application/json", strings.NewReader(""))
	if err != nil {
		t.Fatalf("webhook post failed: %v", err)
	}
	_ = resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected webhook status 200, got %d", resp.StatusCode)
	}

	time.Sleep(400 * time.Millisecond)

	// 2. Trigger File Watcher
	watcher.ProcessEvent(watchedFile)

	time.Sleep(500 * time.Millisecond)

	outData, err := os.ReadFile(outputLogFile)
	if err != nil {
		t.Fatalf("output log file was not created: %v", err)
	}

	content := string(outData)
	if !strings.Contains(content, "webhook ok") {
		t.Errorf("expected output log to contain 'webhook ok', got:\n%s", content)
	}
	if !strings.Contains(content, "file ok") {
		t.Errorf("expected output log to contain 'file ok', got:\n%s", content)
	}
}
