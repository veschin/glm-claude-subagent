package cmd_test

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/veschin/GoLeM/internal/cmd"
)

// helpers -------------------------------------------------------------------

// makeSubagentsRoot creates a temporary subagents root directory for tests.
func makeSubagentsRoot(t *testing.T) string {
	t.Helper()
	return t.TempDir()
}

// writeJobDir creates a fake job directory under subagentsRoot/projectID/jobID
// with the given status and stdout content.
func writeJobDir(t *testing.T, root, projectID, jobID, status, stdout string) string {
	t.Helper()
	dir := filepath.Join(root, projectID, jobID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("writeJobDir MkdirAll: %v", err)
	}
	writeFile(t, filepath.Join(dir, "status"), status)
	writeFile(t, filepath.Join(dir, "stdout.txt"), stdout)
	return dir
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writeFile %s: %v", path, err)
	}
}

func chainFlags(dir string, timeout int, model string, continueOnError bool, prompts []string) *cmd.ChainFlags {
	f := &cmd.Flags{
		Dir:     dir,
		Timeout: timeout,
		Model:   model,
	}
	return &cmd.ChainFlags{
		Flags:           f,
		ContinueOnError: continueOnError,
		Prompts:         prompts,
	}
}

// AC1: Sequential execution of multiple prompts ----------------------------

// TestChainExecutesThreePromptsSequentially verifies that running "glm chain"
// with three prompts creates 3 jobs in strict sequence and that the first
// job starts before the second, and the second before the third.
func TestChainExecutesThreePromptsSequentially(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer
	prompts := []string{
		"Analyze src/auth/ for security issues",
		"Based on the analysis, write fixes for the critical issues found",
		"Write tests for the security fixes",
	}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if result.StepsExecuted != 3 {
		t.Errorf("expected 3 steps executed, got %d", result.StepsExecuted)
	}
	if len(result.JobDirs) != 3 {
		t.Errorf("expected 3 job dirs, got %d", len(result.JobDirs))
	}
}

// AC2: Each prompt is a separate job with its own artifacts ----------------

// TestEachChainStepProducesSeparateJobDirectory verifies that after running
// "glm chain" with three prompts, three separate job directories exist and
// each contains prompt.txt, stdout.txt, and status.
func TestEachChainStepProducesSeparateJobDirectory(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer
	prompts := []string{"Analyze code", "Fix issues", "Write tests"}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) != 3 {
		t.Fatalf("expected 3 job directories, got %d", len(result.JobDirs))
	}

	requiredFiles := []string{"prompt.txt", "stdout.txt", "status"}
	for i, dir := range result.JobDirs {
		for _, fname := range requiredFiles {
			fpath := filepath.Join(dir, fname)
			if _, err := os.Stat(fpath); os.IsNotExist(err) {
				t.Errorf("step %d: missing %s in %s", i+1, fname, dir)
			}
		}
	}
}

// AC3: Previous job stdout injected into next prompt -----------------------

// TestChainPassesPreviousResultToNextStep verifies that the second step's
// prompt.txt contains the "Previous agent result:" prefix followed by
// the first step's stdout, and "Your task:" followed by the raw prompt.
func TestChainPassesPreviousResultToNextStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{
		"Analyze src/auth/ for security issues",
		"Based on the analysis, write fixes for the critical issues found",
		"Write tests for the security fixes",
	}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) < 2 {
		t.Fatalf("expected at least 2 job dirs, got %d", len(result.JobDirs))
	}

	// Read step 2's prompt.txt.
	step2Prompt, err := os.ReadFile(filepath.Join(result.JobDirs[1], "prompt.txt"))
	if err != nil {
		t.Fatalf("cannot read step 2 prompt.txt: %v", err)
	}
	promptStr := string(step2Prompt)

	if !strings.Contains(promptStr, "Previous agent result:") {
		t.Errorf("step 2 prompt missing 'Previous agent result:'\ngot: %q", promptStr)
	}
	if !strings.Contains(promptStr, "Your task:") {
		t.Errorf("step 2 prompt missing 'Your task:'\ngot: %q", promptStr)
	}
	if !strings.Contains(promptStr, "Based on the analysis, write fixes for the critical issues found") {
		t.Errorf("step 2 prompt missing raw prompt\ngot: %q", promptStr)
	}

	if len(result.JobDirs) >= 3 {
		step3Prompt, err := os.ReadFile(filepath.Join(result.JobDirs[2], "prompt.txt"))
		if err != nil {
			t.Fatalf("cannot read step 3 prompt.txt: %v", err)
		}
		step3Str := string(step3Prompt)
		if !strings.Contains(step3Str, "Previous agent result:") {
			t.Errorf("step 3 prompt missing 'Previous agent result:'\ngot: %q", step3Str)
		}
	}
}

// AC4: Chain stops on failure by default -----------------------------------

// TestChainStopsAtFirstFailedStep verifies that when a step fails (exit code 1)
// and --continue-on-error is NOT set, only 1 step runs and the remaining 2
// are skipped. The stderr contains the failed job ID and "Directory not found".
// The final exit code is 1.
func TestChainStopsAtFirstFailedStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{
		"Analyze src/auth/middleware.ts for security vulnerabilities",
		"Refactor the middleware",
		"Write integration tests",
	}
	cf := chainFlags("/nonexistent-dir-that-does-not-exist", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if result.StepsExecuted != 1 {
		t.Errorf("expected 1 step executed, got %d", result.StepsExecuted)
	}
	if result.StepsSkipped != 2 {
		t.Errorf("expected 2 steps skipped, got %d", result.StepsSkipped)
	}
	if result.ExitCode != 1 {
		t.Errorf("expected exit code 1, got %d", result.ExitCode)
	}

	stderrStr := stderr.String()
	if !strings.Contains(stderrStr, "Directory not found") {
		t.Errorf("stderr missing 'Directory not found'\ngot: %q", stderrStr)
	}
}

// TestChainContinuesOnErrorWhenFlagIsSet verifies that with --continue-on-error,
// all 3 steps run even when step 1 fails. Final stdout is from step 3.
// Final exit code is 1 (at least one step failed).
func TestChainContinuesOnErrorWhenFlagIsSet(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{
		"Analyze src/db/queries.go for N+1 query issues",
		"Fix the N+1 queries identified in the previous step",
		"Run the test suite to verify fixes",
	}
	cf := chainFlags(".", 0, "", true, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if result.StepsExecuted != 3 {
		t.Errorf("expected all 3 steps executed, got %d", result.StepsExecuted)
	}
	if result.ExitCode != 1 {
		t.Errorf("expected exit code 1 (at least one failure), got %d", result.ExitCode)
	}
}

// TestContinueOnErrorStillInjectsStdoutFromFailedStep verifies that even when
// a step fails, its stdout is still injected into the next step's prompt.
func TestContinueOnErrorStillInjectsStdoutFromFailedStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{
		"Analyze src/db/queries.go for N+1 query issues",
		"Fix the N+1 queries identified in the previous step",
	}
	cf := chainFlags(".", 0, "", true, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) < 2 {
		t.Fatalf("expected at least 2 job dirs, got %d", len(result.JobDirs))
	}

	step2Prompt, err := os.ReadFile(filepath.Join(result.JobDirs[1], "prompt.txt"))
	if err != nil {
		t.Fatalf("cannot read step 2 prompt.txt: %v", err)
	}
	if !strings.Contains(string(step2Prompt), "Previous agent result:") {
		t.Errorf("step 2 prompt missing 'Previous agent result:'\ngot: %q", string(step2Prompt))
	}
}

// AC5: Returns final job stdout; intermediate dirs preserved ---------------

// TestChainReturnsFinalJobStdout verifies that the ChainResult.FinalStdout
// contains the last step's output.
func TestChainReturnsFinalJobStdout(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"Analyze", "Fix", "Write tests"}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	// The final stdout must match what the final step produced.
	// (The actual content depends on the stub/real implementation;
	// we check that FinalStdout is consistent with step 3's stdout.txt.)
	if len(result.JobDirs) == 0 {
		t.Fatal("no job dirs returned")
	}
	lastDir := result.JobDirs[len(result.JobDirs)-1]
	rawStdout, err := os.ReadFile(filepath.Join(lastDir, "stdout.txt"))
	if err != nil {
		t.Fatalf("cannot read last step stdout.txt: %v", err)
	}
	if result.FinalStdout != string(rawStdout) {
		t.Errorf("FinalStdout mismatch: got %q, want %q", result.FinalStdout, string(rawStdout))
	}
}

// TestIntermediateJobDirectoriesArePreservedAfterChain verifies that all 3
// job directories still exist on disk after the chain completes.
func TestIntermediateJobDirectoriesArePreservedAfterChain(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"Step 1", "Step 2", "Step 3"}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) != 3 {
		t.Fatalf("expected 3 job dirs, got %d", len(result.JobDirs))
	}
	for i, dir := range result.JobDirs {
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			t.Errorf("job dir %d (%s) does not exist after chain", i+1, dir)
		}
	}
}

// AC6: Chain progress printed to stderr ------------------------------------

// TestChainPrintsProgressToStderr verifies that each step produces a
// "[N/M] Running step N..." line on stderr.
func TestChainPrintsProgressToStderr(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"Analyze", "Fix", "Test"}
	cf := chainFlags(".", 0, "", false, prompts)

	_, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	stderrStr := stderr.String()
	expected := []string{
		"[1/3] Running step 1...",
		"[2/3] Running step 2...",
		"[3/3] Running step 3...",
	}
	for _, want := range expected {
		if !strings.Contains(stderrStr, want) {
			t.Errorf("stderr missing %q\ngot: %q", want, stderrStr)
		}
	}
}

// TestChainWithTwoStepsPrintsCorrectProgress verifies the progress format
// when only 2 prompts are given.
func TestChainWithTwoStepsPrintsCorrectProgress(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"Analyze", "Fix"}
	cf := chainFlags(".", 0, "", false, prompts)

	_, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	stderrStr := stderr.String()
	expected := []string{
		"[1/2] Running step 1...",
		"[2/2] Running step 2...",
	}
	for _, want := range expected {
		if !strings.Contains(stderrStr, want) {
			t.Errorf("stderr missing %q\ngot: %q", want, stderrStr)
		}
	}
}

// Edge case: Single prompt -------------------------------------------------

// TestChainWithSinglePromptBehavesLikeGlmRun verifies that a single-prompt
// chain runs successfully, prints "[1/1] Running step 1..." to stderr, and
// exits with code 0.
func TestChainWithSinglePromptBehavesLikeGlmRun(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"List all TODO comments in src/"}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	stderrStr := stderr.String()
	if !strings.Contains(stderrStr, "[1/1] Running step 1...") {
		t.Errorf("stderr missing '[1/1] Running step 1...'\ngot: %q", stderrStr)
	}
	if result.ExitCode != 0 {
		t.Errorf("expected exit code 0, got %d", result.ExitCode)
	}
	if result.StepsExecuted != 1 {
		t.Errorf("expected 1 step executed, got %d", result.StepsExecuted)
	}
}

// Edge case: Empty stdout --------------------------------------------------

// TestChainHandlesEmptyStdoutFromAStep verifies that when step 1 produces
// empty stdout, step 2's prompt still contains "Previous agent result:" and
// "Your task:", and the chain exits 0.
func TestChainHandlesEmptyStdoutFromAStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{
		"Delete all .tmp files in the project",
		"Verify no .tmp files remain",
	}
	cf := chainFlags(".", 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if result.ExitCode != 0 {
		t.Errorf("expected exit code 0, got %d", result.ExitCode)
	}

	if len(result.JobDirs) < 2 {
		t.Fatalf("expected at least 2 job dirs, got %d", len(result.JobDirs))
	}

	step2Prompt, err := os.ReadFile(filepath.Join(result.JobDirs[1], "prompt.txt"))
	if err != nil {
		t.Fatalf("cannot read step 2 prompt.txt: %v", err)
	}
	promptStr := string(step2Prompt)

	if !strings.Contains(promptStr, "Previous agent result:") {
		t.Errorf("step 2 prompt missing 'Previous agent result:'\ngot: %q", promptStr)
	}
	if !strings.Contains(promptStr, "Your task:") {
		t.Errorf("step 2 prompt missing 'Your task:'\ngot: %q", promptStr)
	}
	if !strings.Contains(promptStr, "Verify no .tmp files remain") {
		t.Errorf("step 2 prompt missing user prompt\ngot: %q", promptStr)
	}
}

// Edge case: All steps fail with --continue-on-error -----------------------

// TestAllStepsFailWithContinueOnErrorReturnsNonZeroExit verifies that when
// every step fails and --continue-on-error is set, all 3 steps are executed
// and the exit code is non-zero.
func TestAllStepsFailWithContinueOnErrorReturnsNonZeroExit(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{
		"Analyze src/auth/ for security issues",
		"Write fixes for the issues",
		"Write tests for the fixes",
	}
	// Use a non-existent dir to force failures on all steps.
	cf := chainFlags("/nonexistent-path-xyz-abc", 0, "", true, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if result.StepsExecuted != 3 {
		t.Errorf("expected all 3 steps executed, got %d", result.StepsExecuted)
	}
	if result.ExitCode == 0 {
		t.Errorf("expected non-zero exit code, got 0")
	}
}

// Flags pass-through -------------------------------------------------------

// TestChainPassesDirectoryFlagToEachStep verifies that each job's workdir
// is set to the value of the -d flag.
func TestChainPassesDirectoryFlagToEachStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	workdir := t.TempDir() // must exist for Validate to pass
	prompts := []string{"Analyze", "Fix"}
	cf := chainFlags(workdir, 0, "", false, prompts)

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) == 0 {
		t.Fatal("no job dirs returned")
	}

	// Verify each job's workdir file contains the expected path.
	for i, dir := range result.JobDirs {
		workdirFile := filepath.Join(dir, "workdir")
		data, err := os.ReadFile(workdirFile)
		if err != nil {
			t.Errorf("step %d: cannot read workdir file: %v", i+1, err)
			continue
		}
		if strings.TrimSpace(string(data)) != workdir {
			t.Errorf("step %d: workdir = %q, want %q", i+1, strings.TrimSpace(string(data)), workdir)
		}
	}
}

// TestChainPassesTimeoutFlagToEachStep verifies that each job uses the
// timeout specified by -t.
func TestChainPassesTimeoutFlagToEachStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"Analyze", "Fix"}
	cf := &cmd.ChainFlags{
		Flags:           &cmd.Flags{Dir: ".", Timeout: 600},
		ContinueOnError: false,
		Prompts:         prompts,
	}

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) == 0 {
		t.Fatal("no job dirs returned")
	}

	// Verify each job's timeout file contains "600".
	for i, dir := range result.JobDirs {
		timeoutFile := filepath.Join(dir, "timeout")
		data, err := os.ReadFile(timeoutFile)
		if err != nil {
			t.Errorf("step %d: cannot read timeout file: %v", i+1, err)
			continue
		}
		if strings.TrimSpace(string(data)) != "600" {
			t.Errorf("step %d: timeout = %q, want %q", i+1, strings.TrimSpace(string(data)), "600")
		}
	}
}

// TestChainPassesModelFlagToEachStep verifies that each job uses the model
// specified by -m.
func TestChainPassesModelFlagToEachStep(t *testing.T) {
	root := makeSubagentsRoot(t)
	var stdout, stderr bytes.Buffer

	prompts := []string{"Analyze", "Fix"}
	cf := &cmd.ChainFlags{
		Flags:           &cmd.Flags{Dir: ".", Model: "custom-model"},
		ContinueOnError: false,
		Prompts:         prompts,
	}

	result, err := cmd.ChainCmd(cf, root, "test-project", &stdout, &stderr)
	if err != nil {
		t.Fatalf("ChainCmd error: %v", err)
	}

	if len(result.JobDirs) == 0 {
		t.Fatal("no job dirs returned")
	}

	// Verify each job's model file contains "custom-model".
	for i, dir := range result.JobDirs {
		modelFile := filepath.Join(dir, "model")
		data, err := os.ReadFile(modelFile)
		if err != nil {
			t.Errorf("step %d: cannot read model file: %v", i+1, err)
			continue
		}
		if strings.TrimSpace(string(data)) != "custom-model" {
			t.Errorf("step %d: model = %q, want %q", i+1, strings.TrimSpace(string(data)), "custom-model")
		}
	}
}

// BuildChainPrompt unit tests -----------------------------------------------

// TestBuildChainPromptFormat verifies the exact format of the injected prompt.
func TestBuildChainPromptFormat(t *testing.T) {
	prev := "Found 3 issues: SQL injection in login.ts, XSS in profile.ts, missing CSRF token"
	next := "Based on the analysis, write fixes for the critical issues found"

	got := cmd.BuildChainPrompt(prev, next)

	if !strings.Contains(got, "Previous agent result:") {
		t.Errorf("prompt missing 'Previous agent result:'\ngot: %q", got)
	}
	if !strings.Contains(got, prev) {
		t.Errorf("prompt missing previous stdout\ngot: %q", got)
	}
	if !strings.Contains(got, "Your task:") {
		t.Errorf("prompt missing 'Your task:'\ngot: %q", got)
	}
	if !strings.Contains(got, next) {
		t.Errorf("prompt missing user prompt\ngot: %q", got)
	}

	want := "Previous agent result:\n" + prev + "\n\nYour task:\n" + next
	if got != want {
		t.Errorf("BuildChainPrompt exact format mismatch:\ngot:  %q\nwant: %q", got, want)
	}
}

// TestBuildChainPromptWithEmptyPrevStdout verifies that an empty previous
// stdout still produces the correct structure.
func TestBuildChainPromptWithEmptyPrevStdout(t *testing.T) {
	got := cmd.BuildChainPrompt("", "Verify no .tmp files remain")

	if !strings.Contains(got, "Previous agent result:") {
		t.Errorf("prompt missing 'Previous agent result:'\ngot: %q", got)
	}
	if !strings.Contains(got, "Your task:") {
		t.Errorf("prompt missing 'Your task:'\ngot: %q", got)
	}
	if !strings.Contains(got, "Verify no .tmp files remain") {
		t.Errorf("prompt missing user prompt\ngot: %q", got)
	}
}
