// Package ruleengine parses, validates, and matches EventOps rules.
package ruleengine

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Rule represents a single EventOps automation rule.
type Rule struct {
	Name      string `json:"name"`
	Type      string `json:"type"`
	Endpoint  string `json:"endpoint,omitempty"`
	WatchPath string `json:"watch_path,omitempty"`
	Action    string `json:"action"`
}

// Config represents the root structure of rules.json.
type Config struct {
	Rules []Rule `json:"rules"`
}

// RuleEngine handles rule storage, validation, and event matching.
type RuleEngine struct {
	rules []Rule
}

// NewRuleEngine initializes an empty RuleEngine.
func NewRuleEngine() *RuleEngine {
	return &RuleEngine{
		rules: make([]Rule, 0),
	}
}

// LoadFromFile reads and validates rules from a JSON file.
func (re *RuleEngine) LoadFromFile(filePath string) ([]Rule, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file %s: %w", filePath, err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("invalid JSON schema in %s: %w", filePath, err)
	}

	return re.LoadFromConfig(&cfg)
}

// LoadFromConfig validates and registers rules from a Config struct.
func (re *RuleEngine) LoadFromConfig(cfg *Config) ([]Rule, error) {
	if cfg == nil || len(cfg.Rules) == 0 {
		return nil, fmt.Errorf("configuration rules list cannot be empty")
	}

	seenNames := make(map[string]bool)
	validated := make([]Rule, 0, len(cfg.Rules))

	for idx, r := range cfg.Rules {
		rule, err := re.validateRule(r, idx)
		if err != nil {
			return nil, err
		}

		if seenNames[rule.Name] {
			return nil, fmt.Errorf("duplicate rule name found: '%s'", rule.Name)
		}
		seenNames[rule.Name] = true
		validated = append(validated, rule)
	}

	re.rules = validated
	return re.rules, nil
}

func (re *RuleEngine) validateRule(r Rule, idx int) (Rule, error) {
	if strings.TrimSpace(r.Name) == "" {
		return r, fmt.Errorf("rule at index %d missing valid 'name'", idx)
	}

	if r.Type != "webhook" && r.Type != "file_change" {
		return r, fmt.Errorf("rule '%s' has invalid type '%s' (must be 'webhook' or 'file_change')", r.Name, r.Type)
	}

	if strings.TrimSpace(r.Action) == "" {
		return r, fmt.Errorf("rule '%s' missing valid 'action' command", r.Name)
	}

	if r.Type == "webhook" {
		if strings.TrimSpace(r.Endpoint) == "" {
			return r, fmt.Errorf("rule '%s' of type 'webhook' requires valid 'endpoint'", r.Name)
		}
		if !strings.HasPrefix(r.Endpoint, "/") {
			r.Endpoint = "/" + r.Endpoint
		}
	}

	if r.Type == "file_change" {
		if strings.TrimSpace(r.WatchPath) == "" {
			return r, fmt.Errorf("rule '%s' of type 'file_change' requires valid 'watch_path'", r.Name)
		}
		absPath, err := filepath.Abs(r.WatchPath)
		if err == nil {
			r.WatchPath = absPath
		}
	}

	return r, nil
}

// MatchWebhook searches for a rule matching an incoming URI path.
func (re *RuleEngine) MatchWebhook(path string) *Rule {
	normalized := path
	if !strings.HasPrefix(normalized, "/") {
		normalized = "/" + normalized
	}
	if len(normalized) > 1 && strings.HasSuffix(normalized, "/") {
		normalized = strings.TrimSuffix(normalized, "/")
	}

	for _, r := range re.rules {
		if r.Type == "webhook" && r.Endpoint != "" {
			ep := r.Endpoint
			if len(ep) > 1 && strings.HasSuffix(ep, "/") {
				ep = strings.TrimSuffix(ep, "/")
			}
			if ep == normalized {
				ruleCopy := r
				return &ruleCopy
			}
		}
	}
	return nil
}

// MatchFileChange searches for a rule matching a modified file path.
func (re *RuleEngine) MatchFileChange(modifiedPath string) *Rule {
	absMod, err := filepath.Abs(modifiedPath)
	if err != nil {
		absMod = modifiedPath
	}
	absModNorm := filepath.Clean(strings.ToLower(absMod))

	for _, r := range re.rules {
		if r.Type == "file_change" && r.WatchPath != "" {
			rulePathNorm := filepath.Clean(strings.ToLower(r.WatchPath))
			if rulePathNorm == absModNorm {
				ruleCopy := r
				return &ruleCopy
			}
		}
	}
	return nil
}

// GetWebhookRules returns all registered webhook rules.
func (re *RuleEngine) GetWebhookRules() []Rule {
	res := make([]Rule, 0)
	for _, r := range re.rules {
		if r.Type == "webhook" {
			res = append(res, r)
		}
	}
	return res
}

// GetFileChangeRules returns all registered file change rules.
func (re *RuleEngine) GetFileChangeRules() []Rule {
	res := make([]Rule, 0)
	for _, r := range re.rules {
		if r.Type == "file_change" {
			res = append(res, r)
		}
	}
	return res
}
