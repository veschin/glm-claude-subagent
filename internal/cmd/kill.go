package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/veschin/GoLeM/internal/job"
)

// KillCmd terminates the running job identified by jobID.
//
// Protocol:
//  1. Find the job directory (returns err:not_found / exit 3 if missing).
//  2. Read the current status; if not "running" return err:user "Job is not
//     running" (exit 1).
//  3. Read pid.txt to get the PID.
//  4. Send SIGTERM to the process group (-pid).
//  5. Wait 1 second.
//  6. If the process is still alive send SIGKILL to the process group.
//  7. Write "killed" to the status file.
//
// signalFn is injected for testing (production: os.Signal via syscall).
// sleepFn is injected for testing (production: time.Sleep(time.Second)).
//
// If the process has already died before SIGTERM/SIGKILL the function still
// updates the status to "killed" and returns nil.
func KillCmd(
	subagentsRoot, currentProjectID, jobID string,
	signalFn func(pid int, sig os.Signal) error,
	sleepFn func(),
) error {
	// 1. Find the job directory.
	jobDir, err := job.FindJobDir(subagentsRoot, currentProjectID, jobID)
	if err != nil {
		return fmt.Errorf("err:not_found")
	}

	// 2. Check status.
	statusData, err := os.ReadFile(filepath.Join(jobDir, "status"))
	if err != nil {
		return fmt.Errorf("err:not_found")
	}
	status := strings.TrimSpace(string(statusData))
	if status != "running" {
		return fmt.Errorf("err:user Job is not running (status: %s)", status)
	}

	// 3. Read pid.txt.
	pidData, err := os.ReadFile(filepath.Join(jobDir, "pid.txt"))
	if err != nil {
		// No PID file; still mark as killed.
		return writeKilledStatus(jobDir)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(pidData)))
	if err != nil {
		return writeKilledStatus(jobDir)
	}

	// 4. Send SIGTERM to the process group (-pid).
	termErr := signalFn(-pid, syscall.SIGTERM)

	// 5. Sleep.
	sleepFn()

	// 6. If process still alive, send SIGKILL.
	if termErr == nil {
		// SIGTERM succeeded (process was alive); check if still alive.
		_ = signalFn(-pid, syscall.SIGKILL)
	}
	// If termErr != nil, process was already dead — skip SIGKILL.

	// 7. Write "killed" status.
	return writeKilledStatus(jobDir)
}

// writeKilledStatus atomically writes "killed" to the status file.
func writeKilledStatus(jobDir string) error {
	return job.AtomicWrite(filepath.Join(jobDir, "status"), []byte("killed"))
}
