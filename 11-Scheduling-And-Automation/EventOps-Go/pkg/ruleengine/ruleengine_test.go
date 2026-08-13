package ruleengine

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadFromConfig_Valid(t *testing.T) {
	cfg := &Config{
		Rules: []Rule{
			{
				Name:     "Deploy Webhook",
				Type:     "webhook",
				Endpoint: "/deploy",
				Action:   "echo deploy",
			},
			{
				Name:      "File Reload",
				Type:      "file_change",
				WatchPath: "config.txt",
				Action:    "echo reload",
			},
		},
	}

	re := NewRuleEngine()
	rules, err := re.LoadFromConfig(cfg)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if len(rules) != 2 {
		t.Fatalf("expected 2 rules, got %d", len(rules))
	}

	if rules[0].Endpoint != "/deploy" {
		t.Errorf("expected /deploy endpoint, got %s", rules[0].Endpoint)
	}

	absConfig, _ := filepath.Abs("config.txt")
	if rules[1].WatchPath != absConfig {
		t.Errorf("expected %s watch_path, got %s", absConfig, rules[1].WatchPath)
	}
}

func TestMatchWebhook(t *testing.T) {
	cfg := &Config{
		Rules: []Rule{
			{
				Name:     "Webhook Match Test",
				Type:     "webhook",
				Endpoint: "/api/v1/trigger",
				Action:   "echo hit",
			},
		},
	}

	re := NewRuleEngine()
	_, _ = re.LoadFromConfig(cfg)

	matched := re.MatchWebhook("/api/v1/trigger")
	if matched == nil {
		t.Fatalf("expected matched rule, got nil")
	}
	if matched.Name != "Webhook Match Test" {
		t.Errorf("expected 'Webhook Match Test', got '%s'", matched.Name)
	}

	if re.MatchWebhook("/unknown") != nil {
		t.Errorf("expected nil for unknown endpoint")
	}
}

func TestMatchFileChange(t *testing.T) {
	tmpFile, err := os.CreateTemp("", "test_rule_*.txt")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	_ = tmpFile.Close()

	cfg := &Config{
		Rules: []Rule{
			{
				Name:      "File Match Test",
				Type:      "file_change",
				WatchPath: tmpFile.Name(),
				Action:     "echo modified",
			},
		},
	}

	re := NewRuleEngine()
	_, _ = re.LoadFromConfig(cfg)

	matched := re.MatchFileChange(tmpFile.Name())
	if matched == nil {
		t.Fatalf("expected matched rule, got nil")
	}
	if matched.Name != "File Match Test" {
		t.Errorf("expected 'File Match Test', got '%s'", matched.Name)
	}

	if re.MatchFileChange("/tmp/nonexistent.txt") != nil {
		t.Errorf("expected nil for non-matching file")
	}
}

func TestLoadFromConfig_Invalid(t *testing.T) {
	invalidConfigs := []*Config{
		{Rules: []Rule{}},
		{Rules: []Rule{{Type: "webhook", Endpoint: "/t", Action: "ls"}}},               // missing name
		{Rules: []Rule{{Name: "R1", Type: "invalid", Action: "ls"}}},                   // invalid type
		{Rules: []Rule{{Name: "R1", Type: "webhook", Action: "ls"}}},                    // missing endpoint
		{Rules: []Rule{{Name: "R1", Type: "file_change", Action: "ls"}}},                // missing watch_path
		{Rules: []Rule{{Name: "R1", Type: "webhook", Endpoint: "/t", Action: ""}}},      // missing action
		{Rules: []Rule{                                                                  // duplicate name
			{Name: "Dup", Type: "webhook", Endpoint: "/t1", Action: "ls"},
			{Name: "Dup", Type: "webhook", Endpoint: "/t2", Action: "pwd"},
		}},
	}

	for idx, cfg := range invalidConfigs {
		re := NewRuleEngine()
		_, err := re.LoadFromConfig(cfg)
		if err == nil {
			t.Errorf("expected validation error for invalid config case %d", idx)
		}
	}
}
