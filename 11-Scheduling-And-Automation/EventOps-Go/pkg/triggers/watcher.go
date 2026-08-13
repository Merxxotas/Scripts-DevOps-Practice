package triggers

import (
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/executor"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/logger"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

// FileWatcherManager manages fsnotify OS filesystem monitoring and debouncing.
type FileWatcherManager struct {
	ruleEngine    *ruleengine.RuleEngine
	cooldown      time.Duration
	watcher       *fsnotify.Watcher
	mu            sync.Mutex
	lastTriggered map[string]time.Time
	done          chan struct{}
}

// NewFileWatcherManager constructs a FileWatcherManager instance.
func NewFileWatcherManager(re *ruleengine.RuleEngine, cooldownSeconds float64) *FileWatcherManager {
	return &FileWatcherManager{
		ruleEngine:    re,
		cooldown:      time.Duration(cooldownSeconds * float64(time.Second)),
		lastTriggered: make(map[string]time.Time),
		done:          make(chan struct{}),
	}
}

// Start initializes the fsnotify watcher and monitors directories.
func (fwm *FileWatcherManager) Start() error {
	rules := fwm.ruleEngine.GetFileChangeRules()
	if len(rules) == 0 {
		logger.Info("FileWatcher", "No file change rules registered. File Watcher dormant.")
		return nil
	}

	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	fwm.watcher = w

	watchDirs := make(map[string]bool)
	for _, r := range rules {
		if r.WatchPath != "" {
			dir := filepath.Dir(r.WatchPath)
			if dir == "" {
				dir = "."
			}
			watchDirs[filepath.Clean(dir)] = true
		}
	}

	for dir := range watchDirs {
		logger.Info("FileWatcher", "Watching directory for changes: %s", dir)
		if err := fwm.watcher.Add(dir); err != nil {
			logger.Warn("FileWatcher", "Failed to watch directory %s: %v", dir, err)
		}
	}

	go fwm.eventLoop()

	logger.Info("FileWatcher", "File Watcher started successfully.")
	return nil
}

func (fwm *FileWatcherManager) eventLoop() {
	for {
		select {
		case <-fwm.done:
			return
		case event, ok := <-fwm.watcher.Events:
			if !ok {
				return
			}
			if event.Has(fsnotify.Write) || event.Has(fsnotify.Create) {
				fwm.ProcessEvent(event.Name)
			}
		case err, ok := <-fwm.watcher.Errors:
			if !ok {
				return
			}
			logger.Error("FileWatcher", "Watcher error: %v", err)
		}
	}
}

// ProcessEvent checks rule matching and enforces debouncing cooldown.
func (fwm *FileWatcherManager) ProcessEvent(srcPath string) {
	rule := fwm.ruleEngine.MatchFileChange(srcPath)
	if rule == nil {
		return
	}

	fwm.mu.Lock()
	now := time.Now()
	lastTime, exists := fwm.lastTriggered[rule.Name]

	if exists && now.Sub(lastTime) < fwm.cooldown {
		logger.Debug("FileWatcher", "Debounced file change event for rule '%s' (%.2fs < %.2fs cooldown)",
			rule.Name, now.Sub(lastTime).Seconds(), fwm.cooldown.Seconds())
		fwm.mu.Unlock()
		return
	}

	fwm.lastTriggered[rule.Name] = now
	fwm.mu.Unlock()

	logger.Info("FileWatcher", "File change detected on '%s'. Triggering rule '%s'", srcPath, rule.Name)
	executor.ExecuteAsync(rule.Action, rule.Name)
}

// Stop closes the fsnotify watcher cleanly.
func (fwm *FileWatcherManager) Stop() {
	if fwm.watcher != nil {
		logger.Info("FileWatcher", "Stopping File Watcher...")
		close(fwm.done)
		_ = fwm.watcher.Close()
		logger.Info("FileWatcher", "File Watcher stopped.")
	}
}
