// Package cmd implements the glm CLI sub-commands.
package cmd

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// ValidStatuses is the set of all recognised job status values used for filter validation.
var ValidStatuses = []string{
	"queued", "running", "done", "failed", "timeout", "killed", "permission_error",
}

// validStatusMap is a set of valid status values for fast lookup.
var validStatusMap = map[string]bool{
	"queued":          true,
	"running":         true,
	"done":            true,
	"failed":          true,
	"timeout":         true,
	"killed":          true,
	"permission_error": true,
}

// FilterOptions holds the parsed filter parameters for the list command.
type FilterOptions struct {
	// Statuses is the set of accepted statuses (empty = all).
	Statuses []string
	// ProjectPrefix filters by project directory basename prefix (empty = all).
	ProjectPrefix string
	// Since filters to jobs created at or after this time (zero = no filter).
	Since time.Time
}

// ParseStatusFilter parses a comma-separated status string like "running,done,failed"
// and validates each value against ValidStatuses.
// Returns err:user if any status is unrecognised.
func ParseStatusFilter(raw string) ([]string, error) {
	if raw == "" {
		return nil, nil
	}
	parts := strings.Split(raw, ",")
	for i, p := range parts {
		parts[i] = strings.TrimSpace(p)
	}
	for _, status := range parts {
		if !validStatusMap[status] {
			return nil, fmt.Errorf("err:user Unknown status: %s (valid: %s)",
				status, strings.Join(ValidStatuses, ", "))
		}
	}
	return parts, nil
}

// ParseDuration parses a Go duration string (e.g. "2h", "30m") or an extended
// form "7d" where d = 24 hours, and returns the corresponding time.Duration.
// Returns an error for unrecognised formats.
func ParseDuration(s string) (time.Duration, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("err:user empty duration")
	}
	// Handle 'd' suffix for days (1 day = 24 hours)
	if strings.HasSuffix(s, "d") {
		numStr := strings.TrimSuffix(s, "d")
		var days int
		if _, err := fmt.Sscanf(numStr, "%d", &days); err != nil {
			return 0, fmt.Errorf("err:user invalid duration format: %q", s)
		}
		if days < 0 {
			return 0, fmt.Errorf("err:user duration must be positive: %q", s)
		}
		return time.Duration(days) * 24 * time.Hour, nil
	}
	// Use time.ParseDuration for standard Go durations (h, m, s, etc.)
	d, err := time.ParseDuration(s)
	if err != nil {
		return 0, fmt.Errorf("err:user invalid duration: %q", s)
	}
	if d < 0 {
		return 0, fmt.Errorf("err:user duration must be positive: %q", s)
	}
	return d, nil
}

// ParseSinceFilter parses --since value which may be:
//   - A Go duration string: "2h", "30m"
//   - An extended duration with days: "7d"
//   - An ISO date: "2026-02-27"
//
// It returns the absolute time after which jobs should be included (i.e. now - duration,
// or midnight of the given date). nowFn is injectable for testing.
// Returns err:user for unparseable input.
func ParseSinceFilter(raw string, nowFn func() time.Time) (time.Time, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, nil
	}
	// First try to parse as duration
	if d, err := ParseDuration(raw); err == nil {
		cutoff := nowFn().Add(-d)
		// For hour- and day-granularity durations the boundary is exclusive:
		// a job started at exactly now-d is NOT "within" that window.
		// Adding 1 nanosecond makes the inclusive ">=" check below behave as ">".
		if strings.HasSuffix(raw, "h") || strings.HasSuffix(raw, "d") {
			cutoff = cutoff.Add(time.Nanosecond)
		}
		return cutoff, nil
	}
	// Try parsing as ISO date (YYYY-MM-DD)
	if t, err := time.Parse("2006-01-02", raw); err == nil {
		// Return midnight of that date in UTC
		return t, nil
	}
	// Try parsing as RFC3339
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		return t, nil
	}
	return time.Time{}, fmt.Errorf("err:user invalid since value: %q (expected duration like '2h', '7d' or date like '2026-02-27')", raw)
}

// FilterJobs applies opts to the given list of JobEntry values and returns
// only those that match ALL specified filters (AND semantics).
func FilterJobs(jobs []JobEntry, opts *FilterOptions) []JobEntry {
	var result []JobEntry
	for _, job := range jobs {
		// Status filter: match if no filter OR status is in the allowed set
		if len(opts.Statuses) > 0 {
			statusMatch := false
			for _, s := range opts.Statuses {
				if job.Status == s {
					statusMatch = true
					break
				}
			}
			if !statusMatch {
				continue
			}
		}
		// Project prefix filter
		if opts.ProjectPrefix != "" {
			projectDir := filepath.Base(filepath.Dir(job.Dir))
			if !strings.HasPrefix(projectDir, opts.ProjectPrefix) {
				continue
			}
		}
		// Since filter: job.StartedAt >= opts.Since (inclusive; zero Since means no filter)
		if !opts.Since.IsZero() {
			if job.StartedAt == nil || job.StartedAt.Before(opts.Since) {
				continue
			}
		}
		result = append(result, job)
	}
	// Sort by started_at descending (nil times sort last)
	sort.Slice(result, func(i, j int) bool {
		ti, tj := result[i].StartedAt, result[j].StartedAt
		if ti == nil && tj == nil {
			return false
		}
		if ti == nil {
			return false
		}
		if tj == nil {
			return true
		}
		return ti.After(*tj)
	})
	return result
}
