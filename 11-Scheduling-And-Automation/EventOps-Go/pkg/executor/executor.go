// Package executor safely executes shell commands asynchronously or synchronously.
package executor

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"runtime"
	"strings"
	"sync"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/logger"
)

// Result holds the execution outcome of a shell command.
type Result struct {
	ExitCode int
	Stdout   string
	Stderr   string
	Err      error
}

// ExecuteSync runs a shell command synchronously and logs output.
func ExecuteSync(action string, ruleName string) Result {
	tag := ""
	if ruleName != "" {
		tag = fmt.Sprintf("[%s]", ruleName)
	}

	logger.Info("Executor", "Executing action %s: %s", tag, action)

	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("cmd.exe", "/C", action)
	} else {
		cmd = exec.Command("sh", "-c", action)
	}

	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		logger.Error("Executor", "Failed to create stdout pipe %s: %v", tag, err)
		return Result{ExitCode: -1, Err: err}
	}

	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		logger.Error("Executor", "Failed to create stderr pipe %s: %v", tag, err)
		return Result{ExitCode: -1, Err: err}
	}

	if err := cmd.Start(); err != nil {
		logger.Error("Executor", "Failed to start command %s: %v", tag, err)
		return Result{ExitCode: -1, Err: err}
	}

	var stdoutBuf, stderrBuf strings.Builder
	var wg sync.WaitGroup
	wg.Add(2)

	// Stream stdout
	go func() {
		defer wg.Done()
		scanAndLog(stdoutPipe, &stdoutBuf, func(line string) {
			logger.Info("Executor", "[stdout %s] %s", tag, line)
		})
	}()

	// Stream stderr
	go func() {
		defer wg.Done()
		scanAndLog(stderrPipe, &stderrBuf, func(line string) {
			logger.Warn("Executor", "[stderr %s] %s", tag, line)
		})
	}()

	err = cmd.Wait()
	wg.Wait() // Ensure all pipe output is read before returning

	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
		}
		logger.Error("Executor", "Action %s failed with exit code %d: %s", tag, exitCode, action)
	} else {
		logger.Info("Executor", "Action %s completed successfully.", tag)
	}

	return Result{
		ExitCode: exitCode,
		Stdout:   stdoutBuf.String(),
		Stderr:   stderrBuf.String(),
		Err:      err,
	}
}

// ExecuteAsync spawns a goroutine to execute a shell command asynchronously.
func ExecuteAsync(action string, ruleName string) {
	go func() {
		_ = ExecuteSync(action, ruleName)
	}()
}

func scanAndLog(r io.Reader, buf *strings.Builder, logFn func(string)) {
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := scanner.Text()
		buf.WriteString(line + "\n")
		logFn(line)
	}
}
