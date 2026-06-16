package main

import (
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestDefaultAgentNameIsBase(t *testing.T) {
	name := defaultAgentName()
	// Base form "<dir>@<hostname>": one '@', no spaces, no per-agent '/' suffix.
	if strings.Count(name, "@") != 1 {
		t.Fatalf("want exactly one '@' in %q", name)
	}
	if strings.ContainsAny(name, " /") {
		t.Fatalf("base name must not contain a space or '/': %q", name)
	}
	if strings.HasSuffix(name, "@") || strings.HasPrefix(name, "@") {
		t.Fatalf("both sides of '@' must be non-empty: %q", name)
	}
}

func TestAgentHome(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("ORBIT_HOME", tmp)

	if got := rootDir(); got != tmp {
		t.Fatalf("rootDir = %q, want %q (ORBIT_HOME)", got, tmp)
	}
	if got := agentHome(""); got != tmp {
		t.Fatalf("agentHome(\"\") = %q, want rootDir %q", got, tmp)
	}
	if got, want := agentHome("claude"), filepath.Join(tmp, "claude"); got != want {
		t.Fatalf("agentHome(claude) = %q, want %q", got, want)
	}
}

func TestSaveLoadConfigAt(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "claude")
	in := &RunnerConfig{
		ServerURL: "https://example", RunnerID: "r1", RunnerToken: "tok",
		Name: "proj@host/claude", AgentKey: "claude", Agents: []string{"claude"},
	}
	if err := saveConfigAt(dir, in); err != nil {
		t.Fatal(err)
	}
	out := loadConfigAt(dir)
	if out == nil {
		t.Fatal("loadConfigAt returned nil")
	}
	if out.AgentKey != "claude" || out.Name != in.Name || out.RunnerID != "r1" {
		t.Fatalf("round-trip mismatch: %+v", out)
	}
}

func TestExistingConfigsFindsPerAgentAndLegacy(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("ORBIT_HOME", tmp)

	// A legacy single-runner config at the root, plus a per-agent config.
	if err := saveConfigAt(tmp, &RunnerConfig{Name: "legacy", RunnerID: "L"}); err != nil {
		t.Fatal(err)
	}
	if err := saveConfigAt(filepath.Join(tmp, "claude"), &RunnerConfig{Name: "proj@host/claude", AgentKey: "claude", RunnerID: "C"}); err != nil {
		t.Fatal(err)
	}

	got := existingConfigs()
	names := map[string]bool{}
	for _, c := range got {
		names[c.Name] = true
	}
	if !names["legacy"] || !names["proj@host/claude"] {
		t.Fatalf("existingConfigs missing entries: got %v", names)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 configs, got %d", len(got))
	}
}

func TestServiceNameAndLabel(t *testing.T) {
	cases := []struct{ key, svc, label string }{
		{"", "orbit-runner", "com.orbit.runner"},
		{"claude", "orbit-runner-claude", "com.orbit.runner.claude"},
		{"codex", "orbit-runner-codex", "com.orbit.runner.codex"},
	}
	for _, c := range cases {
		if got := serviceName(c.key); got != c.svc {
			t.Errorf("serviceName(%q) = %q, want %q", c.key, got, c.svc)
		}
		if got := launchdLabel(c.key); got != c.label {
			t.Errorf("launchdLabel(%q) = %q, want %q", c.key, got, c.label)
		}
	}
}

func TestMintedFromFallback(t *testing.T) {
	// When the server returns a runners list, use it verbatim.
	list := []MintedRunner{{AgentKey: "claude", RunnerID: "r1", RunnerToken: "t1", Name: "n/claude"}}
	if got := mintedFrom(list, "x", "y", "z"); !reflect.DeepEqual(got, list) {
		t.Fatalf("want server list, got %+v", got)
	}
	// Older server (no runners): synthesize a single runner from the legacy fields.
	got := mintedFrom(nil, "r1", "tok", "name")
	want := []MintedRunner{{RunnerID: "r1", RunnerToken: "tok", Name: "name"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("fallback mismatch: got %+v, want %+v", got, want)
	}
}
