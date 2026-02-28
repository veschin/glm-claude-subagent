package config

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

// Provider holds configuration for a single API provider.
type Provider struct {
	// Name is the provider key from the TOML [providers.X] section.
	Name string
	// BaseURL is the API base URL (ANTHROPIC_BASE_URL).
	BaseURL string
	// APIKeyFile is the path to the file containing the API key.
	// Tilde (~) expansion is performed at load time.
	APIKeyFile string
	// TimeoutMs is the request timeout in milliseconds as a string
	// (passed directly as API_TIMEOUT_MS).
	TimeoutMs string
	// Models maps slot names ("opus", "sonnet", "haiku") to model identifiers.
	Models map[string]string
}

// APIKey reads and returns the content of APIKeyFile, trimming whitespace.
// Returns an err:config error if the file is missing or unreadable.
func (p *Provider) APIKey() (string, error) {
	path := expandTilde(p.APIKeyFile)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("err:config \"Cannot read API key file for provider '%s': file not found\"", p.Name)
		}
		return "", fmt.Errorf("err:config \"Cannot read API key file for provider '%s': %s\"", p.Name, err.Error())
	}
	return strings.TrimSpace(string(data)), nil
}

// ProviderConfig holds the provider sections parsed from glm.toml.
type ProviderConfig struct {
	// DefaultProvider is the name of the default provider from default_provider key.
	DefaultProvider string
	// Providers maps provider names to their Provider structs.
	Providers map[string]*Provider
}

// HardcodedZAIDefaults returns a ProviderConfig containing only the built-in
// Z.AI defaults, used when no [providers.*] sections appear in glm.toml.
func HardcodedZAIDefaults() *ProviderConfig {
	return &ProviderConfig{
		DefaultProvider: "zai",
		Providers: map[string]*Provider{
			"zai": {
				Name:       "zai",
				BaseURL:    ZaiBaseURL,
				APIKeyFile: "~/.config/GoLeM/zai_api_key",
				TimeoutMs:  ZaiAPITimeoutMs,
				Models: map[string]string{
					"opus":   DefaultModel,
					"sonnet": DefaultModel,
					"haiku":  DefaultModel,
				},
			},
		},
	}
}

// LoadProvider parses the TOML data from configDir/glm.toml and returns the
// named provider. If providerName is empty, the default_provider value from
// the TOML (or "zai" hardcoded) is used. If no providers sections are defined,
// HardcodedZAIDefaults is returned.
//
// Returns err:user if the named provider does not exist.
// Returns err:config if the provider's APIKeyFile cannot be read.
func LoadProvider(configDir, providerName string) (*Provider, error) {
	tomlPath := configDir + "/glm.toml"
	data, err := os.ReadFile(tomlPath)
	if err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("err:config \"Cannot read glm.toml: %s\"", err.Error())
	}

	pc, err := ParseProviderConfig(data)
	if err != nil {
		return nil, err
	}

	// Determine which provider to use
	name := providerName
	if name == "" {
		name = pc.DefaultProvider
	}

	p, ok := pc.Providers[name]
	if !ok {
		return nil, fmt.Errorf("err:user provider %q not found", name)
	}

	return p, nil
}

// ListProviders parses glm.toml from configDir and returns all defined
// provider names in sorted order. If no providers are configured, returns
// ["zai"] (the hardcoded default).
func ListProviders(configDir string) ([]string, error) {
	tomlPath := configDir + "/glm.toml"
	data, err := os.ReadFile(tomlPath)
	if err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("err:config \"Cannot read glm.toml: %s\"", err.Error())
	}

	pc, err := ParseProviderConfig(data)
	if err != nil {
		return nil, err
	}

	names := make([]string, 0, len(pc.Providers))
	for name := range pc.Providers {
		names = append(names, name)
	}
	sort.Strings(names)

	return names, nil
}

// ParseProviderConfig parses the [providers.*] sections from raw TOML bytes.
// Returns a ProviderConfig. If no providers are found, returns
// HardcodedZAIDefaults.
func ParseProviderConfig(data []byte) (*ProviderConfig, error) {
	content := string(data)
	lines := strings.Split(content, "\n")

	pc := &ProviderConfig{
		DefaultProvider: "zai",
		Providers:       make(map[string]*Provider),
	}

	currentProvider := ""
	var current *Provider

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Check for default_provider = "value"
		if strings.HasPrefix(line, "default_provider") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				val := strings.TrimSpace(strings.Trim(parts[1], `"'`))
				pc.DefaultProvider = val
			}
			continue
		}

		// Check for [providers.name] section header
		if strings.HasPrefix(line, "[providers.") {
			// Save previous provider if exists
			if current != nil && currentProvider != "" {
				pc.Providers[currentProvider] = current
			}

			// Parse new provider name
			line = strings.TrimPrefix(line, "[providers.")
			line = strings.TrimSuffix(line, "]")
			currentProvider = strings.TrimSpace(line)
			current = &Provider{
				Name:       currentProvider,
				BaseURL:    ZaiBaseURL,
				APIKeyFile: "~/.config/GoLeM/zai_api_key",
				TimeoutMs:  ZaiAPITimeoutMs,
				Models: map[string]string{
					"opus":   DefaultModel,
					"sonnet": DefaultModel,
					"haiku":  DefaultModel,
				},
			}
			continue
		}

		// Check for other [section] headers - reset current provider
		if strings.HasPrefix(line, "[") {
			if current != nil && currentProvider != "" {
				pc.Providers[currentProvider] = current
				current = nil
				currentProvider = ""
			}
			continue
		}

		// Parse key = value within a provider section
		if current != nil {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				key := strings.TrimSpace(parts[0])
				value := strings.TrimSpace(strings.Trim(parts[1], `"'`))

				switch key {
				case "base_url":
					current.BaseURL = value
				case "api_key_file":
					current.APIKeyFile = value
				case "timeout_ms":
					current.TimeoutMs = value
				case "opus_model":
					current.Models["opus"] = value
				case "sonnet_model":
					current.Models["sonnet"] = value
				case "haiku_model":
					current.Models["haiku"] = value
				}
			}
		}
	}

	// Save last provider
	if current != nil && currentProvider != "" {
		pc.Providers[currentProvider] = current
	}

	// If no providers found, use hardcoded defaults
	if len(pc.Providers) == 0 {
		return HardcodedZAIDefaults(), nil
	}

	return pc, nil
}

// ResolveModelEnv returns the environment variable map for the given provider,
// applying optional model overrides. Keys are environment variable names;
// values are the strings to set.
//
//   - ANTHROPIC_BASE_URL  ← p.BaseURL
//   - API_TIMEOUT_MS      ← p.TimeoutMs
//   - ANTHROPIC_AUTH_TOKEN ← apiKey (read from p.APIKeyFile)
//   - ANTHROPIC_DEFAULT_OPUS_MODEL   ← p.Models["opus"]   or override
//   - ANTHROPIC_DEFAULT_SONNET_MODEL ← p.Models["sonnet"] or override
//   - ANTHROPIC_DEFAULT_HAIKU_MODEL  ← p.Models["haiku"]  or override
//
// modelOverride, if non-empty, overrides all three model slots.
// opusOverride, sonnetOverride, haikuOverride override individual slots.
func ResolveModelEnv(p *Provider, apiKey, modelOverride, opusOverride, sonnetOverride, haikuOverride string) map[string]string {
	env := make(map[string]string)

	env["ANTHROPIC_BASE_URL"] = p.BaseURL
	env["API_TIMEOUT_MS"] = p.TimeoutMs
	env["ANTHROPIC_AUTH_TOKEN"] = apiKey

	// Determine model values
	opusModel := p.Models["opus"]
	sonnetModel := p.Models["sonnet"]
	haikuModel := p.Models["haiku"]

	if modelOverride != "" {
		opusModel = modelOverride
		sonnetModel = modelOverride
		haikuModel = modelOverride
	}

	if opusOverride != "" {
		opusModel = opusOverride
	}
	if sonnetOverride != "" {
		sonnetModel = sonnetOverride
	}
	if haikuOverride != "" {
		haikuModel = haikuOverride
	}

	env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = opusModel
	env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = sonnetModel
	env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = haikuModel

	return env
}

// expandTilde replaces a leading "~/" or "~" with the user's home directory.
func expandTilde(path string) string {
	if path == "~" {
		home, _ := os.UserHomeDir()
		return home
	}
	if strings.HasPrefix(path, "~/") {
		home, _ := os.UserHomeDir()
		return home + path[1:]
	}
	return path
}
