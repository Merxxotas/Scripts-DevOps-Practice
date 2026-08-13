// Package logger provides central logging functionality for the EventOps daemon.
package logger

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// LogLevel represents logging severity.
type LogLevel int

const (
	DEBUG LogLevel = iota
	INFO
	WARN
	ERROR
)

// String returns the string representation of a LogLevel.
func (l LogLevel) String() string {
	switch l {
	case DEBUG:
		return "DEBUG"
	case INFO:
		return "INFO"
	case WARN:
		return "WARNING"
	case ERROR:
		return "ERROR"
	default:
		return "INFO"
	}
}

// ParseLogLevel converts a level string into a LogLevel.
func ParseLogLevel(levelStr string) LogLevel {
	switch strings.ToUpper(strings.TrimSpace(levelStr)) {
	case "DEBUG":
		return DEBUG
	case "INFO":
		return INFO
	case "WARN", "WARNING":
		return WARN
	case "ERROR":
		return ERROR
	default:
		return INFO
	}
}

// Logger handles formatted output to console and log file.
type Logger struct {
	mu       sync.Mutex
	level    LogLevel
	writers  []io.Writer
	logFile  *os.File
	fileDest string
}

var globalLogger *Logger
var once sync.Once

// InitLogger initializes the central logger instance.
func InitLogger(fileDest string, level LogLevel) (*Logger, error) {
	var initErr error
	once.Do(func() {
		writers := []io.Writer{os.Stdout}
		var f *os.File

		if fileDest != "" {
			if err := os.MkdirAll(filepath.Dir(fileDest), 0755); err != nil && filepath.Dir(fileDest) != "." {
				initErr = fmt.Errorf("failed to create log directory: %w", err)
				return
			}
			var err error
			f, err = os.OpenFile(fileDest, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
			if err != nil {
				initErr = fmt.Errorf("failed to open log file %s: %w", fileDest, err)
				return
			}
			writers = append(writers, f)
		}

		globalLogger = &Logger{
			level:    level,
			writers:  writers,
			logFile:  f,
			fileDest: fileDest,
		}
	})

	if initErr != nil {
		return nil, initErr
	}
	return globalLogger, nil
}

// Get returns the global logger instance.
func Get() *Logger {
	if globalLogger == nil {
		l, _ := InitLogger("eventops.log", INFO)
		return l
	}
	return globalLogger
}

// SetLevel updates logger verbosity level.
func (l *Logger) SetLevel(lvl LogLevel) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.level = lvl
}

func (l *Logger) log(level LogLevel, component string, format string, v ...interface{}) {
	if level < l.level {
		return
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	timestamp := time.Now().Format("2006-01-02 15:04:05")
	msg := fmt.Sprintf(format, v...)
	logLine := fmt.Sprintf("[%s] [%s] [%s] %s\n", timestamp, level.String(), component, msg)

	for _, w := range l.writers {
		_, _ = w.Write([]byte(logLine))
	}
}

// Debug logs debug level messages.
func (l *Logger) Debug(component, format string, v ...interface{}) {
	l.log(DEBUG, component, format, v...)
}

// Info logs info level messages.
func (l *Logger) Info(component, format string, v ...interface{}) {
	l.log(INFO, component, format, v...)
}

// Warn logs warning level messages.
func (l *Logger) Warn(component, format string, v ...interface{}) {
	l.log(WARN, component, format, v...)
}

// Error logs error level messages.
func (l *Logger) Error(component, format string, v ...interface{}) {
	l.log(ERROR, component, format, v...)
}

// Close flushes and closes log file descriptors.
func (l *Logger) Close() {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.logFile != nil {
		_ = l.logFile.Close()
		l.logFile = nil
	}
}

// Helper package-level logging functions
func Debug(component, format string, v ...interface{}) { Get().Debug(component, format, v...) }
func Info(component, format string, v ...interface{})  { Get().Info(component, format, v...) }
func Warn(component, format string, v ...interface{})  { Get().Warn(component, format, v...) }
func Error(component, format string, v ...interface{}) { Get().Error(component, format, v...) }
