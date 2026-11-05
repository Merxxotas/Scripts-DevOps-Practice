package executor

import (
	"strings"
	"testing"
	"time"
)

func TestExecuteSync_Success(t *testing.T) {
	res := ExecuteSync("echo hello go executor", "TestRule")
	if res.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", res.ExitCode)
	}

	if !strings.Contains(res.Stdout, "hello go executor") {
		t.Errorf("expected stdout to contain 'hello go executor', got '%s'", res.Stdout)
	}
}

func TestExecuteSync_Failure(t *testing.T) {
	res := ExecuteSync("exit 12", "FailRule")
	if res.ExitCode == 0 {
		t.Fatalf("expected non-zero exit code, got 0")
	}
}

func TestExecuteAsync(t *testing.T) {
	done := make(chan bool)
	go func() {
		ExecuteAsync("echo async test", "AsyncRule")
		time.Sleep(100 * time.Millisecond)
		done <- true
	}()

	select {
	case <-done:
		// success
	case <-time.After(2 * time.Second):
		t.Fatal("async execution timed out")
	}
}

func TestExecuteSync_Timeout(t *testing.T) {
	start := time.Now()
	res := ExecuteSyncTimeout("sleep 5", "TimeoutRule", 500*time.Millisecond)
	elapsed := time.Since(start)

	if elapsed > 4*time.Second {
		t.Fatalf("expected timeout to kill the process promptly, took %s", elapsed)
	}
	if res.ExitCode == 0 {
		t.Fatalf("expected non-zero exit code on timeout, got 0")
	}
	if res.Err == nil {
		t.Fatalf("expected an error describing the timeout, got nil")
	}
}
