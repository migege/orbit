package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync/atomic"
	"time"
)

// The runner surfaces local coding-runtime quota so the UI can display per-runner
// plan usage. Claude uses the OAuth usage endpoint Claude Code itself calls; Codex
// uses the app-server account/rateLimits/read protocol method. Both are best-effort:
// failures degrade to "no usage reported" and never disturb the heartbeat.

const (
	planUsageURL = "https://api.anthropic.com/api/oauth/usage"
	// While the runner has ≥1 active session, refresh at most this often. Quota only
	// moves while claude is running, so a fully idle runner isn't polled at all.
	planUsageInterval = 2 * time.Minute
	// Local (no-network) cadence for checking busy/idle edges and refresh-due. Cheap:
	// it just reads an in-process counter.
	planUsageCheckInterval = 15 * time.Second
	// anthropic-beta value Claude Code sends on OAuth-authenticated requests. The
	// endpoint accepts the token without it today; we send it to match the CLI in
	// case the header is enforced later. If Anthropic rotates it, the request 4xx's
	// and we degrade gracefully rather than break.
	planUsageBeta = "oauth-2025-04-20"
)

// PlanUsageWindow is one rate-limit window. Claude reports named windows (rolling
// 5-hour / weekly); Codex reports primary/secondary windows with durations.
// Mirrors @orbit/shared PlanUsageWindow.
type PlanUsageWindow struct {
	Utilization        float64 `json:"utilization"`                  // 0..100 percent consumed
	ResetsAt           string  `json:"resetsAt,omitempty"`           // ISO-8601 reset time, if known
	Label              string  `json:"label,omitempty"`              // UI label for dynamic Codex windows
	WindowDurationMins int64   `json:"windowDurationMins,omitempty"` // Codex-reported rolling window size
}

type CreditsSnapshot struct {
	HasCredits bool   `json:"hasCredits"`
	Unlimited  bool   `json:"unlimited"`
	Balance    string `json:"balance,omitempty"`
}

// PlanUsage is a provider usage snapshot. For compatibility, a single-provider
// heartbeat can still be flat; when the runner has multiple providers active, Claude
// and Codex snapshots are nested under claude/codex.
type PlanUsage struct {
	Provider string `json:"provider,omitempty"`

	// Claude windows.
	FiveHour       *PlanUsageWindow `json:"fiveHour,omitempty"`
	SevenDay       *PlanUsageWindow `json:"sevenDay,omitempty"`
	SevenDayOpus   *PlanUsageWindow `json:"sevenDayOpus,omitempty"`
	SevenDaySonnet *PlanUsageWindow `json:"sevenDaySonnet,omitempty"`

	// Codex windows, from app-server account/rateLimits/read.
	Primary              *PlanUsageWindow `json:"primary,omitempty"`
	Secondary            *PlanUsageWindow `json:"secondary,omitempty"`
	LimitID              string           `json:"limitId,omitempty"`
	LimitName            string           `json:"limitName,omitempty"`
	PlanType             string           `json:"planType,omitempty"`
	RateLimitReachedType string           `json:"rateLimitReachedType,omitempty"`
	Credits              *CreditsSnapshot `json:"credits,omitempty"`

	// Nested snapshots when more than one provider is available.
	Claude *PlanUsage `json:"claude,omitempty"`
	Codex  *PlanUsage `json:"codex,omitempty"`

	FetchedAt string `json:"fetchedAt,omitempty"`
}

type planUsageFetchFunc func(context.Context, *http.Client) (*PlanUsage, error)

// planUsageProbe keeps the most recent usage snapshot fresh in the background so the
// heartbeat reads it instantly (lock-free) and is never delayed by the external call.
type planUsageProbe struct {
	client *http.Client
	name   string
	fetch  planUsageFetchFunc
	val    atomic.Value // *PlanUsage; unset until the first successful fetch
}

func newClaudePlanUsageProbe() *planUsageProbe {
	return &planUsageProbe{client: &http.Client{}, name: "claude plan-usage", fetch: fetchClaudePlanUsage}
}

func newCodexPlanUsageProbe() *planUsageProbe {
	return &planUsageProbe{client: &http.Client{}, name: "codex plan-usage", fetch: fetchCodexPlanUsage}
}

// snapshot returns the latest usage, or nil if none has been fetched / it's
// unavailable. Safe to call from the heartbeat goroutine.
func (p *planUsageProbe) snapshot() *PlanUsage {
	v, _ := p.val.Load().(*PlanUsage)
	return v
}

// run polls the usage endpoint only while the runner is busy: it refreshes on the
// idle→busy edge (so the gauge is fresh when work starts), every planUsageInterval
// while sessions run, and once more on the busy→idle edge (to capture the just-
// finished turn's usage). A fully idle runner makes no request — quota only moves
// while claude runs. activeCount reports how many sessions are currently running.
// Failures are soft (see fetchPlanUsage): the last good value is kept and a repeated
// error is logged only once.
func (p *planUsageProbe) run(ctx context.Context, activeCount func() int) {
	var lastErr string
	var lastFetch time.Time
	refresh := func() {
		lastFetch = time.Now()
		u, err := p.fetch(ctx, p.client)
		if err != nil {
			if msg := err.Error(); msg != lastErr {
				logln(p.name+" unavailable:", msg)
				lastErr = msg
			}
			return
		}
		if lastErr != "" {
			logln(p.name + " recovered")
			lastErr = ""
		}
		p.val.Store(u)
	}
	wasActive := false
	ticker := time.NewTicker(planUsageCheckInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			active := activeCount() > 0
			// Refresh on a busy/idle transition (fresh on start, final capture on
			// finish), or when a busy runner is due for its periodic poll.
			if active != wasActive || (active && time.Since(lastFetch) >= planUsageInterval) {
				refresh()
			}
			wasActive = active
		}
	}
}

// claudeCredentialsPath resolves where Claude Code stores OAuth creds, honoring
// CLAUDE_CONFIG_DIR (which the CLI itself respects) and otherwise ~/.claude — the
// same HOME the runner spawns claude under, so the token always matches.
func claudeCredentialsPath() string {
	dir := os.Getenv("CLAUDE_CONFIG_DIR")
	if dir == "" {
		dir = filepath.Join(userHome(), ".claude")
	}
	return filepath.Join(dir, ".credentials.json")
}

func claudeOAuthToken() (string, error) {
	b, err := claudeCredentialsJSON()
	if err != nil {
		return "", err
	}
	var c struct {
		ClaudeAiOauth struct {
			AccessToken string `json:"accessToken"`
		} `json:"claudeAiOauth"`
	}
	if err := json.Unmarshal(b, &c); err != nil {
		return "", err
	}
	if c.ClaudeAiOauth.AccessToken == "" {
		return "", fmt.Errorf("no oauth token (api-key auth?)")
	}
	return c.ClaudeAiOauth.AccessToken, nil
}

// claudeCredentialsJSON returns the raw {"claudeAiOauth":{...}} blob Claude Code
// stores. On Linux that's the .credentials.json file; on macOS the CLI keeps it in
// the login Keychain instead, leaving no file — so fall back to the Keychain when the
// file read fails. The original file error is preserved when the fallback also fails,
// so the logged reason stays accurate on non-mac hosts.
func claudeCredentialsJSON() ([]byte, error) {
	b, err := os.ReadFile(claudeCredentialsPath())
	if err == nil {
		return b, nil
	}
	if runtime.GOOS == "darwin" {
		if kb, kerr := keychainCredentials(); kerr == nil {
			return kb, nil
		}
	}
	return nil, err
}

// keychainCredentials reads Claude Code's OAuth credentials from the macOS login
// Keychain (item "Claude Code-credentials"), where the CLI stores them on darwin. The
// first read from the runner triggers a one-time Keychain access prompt; choosing
// "Always Allow" makes subsequent reads silent.
func keychainCredentials() ([]byte, error) {
	out, err := exec.Command("security", "find-generic-password", "-s", "Claude Code-credentials", "-w").Output()
	if err != nil {
		return nil, err
	}
	return out, nil
}

func fetchClaudePlanUsage(ctx context.Context, client *http.Client) (*PlanUsage, error) {
	// Read the token fresh every cycle: Claude Code rotates it in place, so a cached
	// token would go stale. A 401 here just means we'll pick up the refreshed one next.
	token, err := claudeOAuthToken()
	if err != nil {
		return nil, err
	}
	cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(cctx, http.MethodGet, planUsageURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("authorization", "Bearer "+token)
	req.Header.Set("anthropic-beta", planUsageBeta)
	req.Header.Set("accept", "application/json")
	req.Header.Set("user-agent", "orbit-runner/"+version)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("usage endpoint -> %d", resp.StatusCode)
	}
	return parsePlanUsage(body)
}

// parsePlanUsage maps the endpoint's snake_case windows to our compact shape. Each
// window is a pointer so a JSON null (e.g. seven_day_opus on plans without it) or a
// missing utilization collapses to an omitted field rather than a bogus 0%.
func parsePlanUsage(body []byte) (*PlanUsage, error) {
	type rawWindow struct {
		Utilization *float64 `json:"utilization"`
		ResetsAt    *string  `json:"resets_at"`
	}
	norm := func(r *rawWindow) *PlanUsageWindow {
		if r == nil || r.Utilization == nil {
			return nil
		}
		w := &PlanUsageWindow{Utilization: *r.Utilization}
		if r.ResetsAt != nil {
			w.ResetsAt = *r.ResetsAt
		}
		return w
	}
	var raw struct {
		FiveHour       *rawWindow `json:"five_hour"`
		SevenDay       *rawWindow `json:"seven_day"`
		SevenDayOpus   *rawWindow `json:"seven_day_opus"`
		SevenDaySonnet *rawWindow `json:"seven_day_sonnet"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, err
	}
	return &PlanUsage{
		Provider:       providerClaude,
		FiveHour:       norm(raw.FiveHour),
		SevenDay:       norm(raw.SevenDay),
		SevenDayOpus:   norm(raw.SevenDayOpus),
		SevenDaySonnet: norm(raw.SevenDaySonnet),
		FetchedAt:      time.Now().UTC().Format(time.RFC3339),
	}, nil
}

func fetchCodexPlanUsage(ctx context.Context, _ *http.Client) (*PlanUsage, error) {
	cctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	app, err := startCodexUsageAppServer(cctx)
	if err != nil {
		return nil, err
	}
	defer app.close()
	if err := app.initialize(cctx); err != nil {
		return nil, err
	}
	result, err := app.request(cctx, "account/rateLimits/read", nil)
	if err != nil {
		return nil, err
	}
	return parseCodexPlanUsage(result)
}

func startCodexUsageAppServer(ctx context.Context) (*codexAppServer, error) {
	procCtx, cancel := context.WithCancel(ctx)
	stateDir := filepath.Join(os.TempDir(), "orbit-codex-usage-state")
	_ = os.MkdirAll(stateDir, 0o700)
	args := []string{"app-server", "--stdio", "-c", fmt.Sprintf("sqlite_home=%q", stateDir)}
	cmd := exec.CommandContext(procCtx, "codex", args...)
	if cwd, err := os.Getwd(); err == nil {
		cmd.Dir = cwd
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		cancel()
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		cancel()
		return nil, err
	}
	app := &codexAppServer{
		cmd:           cmd,
		cancel:        cancel,
		stdin:         stdin,
		pending:       map[string]chan codexRPCMessage{},
		notifications: make(chan codexRPCMessage, 16),
		done:          make(chan struct{}),
	}
	if err := cmd.Start(); err != nil {
		cancel()
		return nil, err
	}
	go app.readLoop(stdout)
	go func() {
		_, _ = io.Copy(io.Discard, stderr)
	}()
	return app, nil
}

func parseCodexPlanUsage(result map[string]interface{}) (*PlanUsage, error) {
	limits := mapValue(result["rateLimitsByLimitId"])
	var snap map[string]interface{}
	if limits != nil {
		snap = mapValue(limits["codex"])
	}
	if snap == nil {
		snap = mapValue(result["rateLimits"])
	}
	if snap == nil {
		return nil, fmt.Errorf("rateLimits response missing codex snapshot")
	}
	u := &PlanUsage{
		Provider:             providerCodex,
		LimitID:              firstString(snap, "limitId", "limit_id"),
		LimitName:            firstString(snap, "limitName", "limit_name"),
		PlanType:             firstString(snap, "planType", "plan_type"),
		RateLimitReachedType: firstString(snap, "rateLimitReachedType", "rate_limit_reached_type"),
		Primary:              codexRateLimitWindow("Primary", mapValue(snap["primary"])),
		Secondary:            codexRateLimitWindow("Secondary", mapValue(snap["secondary"])),
		Credits:              codexCreditsSnapshot(mapValue(snap["credits"])),
		FetchedAt:            time.Now().UTC().Format(time.RFC3339),
	}
	return u, nil
}

func codexRateLimitWindow(role string, raw map[string]interface{}) *PlanUsageWindow {
	if raw == nil {
		return nil
	}
	used, ok := numberValue(firstPresent(raw, "usedPercent", "used_percent"))
	if !ok {
		return nil
	}
	mins, _ := int64Value(firstPresent(raw, "windowDurationMins", "window_duration_mins"))
	reset, _ := int64Value(firstPresent(raw, "resetsAt", "resets_at"))
	w := &PlanUsageWindow{
		Utilization:        used,
		Label:              codexWindowLabel(role, mins),
		WindowDurationMins: mins,
	}
	if reset > 0 {
		w.ResetsAt = time.Unix(reset, 0).UTC().Format(time.RFC3339)
	}
	return w
}

func codexWindowLabel(role string, mins int64) string {
	switch mins {
	case 300:
		return "5-hour limit"
	case 1440:
		return "Daily limit"
	case 10080:
		return "Weekly limit"
	}
	if mins > 0 && mins%60 == 0 {
		hours := mins / 60
		if hours == 1 {
			return role + " · 1-hour limit"
		}
		return fmt.Sprintf("%s · %d-hour limit", role, hours)
	}
	if mins > 0 {
		return fmt.Sprintf("%s · %d-min limit", role, mins)
	}
	return role + " limit"
}

func codexCreditsSnapshot(raw map[string]interface{}) *CreditsSnapshot {
	if raw == nil {
		return nil
	}
	has, okHas := boolValue(raw["hasCredits"])
	unlimited, okUnlimited := boolValue(raw["unlimited"])
	if !okHas && !okUnlimited {
		return nil
	}
	return &CreditsSnapshot{
		HasCredits: has,
		Unlimited:  unlimited,
		Balance:    firstString(raw, "balance"),
	}
}

func combinePlanUsage(claude, codex *PlanUsage) *PlanUsage {
	if claude == nil {
		return codex
	}
	if codex == nil {
		return claude
	}
	fetchedAt := claude.FetchedAt
	if codex.FetchedAt > fetchedAt {
		fetchedAt = codex.FetchedAt
	}
	return &PlanUsage{Claude: claude, Codex: codex, FetchedAt: fetchedAt}
}

func numberValue(v interface{}) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case float32:
		return float64(n), true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	case json.Number:
		f, err := n.Float64()
		return f, err == nil
	default:
		return 0, false
	}
}

func int64Value(v interface{}) (int64, bool) {
	switch n := v.(type) {
	case float64:
		return int64(n), true
	case float32:
		return int64(n), true
	case int:
		return int64(n), true
	case int64:
		return n, true
	case json.Number:
		i, err := n.Int64()
		if err == nil {
			return i, true
		}
		f, ferr := n.Float64()
		return int64(f), ferr == nil
	default:
		return 0, false
	}
}

func boolValue(v interface{}) (bool, bool) {
	b, ok := v.(bool)
	return b, ok
}
