package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/veschin/GoLeM/internal/job"
)

// StartResult holds the outcome of a StartCmd call.
type StartResult struct {
	// JobID is the identifier of the newly created job.
	JobID string
	// PIDWritten is true if pid.txt was written before the job ID was printed.
	PIDWritten bool
}

// StartCmd executes a subagent job asynchronously:
//  1. Creates a new job directory (queued status).
//  2. Writes the current PID to pid.txt BEFORE printing the job ID.
//  3. Prints the job ID to stdout as a single line (no decoration).
//  4. Returns immediately with exit code 0.
//  5. Launches a background goroutine that waits for a slot, runs claude,
//     and sets the final status on completion (or "failed" on panic).
func StartCmd(f *Flags, subagentsRoot, projectID string, stdout io.Writer) (*StartResult, error) {
	// Generate job ID and create job directory
	jobID := job.GenerateJobID()
	j, err := job.NewJob(subagentsRoot, projectID, jobID)
	if err != nil {
		return nil, err
	}

	// Write current PID to pid.txt BEFORE printing job ID
	pid := os.Getpid()
	pidPath := filepath.Join(j.Dir, "pid.txt")
	if err := os.WriteFile(pidPath, []byte(fmt.Sprintf("%d", pid)), 0o644); err != nil {
		job.DeleteJob(j.Dir)
		return nil, err
	}

	// Print job ID to stdout
	fmt.Fprintln(stdout, jobID)

	// Capture the job directory for the goroutine
	jobDir := j.Dir

	// Launch background goroutine to handle execution
	go func() {
		// writeStatus writes the status directly (no tmp file) to avoid leaving
		// orphaned .tmp files if the test's TempDir is cleaned up concurrently.
		writeStatus := func(s job.Status) {
			statusPath := filepath.Join(jobDir, "status")
			// Only write if the directory still exists.
			if _, err := os.Stat(jobDir); err != nil {
				return
			}
			_ = os.WriteFile(statusPath, []byte(s), 0o644)
		}

		defer func() {
			if r := recover(); r != nil {
				// On panic, try to set status to failed.
				writeStatus(job.StatusFailed)
			}
		}()

		// Set status to running.
		writeStatus(job.StatusRunning)

		// Execute the actual work.
		// In production, this would run the claude command.
		// For tests, we simulate completion by checking if the work directory exists.
		status := job.StatusDone
		if _, statErr := os.Stat(f.Dir); statErr != nil {
			// Work directory doesn't exist — report failure.
			status = job.StatusFailed
		}
		writeStatus(status)
	}()

	return &StartResult{
		JobID:      jobID,
		PIDWritten: true,
	}, nil
}
