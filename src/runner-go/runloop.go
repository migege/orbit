package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

const heartbeatInterval = 30 * time.Second

// PreflightResult mirrors the TS preflight contract.
type PreflightResult struct {
	OK      bool
	Message string
}

var unauthRe = regexp.MustCompile(`not.*(logged|authenticat)|unauthenticated|run .*login|please log in`)

// preflightClaudeAuth verifies the runner can authenticate to Claude before
// accepting jobs. Set ORBIT_SKIP_PREFLIGHT=1 to bypass.
func preflightClaudeAuth() PreflightResult {
	if os.Getenv("ORBIT_SKIP_PREFLIGHT") != "" {
		return PreflightResult{true, "preflight skipped (ORBIT_SKIP_PREFLIGHT)"}
	}
	if hasExplicitClaudeAuth() {
		return PreflightResult{true, "auth via env (ANTHROPIC_API_KEY / OAuth token)"}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "claude", "auth", "status").CombinedOutput()
	if err == nil {
		return PreflightResult{true, "Claude Code is logged in (subscription)"}
	}
	var execErr *exec.Error
	if errors.As(err, &execErr) {
		return PreflightResult{false,
			"Claude Code (`claude`) was not found on PATH. Install Claude Code and run `claude` then `/login`."}
	}
	if unauthRe.MatchString(strings.ToLower(string(out))) {
		return PreflightResult{false,
			"Claude Code is not logged in. Run `claude` then `/login` (uses your Claude subscription)."}
	}
	return PreflightResult{true, "could not verify Claude Code auth via `claude auth status`; proceeding"}
}

func runLoop(cfg *RunnerConfig) {
	t := NewTransport(cfg.ServerURL, cfg.RunnerToken)

	var mu sync.Mutex
	active := map[string]context.CancelFunc{}

	loopCtx, loopCancel := context.WithCancel(context.Background())
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; loopCancel() }()

	// Heartbeat every 30s; honor server-requested cancellations.
	hbStop := make(chan struct{})
	go func() {
		ticker := time.NewTicker(heartbeatInterval)
		defer ticker.Stop()
		for {
			select {
			case <-hbStop:
				return
			case <-ticker.C:
				mu.Lock()
				idle := cfg.MaxConcurrent - len(active)
				cancels := make(map[string]context.CancelFunc, len(active))
				for k, v := range active {
					cancels[k] = v
				}
				mu.Unlock()
				if idle < 0 {
					idle = 0
				}
				resp, err := t.heartbeat(HeartbeatRequest{Status: "ONLINE", IdleCapacity: idle, Version: version})
				if err != nil {
					logln("heartbeat failed:", err)
					continue
				}
				for _, id := range resp.CancelRunIDs {
					if c, ok := cancels[id]; ok {
						c()
					}
				}
			}
		}
	}()

	logln(fmt.Sprintf("runner %q online -> %s (max %d concurrent)", cfg.Name, cfg.ServerURL, cfg.MaxConcurrent))

	for loopCtx.Err() == nil {
		mu.Lock()
		n := len(active)
		mu.Unlock()
		if n >= cfg.MaxConcurrent {
			time.Sleep(500 * time.Millisecond)
			continue
		}
		job, err := t.claimJob(loopCtx)
		if err != nil {
			if loopCtx.Err() != nil {
				break
			}
			logln("claim failed:", err)
			time.Sleep(2 * time.Second)
			continue
		}
		if job == nil {
			continue
		}
		jobCtx, cancel := context.WithCancel(context.Background())
		mu.Lock()
		active[job.RunID] = cancel
		mu.Unlock()
		go func(j *ClaimedJob) {
			executeAndReport(t, j, jobCtx)
			mu.Lock()
			delete(active, j.RunID)
			mu.Unlock()
		}(job)
	}

	close(hbStop)
	logln("runner stopping; waiting for active jobs...")
	for {
		mu.Lock()
		n := len(active)
		mu.Unlock()
		if n == 0 {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func executeAndReport(t *Transport, job *ClaimedJob, ctx context.Context) {
	var bufMu sync.Mutex
	var buf []RunEvent
	seq := 0

	flush := func() {
		bufMu.Lock()
		if len(buf) == 0 {
			bufMu.Unlock()
			return
		}
		events := buf
		buf = nil
		bufMu.Unlock()
		if err := t.postEvents(job.RunID, RunEventBatch{Events: events}); err != nil {
			logln("event flush failed for", job.RunID+":", err)
		}
	}
	emit := func(eventType string, payload map[string]interface{}) {
		bufMu.Lock()
		buf = append(buf, RunEvent{Seq: seq, Type: eventType, TS: nowISO(), Payload: payload})
		seq++
		full := len(buf) >= 25
		bufMu.Unlock()
		if full {
			flush()
		}
	}

	stopFlush := make(chan struct{})
	go func() {
		tk := time.NewTicker(1 * time.Second)
		defer tk.Stop()
		for {
			select {
			case <-stopFlush:
				return
			case <-tk.C:
				flush()
			}
		}
	}()

	logln(fmt.Sprintf("> run %s — %s", job.RunID, job.Title))
	workdir := filepath.Join(runsDir(), job.RunID)
	_ = os.MkdirAll(workdir, 0o755)
	res := executeJob(ctx, job, emit, workdir)

	close(stopFlush)
	flush()

	err := t.complete(job.RunID, CompleteRequest{
		Status:          res.Status,
		Result:          res.Result,
		Subtype:         res.Subtype,
		Error:           res.ErrorMsg,
		ClaudeSessionID: res.ClaudeSessionID,
		NumTurns:        res.NumTurns,
		DurationMs:      res.DurationMs,
		CostUsd:         res.CostUsd,
		Usage:           res.Usage,
		ModelUsage:      res.ModelUsage,
	})
	if err != nil {
		logln("complete failed for", job.RunID+":", err)
	} else {
		logln(fmt.Sprintf("■ run %s → %s ($%.4f)", job.RunID, res.Status, res.CostUsd))
	}
}

func logln(args ...interface{}) {
	fmt.Print("[orbit-runner ", nowISO(), "] ")
	fmt.Println(args...)
}

func nowISO() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000Z07:00")
}
