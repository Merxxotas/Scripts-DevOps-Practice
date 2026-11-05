//go:build !windows

package executor

import (
	"os/exec"
	"syscall"
)

// configureKill makes the command run in its own process group and, on
// context cancellation, signals the whole group instead of only the direct
// child, so grandchildren holding inherited pipes cannot outlive the timeout.
func configureKill(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		if err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); err != nil {
			return cmd.Process.Kill()
		}
		return nil
	}
}
