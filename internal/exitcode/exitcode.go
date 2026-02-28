package exitcode

import (
	"fmt"
	"strings"
)

// Exit code constants.
const (
	OK                = 0
	UserError         = 1
	NotFound          = 3
	Timeout           = 124
	DependencyMissing = 127
)

// Category represents the type of error.
type Category string

const (
	CategoryUser       Category = "user"
	CategoryNotFound   Category = "not_found"
	CategoryDependency Category = "dependency"
	CategoryValidation Category = "validation"
	CategoryInternal   Category = "internal"
	CategoryTimeout    Category = "timeout"
)

// Error is a typed error that carries a category and an optional suggestion.
type Error struct {
	Category   Category
	Message    string
	Suggestion string
}

// Error returns the formatted error string "err:{category} {message}" and
// appends ". {suggestion}" when a suggestion is present.
func (e *Error) Error() string {
	s := fmt.Sprintf("err:%s %s", e.Category, e.Message)
	if e.Suggestion != "" {
		s += ". " + e.Suggestion
	}
	return s
}

// NewError constructs an Error with the given category and message.
func NewError(category Category, message string) *Error {
	return &Error{Category: category, Message: message}
}

// NewErrorWithSuggestion constructs an Error with a suggestion appended.
func NewErrorWithSuggestion(category Category, message, suggestion string) *Error {
	return &Error{Category: category, Message: message, Suggestion: suggestion}
}

// permissionKeywords contains the case-insensitive substrings that indicate a
// permission-related failure in subprocess stderr output.
var permissionKeywords = []string{
	"permission",
	"not allowed",
	"denied",
	"unauthorized",
}

// IsPermissionError reports whether the given stderr string contains any of the
// known permission-related keywords (comparison is case-insensitive).
func IsPermissionError(stderr string) bool {
	lower := strings.ToLower(stderr)
	for _, kw := range permissionKeywords {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	return false
}

// ExitCodeFor returns the numeric exit code that corresponds to a Category.
func ExitCodeFor(c Category) int {
	switch c {
	case CategoryUser, CategoryValidation, CategoryInternal:
		return UserError
	case CategoryNotFound:
		return NotFound
	case CategoryTimeout:
		return Timeout
	case CategoryDependency:
		return DependencyMissing
	default:
		return UserError
	}
}
