// EventOps-Go is a cross-platform, event-driven automation daemon written in Go.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/logger"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/triggers"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	command := os.Args[1]
	switch command {
	case "start":
		runStartCommand(os.Args[2:])
	case "-h", "--help", "help":
		printUsage()
	default:
		fmt.Printf("Unknown command: %s\n", command)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("EventOps-Go - Cross-platform Event-Driven Automation Daemon")
	fmt.Println("\nUsage:")
	fmt.Println("  eventops start [options]")
	fmt.Println("\nOptions for start:")
	fmt.Println("  --config, -c    Path to rules.json configuration file (default: rules.json)")
	fmt.Println("  --host          Host interface for Webhook server (default: 0.0.0.0)")
	fmt.Println("  --port, -p      Port for Webhook server (default: 8080)")
	fmt.Println("  --log-file      Path to log file (default: eventops.log)")
	fmt.Println("  --log-level     Logging level: DEBUG, INFO, WARN, ERROR (default: INFO)")
}

func runStartCommand(args []string) {
	fs := flag.NewFlagSet("start", flag.ExitOnError)
	configPath := fs.String("config", "rules.json", "Path to rules.json configuration file")
	fs.StringVar(configPath, "c", "rules.json", "Path to rules.json configuration file (shorthand)")
	host := fs.String("host", "0.0.0.0", "Host interface for Webhook server")
	port := fs.Int("port", 8080, "Port for Webhook server")
	fs.IntVar(port, "p", 8080, "Port for Webhook server (shorthand)")
	logFile := fs.String("log-file", "eventops.log", "Path to log file")
	logLevelStr := fs.String("log-level", "INFO", "Logging level")

	_ = fs.Parse(args)

	logLevel := logger.ParseLogLevel(*logLevelStr)
	l, err := logger.InitLogger(*logFile, logLevel)
	if err != nil {
		fmt.Printf("Error initializing logger: %v\n", err)
		os.Exit(1)
	}
	defer l.Close()

	logger.Info("Main", "Starting EventOps Daemon (Go Edition)...")
	logger.Info("Main", "Loading configuration from: %s", *configPath)

	re := ruleengine.NewRuleEngine()
	if _, err := re.LoadFromFile(*configPath); err != nil {
		logger.Error("Main", "Configuration error: %v", err)
		os.Exit(1)
	}

	webhookServer := triggers.NewWebhookServer(re, *host, *port)
	if err := webhookServer.Start(); err != nil {
		logger.Error("Main", "Failed to start Webhook Server: %v", err)
		os.Exit(1)
	}

	fileWatcher := triggers.NewFileWatcherManager(re, 2.0)
	if err := fileWatcher.Start(); err != nil {
		logger.Error("Main", "Failed to start File Watcher: %v", err)
		_ = webhookServer.Stop()
		os.Exit(1)
	}

	logger.Info("Main", "EventOps Daemon is now active and monitoring events.")

	// Handle OS shutdown signals cleanly
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	sig := <-stopChan
	logger.Info("Main", "Received OS signal %v. Initiating graceful shutdown...", sig)

	fileWatcher.Stop()
	_ = webhookServer.Stop()

	// Brief pause to allow pending goroutine logs to flush
	time.Sleep(200 * time.Millisecond)
	logger.Info("Main", "EventOps Daemon shutdown complete.")
}
