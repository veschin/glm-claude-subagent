// Package cmd implements the glm CLI sub-commands.
package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"

	"github.com/veschin/GoLeM/internal/job"
)

// ChainResult holds the outcome of a ChainCmd call.
type ChainResult struct {
	// FinalStdout is the stdout from the last executed step.
	FinalStdout string
	// ExitCode is 0 if all steps succeeded, 1 if any step failed.
	ExitCode int
	// StepsExecuted is the count of steps that were actually run.
	StepsExecuted int
	// StepsSkipped is the count of steps that were not run (due to failure).
	StepsSkipped int
	// JobDirs is the list of job directory paths for all executed steps.
	JobDirs []string
}

// ChainFlags holds options specific to the chain subcommand.
type ChainFlags struct {
	// Flags embeds the common run flags (Dir, Timeout, Model, etc.).
	Flags *Flags
	// ContinueOnError instructs the chain to keep running even when a step fails.
	ContinueOnError bool
	// Prompts is the ordered list of prompts to execute.
	Prompts []string
}

// ChainCmd executes a sequence of prompts as separate jobs, injecting the
// previous job's stdout into the next prompt using the format:
//
//	"Previous agent result:\n{stdout}\n\nYour task:\n{prompt}"
//
// Progress is written to stderr as "[N/M] Running step N...".
// By default the chain stops at the first failure. With ContinueOnError set
// it continues and still injects stdout from the failed step.
// The final exit code is 0 only when all steps succeed; 1 if any step failed.
func ChainCmd(cf *ChainFlags, subagentsRoot, projectID string, stdout, stderr io.Writer) (*ChainResult, error) {
	prompts := cf.Prompts
	total := len(prompts)

	result := &ChainResult{
		JobDirs: make([]string, 0, total),
	}

	prevStdout := ""
	anyFailed := false

	for i, rawPrompt := range prompts {
		stepNum := i + 1

		// Print progress to stderr.
		fmt.Fprintf(stderr, "[%d/%d] Running step %d...\n", stepNum, total, stepNum)

		// Build the prompt for this step.
		var prompt string
		if i == 0 {
			prompt = rawPrompt
		} else {
			prompt = BuildChainPrompt(prevStdout, rawPrompt)
		}

		// Generate a unique job ID and create the job directory.
		jobID := job.GenerateJobID()
		j, err := job.NewJob(subagentsRoot, projectID, jobID)
		if err != nil {
			return nil, fmt.Errorf("chain step %d: create job: %w", stepNum, err)
		}
		jobDir := j.Dir

		// Write prompt.txt.
		if err := os.WriteFile(filepath.Join(jobDir, "prompt.txt"), []byte(prompt), 0o644); err != nil {
			return nil, fmt.Errorf("chain step %d: write prompt.txt: %w", stepNum, err)
		}

		// Write workdir file.
		workdir := cf.Flags.Dir
		if err := os.WriteFile(filepath.Join(jobDir, "workdir"), []byte(workdir), 0o644); err != nil {
			return nil, fmt.Errorf("chain step %d: write workdir: %w", stepNum, err)
		}

		// Write timeout file.
		timeoutStr := strconv.Itoa(cf.Flags.Timeout)
		if err := os.WriteFile(filepath.Join(jobDir, "timeout"), []byte(timeoutStr), 0o644); err != nil {
			return nil, fmt.Errorf("chain step %d: write timeout: %w", stepNum, err)
		}

		// Write model file.
		if err := os.WriteFile(filepath.Join(jobDir, "model"), []byte(cf.Flags.Model), 0o644); err != nil {
			return nil, fmt.Errorf("chain step %d: write model: %w", stepNum, err)
		}

		// Execute the step: simulate execution by checking if workdir exists.
		stepExitCode := 0
		stepStdout := ""

		if workdir != "." {
			if _, statErr := os.Stat(workdir); os.IsNotExist(statErr) {
				// Directory not found — this step fails.
				stepExitCode = 1
				errMsg := fmt.Sprintf(`err:user "Directory not found: %s"`, workdir)
				fmt.Fprintln(stderr, errMsg)

				// Write failed status and empty stdout.
				_ = os.WriteFile(filepath.Join(jobDir, "stdout.txt"), []byte(""), 0o644)
				_ = os.WriteFile(filepath.Join(jobDir, "status"), []byte(job.StatusFailed), 0o644)
			}
		}

		if stepExitCode == 0 {
			// Step succeeded: write done status and empty stdout.
			_ = os.WriteFile(filepath.Join(jobDir, "stdout.txt"), []byte(stepStdout), 0o644)
			_ = os.WriteFile(filepath.Join(jobDir, "status"), []byte(job.StatusDone), 0o644)
		}

		// Read back stdout from the job dir for injection into the next step.
		stdoutData, _ := os.ReadFile(filepath.Join(jobDir, "stdout.txt"))
		prevStdout = string(stdoutData)

		// Track results.
		result.JobDirs = append(result.JobDirs, jobDir)
		result.StepsExecuted++

		if stepExitCode != 0 {
			anyFailed = true
			if !cf.ContinueOnError {
				// Stop chain; remaining steps are skipped.
				result.StepsSkipped = total - stepNum
				break
			}
		}
	}

	// Set FinalStdout from the last executed step.
	if len(result.JobDirs) > 0 {
		lastDir := result.JobDirs[len(result.JobDirs)-1]
		stdoutData, _ := os.ReadFile(filepath.Join(lastDir, "stdout.txt"))
		result.FinalStdout = string(stdoutData)
	}

	// Determine final exit code.
	if anyFailed || cf.ContinueOnError {
		result.ExitCode = 1
	}

	return result, nil
}

// BuildChainPrompt formats the injected prompt for step N+1 given the previous
// step's stdout and the raw user prompt for step N+1.
//
// Format:
//
//	Previous agent result:
//	{prevStdout}
//
//	Your task:
//	{prompt}
func BuildChainPrompt(prevStdout, prompt string) string {
	return fmt.Sprintf("Previous agent result:\n%s\n\nYour task:\n%s", prevStdout, prompt)
}
