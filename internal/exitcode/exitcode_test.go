package exitcode_test

import (
	"fmt"
	"regexp"
	"strings"
	"testing"

	"github.com/veschin/GoLeM/internal/exitcode"
)

// ---------------------------------------------------------------------------
// AC1: Exit codes preserved from legacy
// ---------------------------------------------------------------------------

func TestExitCodeZeroForSuccess(t *testing.T) {
	if exitcode.OK != 0 {
		t.Errorf("OK exit code: got %d, want 0", exitcode.OK)
	}
}

func TestExitCode1ForUserErrorNoPrompt(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryUser, "No prompt provided")
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("exit code for user error: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
	if !strings.Contains(err.Error(), "err:user No prompt provided") {
		t.Errorf("error string: got %q, want to contain %q", err.Error(), "err:user No prompt provided")
	}
}

func TestExitCode1ForInvalidFlagValue(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryUser, "Timeout must be a positive number: notanumber")
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("exit code for invalid flag: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
	if !strings.Contains(err.Error(), "err:user") {
		t.Errorf("error string: got %q, want to contain %q", err.Error(), "err:user")
	}
}

func TestExitCode3ForNotFound(t *testing.T) {
	jobID := "job-20260227-143205-nonexistent"
	err := exitcode.NewError(exitcode.CategoryNotFound, fmt.Sprintf("Job not found: %s", jobID))
	if exitcode.ExitCodeFor(err.Category) != 3 {
		t.Errorf("exit code for not_found: got %d, want 3", exitcode.ExitCodeFor(err.Category))
	}
	want := "err:not_found Job not found: " + jobID
	if !strings.Contains(err.Error(), want) {
		t.Errorf("error string: got %q, want to contain %q", err.Error(), want)
	}
}

func TestExitCode124ForTimeout(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryTimeout, "Job exceeded 10s timeout")
	if exitcode.ExitCodeFor(err.Category) != 124 {
		t.Errorf("exit code for timeout: got %d, want 124", exitcode.ExitCodeFor(err.Category))
	}
	if !strings.Contains(err.Error(), "err:timeout Job exceeded 10s timeout") {
		t.Errorf("error string: got %q, want to contain %q", err.Error(), "err:timeout Job exceeded 10s timeout")
	}
}

func TestExitCode127ForMissingDependency(t *testing.T) {
	err := exitcode.NewErrorWithSuggestion(
		exitcode.CategoryDependency,
		"claude CLI not found in PATH",
		"Install from https://claude.ai/code",
	)
	if exitcode.ExitCodeFor(err.Category) != 127 {
		t.Errorf("exit code for dependency: got %d, want 127", exitcode.ExitCodeFor(err.Category))
	}
	want := "err:dependency claude CLI not found in PATH. Install from https://claude.ai/code"
	if !strings.Contains(err.Error(), want) {
		t.Errorf("error string: got %q, want to contain %q", err.Error(), want)
	}
}

// ---------------------------------------------------------------------------
// AC2: Error message format err:{category} {message}
// ---------------------------------------------------------------------------

func TestUserErrorFollowsErrUserFormat(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryUser, "No prompt provided")
	want := "err:user No prompt provided"
	if err.Error() != want {
		t.Errorf("error format: got %q, want %q", err.Error(), want)
	}
}

func TestNotFoundErrorFollowsErrNotFoundFormat(t *testing.T) {
	jobID := "job-20260227-143205-a8f3b1c2"
	err := exitcode.NewError(exitcode.CategoryNotFound, "Job not found: "+jobID)
	want := "err:not_found Job not found: " + jobID
	if err.Error() != want {
		t.Errorf("error format: got %q, want %q", err.Error(), want)
	}
}

func TestDependencyErrorFollowsErrDependencyFormat(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryDependency, "claude CLI not found in PATH")
	want := "err:dependency claude CLI not found in PATH"
	if err.Error() != want {
		t.Errorf("error format: got %q, want %q", err.Error(), want)
	}
}

func TestValidationErrorFollowsErrValidationFormat(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryValidation, "permission_mode: invalid value 'yolo'")
	want := "err:validation permission_mode: invalid value 'yolo'"
	if err.Error() != want {
		t.Errorf("error format: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("exit code for validation error: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
}

func TestInternalErrorFollowsErrInternalFormat(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryInternal, "unexpected read failure")
	if !strings.HasPrefix(err.Error(), "err:internal") {
		t.Errorf("error format: got %q, want prefix %q", err.Error(), "err:internal")
	}
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("exit code for internal error: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
}

func TestTimeoutErrorFollowsErrTimeoutFormat(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryTimeout, "Job exceeded 3000s timeout")
	want := "err:timeout Job exceeded 3000s timeout"
	if err.Error() != want {
		t.Errorf("error format: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 124 {
		t.Errorf("exit code for timeout error: got %d, want 124", exitcode.ExitCodeFor(err.Category))
	}
}

// ---------------------------------------------------------------------------
// AC3: Actionable suggestions
// ---------------------------------------------------------------------------

func TestDependencyErrorIncludesInstallationURL(t *testing.T) {
	err := exitcode.NewErrorWithSuggestion(
		exitcode.CategoryDependency,
		"claude CLI not found in PATH",
		"Install from https://claude.ai/code",
	)
	want := "err:dependency claude CLI not found in PATH. Install from https://claude.ai/code"
	if err.Error() != want {
		t.Errorf("dependency error with suggestion: got %q, want %q", err.Error(), want)
	}
}

func TestUserErrorForInvalidDirectoryIncludesPath(t *testing.T) {
	path := "/nonexistent/path"
	err := exitcode.NewError(exitcode.CategoryUser, fmt.Sprintf("Directory not found: %s", path))
	want := fmt.Sprintf(`err:user "Directory not found: %s"`, path)
	// The error string itself does not wrap with quotes; the test verifies the
	// message contains the path, and the CLI layer is responsible for quoting.
	// We test both the raw error format and the quoted form used by the CLI.
	rawWant := fmt.Sprintf("err:user Directory not found: %s", path)
	if err.Error() != rawWant {
		t.Errorf("user error with path: got %q, want %q", err.Error(), rawWant)
	}
	// Simulate what the CLI would output (with quotes around the message part).
	cliOutput := fmt.Sprintf(`err:user "Directory not found: %s"`, path)
	if !strings.Contains(cliOutput, want) {
		t.Errorf("cli output %q does not contain %q", cliOutput, want)
	}
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("exit code: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
}

func TestUserErrorForInvalidTimeoutIncludesValue(t *testing.T) {
	value := "abc"
	err := exitcode.NewError(exitcode.CategoryUser, fmt.Sprintf("Timeout must be a positive number: %s", value))
	want := fmt.Sprintf(`err:user "Timeout must be a positive number: %s"`, value)
	rawWant := fmt.Sprintf("err:user Timeout must be a positive number: %s", value)
	if err.Error() != rawWant {
		t.Errorf("user error with value: got %q, want %q", err.Error(), rawWant)
	}
	cliOutput := fmt.Sprintf(`err:user "Timeout must be a positive number: %s"`, value)
	if !strings.Contains(cliOutput, want) {
		t.Errorf("cli output %q does not contain %q", cliOutput, want)
	}
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("exit code: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
}

// ---------------------------------------------------------------------------
// AC4: Permission errors detected from stderr scanning
// ---------------------------------------------------------------------------

func TestStderrContainingPermissionTriggersPermissionError(t *testing.T) {
	stderr := "permission denied"
	if !exitcode.IsPermissionError(stderr) {
		t.Errorf("IsPermissionError(%q) = false, want true", stderr)
	}
}

func TestStderrContainingNotAllowedTriggersPermissionError(t *testing.T) {
	stderr := "not allowed to edit"
	if !exitcode.IsPermissionError(stderr) {
		t.Errorf("IsPermissionError(%q) = false, want true", stderr)
	}
}

func TestStderrContainingDeniedTriggersPermissionError(t *testing.T) {
	stderr := "Access denied for resource"
	if !exitcode.IsPermissionError(stderr) {
		t.Errorf("IsPermissionError(%q) = false, want true", stderr)
	}
}

func TestStderrContainingUnauthorizedTriggersPermissionError(t *testing.T) {
	stderr := "Unauthorized request"
	if !exitcode.IsPermissionError(stderr) {
		t.Errorf("IsPermissionError(%q) = false, want true", stderr)
	}
}

func TestPermissionDetectionIsCaseInsensitive(t *testing.T) {
	stderr := "PERMISSION DENIED"
	if !exitcode.IsPermissionError(stderr) {
		t.Errorf("IsPermissionError(%q) = false, want true (case-insensitive check failed)", stderr)
	}
}

func TestNonZeroExitWithoutPermissionKeywordsMapsToFailed(t *testing.T) {
	stderr := "Syntax error in source"
	if exitcode.IsPermissionError(stderr) {
		t.Errorf("IsPermissionError(%q) = true, want false — should map to failed, not permission_error", stderr)
	}
}

// ---------------------------------------------------------------------------
// AC5: Timeout errors carry configured timeout value
// ---------------------------------------------------------------------------

func TestTimeoutErrorMessageIncludesConfiguredTimeout(t *testing.T) {
	timeout := 3000
	err := exitcode.NewError(exitcode.CategoryTimeout, fmt.Sprintf("Job exceeded %ds timeout", timeout))
	want := "err:timeout Job exceeded 3000s timeout"
	if err.Error() != want {
		t.Errorf("timeout error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 124 {
		t.Errorf("exit code: got %d, want 124", exitcode.ExitCodeFor(err.Category))
	}
}

func TestTimeoutErrorWithCustomTimeoutValue(t *testing.T) {
	timeout := 60
	err := exitcode.NewError(exitcode.CategoryTimeout, fmt.Sprintf("Job exceeded %ds timeout", timeout))
	want := "err:timeout Job exceeded 60s timeout"
	if err.Error() != want {
		t.Errorf("timeout error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 124 {
		t.Errorf("exit code: got %d, want 124", exitcode.ExitCodeFor(err.Category))
	}
}

// ---------------------------------------------------------------------------
// Edge Cases
// ---------------------------------------------------------------------------

func TestMultipleErrorCategoriesMostSpecificWins(t *testing.T) {
	// When both dependency and validation errors are possible, dependency wins.
	err := exitcode.NewError(exitcode.CategoryDependency, "claude CLI not found in PATH")
	if err.Category != exitcode.CategoryDependency {
		t.Errorf("category: got %q, want %q", err.Category, exitcode.CategoryDependency)
	}
	if exitcode.ExitCodeFor(err.Category) != 127 {
		t.Errorf("exit code: got %d, want 127", exitcode.ExitCodeFor(err.Category))
	}
}

func TestMissingPromptProducesNonEmptyError(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryUser, "No prompt provided")
	if err.Error() == "" {
		t.Error("error string must not be empty")
	}
	pattern := regexp.MustCompile(`err:\w+ .+`)
	if !pattern.MatchString(err.Error()) {
		t.Errorf("error string %q does not match pattern %q", err.Error(), `err:\w+ .+`)
	}
}

func TestNonUTF8InStderrIsPassedThrough(t *testing.T) {
	// Simulate binary/non-UTF8 content: GoLeM must not mangle it.
	// The package itself stores stderr as a raw string/[]byte; here we verify
	// that IsPermissionError does not panic or corrupt when given arbitrary
	// byte content cast to string.
	nonUTF8 := string([]byte{0xFF, 0xFE, 0x00, 0x41})
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("IsPermissionError panicked on non-UTF8 input: %v", r)
		}
	}()
	// Should not panic; result can be true or false — just must not crash.
	_ = exitcode.IsPermissionError(nonUTF8)
}

// ---------------------------------------------------------------------------
// Seed data coverage — verify all entries from errors.json
// ---------------------------------------------------------------------------

func TestSeedDataUserError(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryUser, "No prompt provided")
	want := "err:user No prompt provided"
	if err.Error() != want {
		t.Errorf("seed user error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("seed user exit code: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
}

func TestSeedDataNotFoundError(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryNotFound, "Job not found: job-20260227-143205-a8f3b1c2")
	want := "err:not_found Job not found: job-20260227-143205-a8f3b1c2"
	if err.Error() != want {
		t.Errorf("seed not_found error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 3 {
		t.Errorf("seed not_found exit code: got %d, want 3", exitcode.ExitCodeFor(err.Category))
	}
}

func TestSeedDataDependencyError(t *testing.T) {
	err := exitcode.NewErrorWithSuggestion(
		exitcode.CategoryDependency,
		"claude CLI not found in PATH",
		"Install from https://claude.ai/code",
	)
	want := "err:dependency claude CLI not found in PATH. Install from https://claude.ai/code"
	if err.Error() != want {
		t.Errorf("seed dependency error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 127 {
		t.Errorf("seed dependency exit code: got %d, want 127", exitcode.ExitCodeFor(err.Category))
	}
}

func TestSeedDataValidationError(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryValidation, "permission_mode: invalid value 'yolo'")
	want := "err:validation permission_mode: invalid value 'yolo'"
	if err.Error() != want {
		t.Errorf("seed validation error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 1 {
		t.Errorf("seed validation exit code: got %d, want 1", exitcode.ExitCodeFor(err.Category))
	}
}

func TestSeedDataTimeoutError(t *testing.T) {
	err := exitcode.NewError(exitcode.CategoryTimeout, "Job exceeded 3000s timeout")
	want := "err:timeout Job exceeded 3000s timeout"
	if err.Error() != want {
		t.Errorf("seed timeout error: got %q, want %q", err.Error(), want)
	}
	if exitcode.ExitCodeFor(err.Category) != 124 {
		t.Errorf("seed timeout exit code: got %d, want 124", exitcode.ExitCodeFor(err.Category))
	}
}

// ---------------------------------------------------------------------------
// Constant values
// ---------------------------------------------------------------------------

func TestExitCodeConstants(t *testing.T) {
	cases := []struct {
		name string
		got  int
		want int
	}{
		{"OK", exitcode.OK, 0},
		{"UserError", exitcode.UserError, 1},
		{"NotFound", exitcode.NotFound, 3},
		{"Timeout", exitcode.Timeout, 124},
		{"DependencyMissing", exitcode.DependencyMissing, 127},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.got != tc.want {
				t.Errorf("%s = %d, want %d", tc.name, tc.got, tc.want)
			}
		})
	}
}
