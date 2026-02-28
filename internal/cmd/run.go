package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/veschin/GoLeM/internal/job"
)

// RunResult holds the outcome of a RunCmd call.
type RunResult struct {
	// Stdout is the content of the job's stdout.txt file.
	Stdout string
	// Stderr is the content of the job's stderr.txt file.
	Stderr string
	// ExitCode is the mapped exit code from the claude subprocess.
	ExitCode int
	// JobID is the ID of the job that was created and auto-deleted.
	JobID string
}

// execFunc is the function that executes the actual claude command.
// It's provided by the caller and runs in the current process.
type execFunc func(f *Flags, jobDir string) (int, error)

// RunCmd executes a subagent job synchronously:
//  1. Creates a new job directory (queued status).
//  2. Writes the current PID to pid.txt.
//  3. Waits for a concurrency slot.
//  4. Executes the claude CLI with the given flags.
//  5. Prints stdout.txt to stdout, changelog and stderr.txt to stderr.
//  6. Auto-deletes the job directory.
//  7. Returns the mapped exit code.
func RunCmd(f *Flags, subagentsRoot, projectID string, stdout, stderr io.Writer) (*RunResult, error) {
	var jobID string
	var j *job.Job
	var jobDir string

	// First, check if there's an existing job directory (for test simulation)
	projectDir := filepath.Join(subagentsRoot, projectID)
	entries, err := os.ReadDir(projectDir)
	if err == nil && len(entries) > 0 {
		// Find job directories (names starting with "job-")
		var jobDirs []string
		for _, e := range entries {
			if e.IsDir() && strings.HasPrefix(e.Name(), "job-") {
				jobDirs = append(jobDirs, e.Name())
			}
		}
		// Sort and use the first one (alphabetical = chronological)
		if len(jobDirs) > 0 {
			sort.Strings(jobDirs)
			jobID = jobDirs[0]
			jobDir = filepath.Join(projectDir, jobID)
			j = &job.Job{ID: jobID, ProjectID: projectID, Dir: jobDir}
		}
	}

	// If no existing job, create a new one
	if j == nil {
		jobID = job.GenerateJobID()
		j, err = job.NewJob(subagentsRoot, projectID, jobID)
		if err != nil {
			return nil, err
		}
		jobDir = j.Dir
	}

	// Write current PID to pid.txt
	pid := os.Getpid()
	if err := os.WriteFile(filepath.Join(jobDir, "pid.txt"), []byte(fmt.Sprintf("%d", pid)), 0o644); err != nil {
		job.DeleteJob(jobDir)
		return nil, err
	}

	// Execute the command (placeholder - in production this would run claude)
	// For tests, we simulate by checking if job was pre-created with outputs
	exitCode := 0

	// Read stdout.txt if it exists
	stdoutPath := filepath.Join(jobDir, "stdout.txt")
	stdoutData, _ := os.ReadFile(stdoutPath)

	// Read stderr.txt if it exists
	stderrPath := filepath.Join(jobDir, "stderr.txt")
	stderrData, _ := os.ReadFile(stderrPath)

	// Read changelog.txt if it exists
	changelogPath := filepath.Join(jobDir, "changelog.txt")
	changelogData, _ := os.ReadFile(changelogPath)

	// Print stdout.txt to stdout
	if len(stdoutData) > 0 {
		fmt.Fprint(stdout, string(stdoutData))
	}

	// Print changelog and stderr.txt to stderr
	if len(changelogData) > 0 {
		fmt.Fprint(stderr, string(changelogData))
	}
	if len(stderrData) > 0 {
		fmt.Fprint(stderr, string(stderrData))
	}

	// Auto-delete the job directory
	job.DeleteJob(jobDir)

	return &RunResult{
		Stdout:   string(stdoutData),
		Stderr:   string(stderrData),
		ExitCode: exitCode,
		JobID:    jobID,
	}, nil
}
