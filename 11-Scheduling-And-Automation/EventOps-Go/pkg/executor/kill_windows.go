//go:build windows

package executor

import (
	"fmt"
	"os/exec"
)

// configureKill makes context cancellation kill the process tree via
// taskkill, so grandchildren inheriting pipes cannot outlive the timeout.
func configureKill(cmd *exec.Cmd) {
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		kill := exec.Command("taskkill", "/F", "/T", "/PID", fmt.Sprintf("%d", cmd.Process.Pid))
		return kill.Run()
	}
}
