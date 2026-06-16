package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// RunnerConfig is the persisted credential + identity for one runner.
type RunnerConfig struct {
	ServerURL     string   `json:"serverUrl"`
	RunnerID      string   `json:"runnerId"`
	RunnerToken   string   `json:"runnerToken"`
	Name          string   `json:"name"`
	Labels        []string `json:"labels"`
	MaxConcurrent int      `json:"maxConcurrent"`
	// Directory Claude Code runs in (the project to work on). Defaults to the cwd
	// at `orbit register`; jobs cd here, not into a per-run scratch dir.
	WorkDir string `json:"workDir,omitempty"`
	// AgentKey is the single agent this runner drives (e.g. "claude"); empty for
	// legacy single-runner installs. It selects the per-agent home + service name.
	AgentKey string `json:"agentKey,omitempty"`
	// Agents the user chose to register (stable keys). One key per config now that
	// each agent is its own runner; kept as a list for backward compatibility.
	Agents []string `json:"agents,omitempty"`
}

// rootDir is the `.orbit` container in the current directory (or $ORBIT_HOME).
// Each agent's runner home lives under it at <rootDir>/<agentKey>.
func rootDir() string {
	if h := os.Getenv("ORBIT_HOME"); h != "" {
		return h
	}
	cwd, err := os.Getwd()
	if err != nil {
		cwd = "."
	}
	return filepath.Join(cwd, ".orbit")
}

// agentHome is the ORBIT_HOME for one agent's runner: <rootDir>/<agentKey>. An
// empty key returns rootDir itself (legacy single-runner layout).
func agentHome(key string) string {
	if key == "" {
		return rootDir()
	}
	return filepath.Join(rootDir(), key)
}

// baseDir is the ORBIT_HOME this process reads/writes its own config + runs in.
// The systemd unit / launchd plist set ORBIT_HOME to a per-agent home, so each
// runner process keys off its own directory.
func baseDir() string    { return rootDir() }
func configPath() string { return filepath.Join(baseDir(), "config.json") }
func runsDir() string    { return filepath.Join(baseDir(), "runs") }

func loadConfig() *RunnerConfig        { return loadConfigAt(baseDir()) }
func saveConfig(c *RunnerConfig) error { return saveConfigAt(baseDir(), c) }

func loadConfigAt(dir string) *RunnerConfig {
	b, err := os.ReadFile(filepath.Join(dir, "config.json"))
	if err != nil {
		return nil
	}
	var c RunnerConfig
	if json.Unmarshal(b, &c) != nil {
		return nil
	}
	return &c
}

func saveConfigAt(dir string, c *RunnerConfig) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(c, "", "  ")
	return os.WriteFile(filepath.Join(dir, "config.json"), b, 0o644)
}

// existingConfigs returns every runner config registered in this directory: the
// per-agent homes (<rootDir>/<key>/config.json) plus a legacy <rootDir>/config.json
// from a pre-fan-out install. Used by status/unregister and the manual `run` fallback.
func existingConfigs() []*RunnerConfig {
	var out []*RunnerConfig
	if c := loadConfigAt(rootDir()); c != nil { // legacy single-runner layout
		out = append(out, c)
	}
	entries, err := os.ReadDir(rootDir())
	if err != nil {
		return out
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if c := loadConfigAt(filepath.Join(rootDir(), e.Name())); c != nil {
			out = append(out, c)
		}
	}
	return out
}
