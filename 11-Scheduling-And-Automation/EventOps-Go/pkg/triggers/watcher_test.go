package triggers

import (
	"os"
	"testing"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

func TestFileWatcher_Debouncing(t *testing.T) {
	tmpFile, err := os.CreateTemp("", "test_debounce_*.txt")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	_ = tmpFile.Close()

	re := ruleengine.NewRuleEngine()
	_, _ = re.LoadFromConfig(&ruleengine.Config{
		Rules: []ruleengine.Rule{
			{
				Name:      "Debounce Rule",
				Type:      "file_change",
				WatchPath: tmpFile.Name(),
				Action:    "echo 'file updated'",
			},
		},
	})

	manager := NewFileWatcherManager(re, 0.5)

	// First event -> should process
	manager.ProcessEvent(tmpFile.Name())

	// Immediate second event -> should be debounced
	manager.ProcessEvent(tmpFile.Name())

	time.Sleep(600 * time.Millisecond)

	// Event after cooldown -> should process again
	manager.ProcessEvent(tmpFile.Name())
}

func TestFileWatcherManager_Lifecycle(t *testing.T) {
	tmpFile, err := os.CreateTemp("", "test_lifecycle_*.txt")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	_ = tmpFile.Close()

	re := ruleengine.NewRuleEngine()
	_, _ = re.LoadFromConfig(&ruleengine.Config{
		Rules: []ruleengine.Rule{
			{
				Name:      "Lifecycle Rule",
				Type:      "file_change",
				WatchPath: tmpFile.Name(),
				Action:    "echo 'ok'",
			},
		},
	})

	manager := NewFileWatcherManager(re, 0.5)
	if err := manager.Start(); err != nil {
		t.Fatalf("failed to start watcher: %v", err)
	}

	time.Sleep(100 * time.Millisecond)
	manager.Stop()
}
