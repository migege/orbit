package main

import (
	"context"
	"net/http"
	"sync/atomic"
	"testing"
	"time"
)

func TestParseCodexPlanUsage(t *testing.T) {
	got, err := parseCodexPlanUsage(map[string]interface{}{
		"rateLimitsByLimitId": map[string]interface{}{
			"codex": map[string]interface{}{
				"limitId":   "codex",
				"limitName": "Codex",
				"planType":  "plus",
				"primary": map[string]interface{}{
					"usedPercent":        float64(6),
					"windowDurationMins": float64(300),
					"resetsAt":           float64(1783000000),
				},
				"secondary": map[string]interface{}{
					"usedPercent":        float64(30),
					"windowDurationMins": float64(10080),
				},
				"credits": map[string]interface{}{
					"hasCredits": true,
					"unlimited":  false,
					"balance":    "10",
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("parseCodexPlanUsage error: %v", err)
	}
	if got.Provider != providerCodex || got.LimitID != "codex" || got.PlanType != "plus" {
		t.Fatalf("unexpected metadata: %#v", got)
	}
	if got.Primary == nil || got.Primary.Utilization != 6 || got.Primary.Label != "5-hour limit" || got.Primary.ResetsAt == "" {
		t.Fatalf("unexpected primary: %#v", got.Primary)
	}
	if got.Secondary == nil || got.Secondary.Utilization != 30 || got.Secondary.Label != "Weekly limit" {
		t.Fatalf("unexpected secondary: %#v", got.Secondary)
	}
	if got.Credits == nil || !got.Credits.HasCredits || got.Credits.Unlimited || got.Credits.Balance != "10" {
		t.Fatalf("unexpected credits: %#v", got.Credits)
	}
}

func TestCombinePlanUsageNestsMultipleProviders(t *testing.T) {
	claude := &PlanUsage{Provider: providerClaude, FetchedAt: "2026-07-01T10:00:00Z"}
	codex := &PlanUsage{Provider: providerCodex, FetchedAt: "2026-07-01T11:00:00Z"}
	got := combinePlanUsage(claude, codex)
	if got.Claude != claude || got.Codex != codex {
		t.Fatalf("combinePlanUsage = %#v", got)
	}
	if got.FetchedAt != codex.FetchedAt {
		t.Fatalf("FetchedAt = %q, want %q", got.FetchedAt, codex.FetchedAt)
	}
}

func TestPlanUsageProbeRefreshesWhileIdleWhenEnabled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var calls atomic.Int64
	p := &planUsageProbe{
		name: "test plan-usage",
		fetch: func(context.Context, *http.Client) (*PlanUsage, error) {
			calls.Add(1)
			return &PlanUsage{Provider: providerCodex}, nil
		},
	}
	go p.runWithIntervals(
		ctx,
		func() int { return 0 },
		func() bool { return true },
		5*time.Millisecond,
		time.Hour,
		20*time.Millisecond,
	)
	waitForPlanUsageCalls(t, &calls, 2)
}

func TestPlanUsageProbeSkipsIdleRefreshWhenDisabled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var calls atomic.Int64
	p := &planUsageProbe{
		name: "test plan-usage",
		fetch: func(context.Context, *http.Client) (*PlanUsage, error) {
			calls.Add(1)
			return &PlanUsage{Provider: providerCodex}, nil
		},
	}
	go p.runWithIntervals(
		ctx,
		func() int { return 0 },
		func() bool { return false },
		5*time.Millisecond,
		20*time.Millisecond,
		20*time.Millisecond,
	)
	time.Sleep(50 * time.Millisecond)
	if got := calls.Load(); got != 0 {
		t.Fatalf("fetch calls = %d, want 0", got)
	}
}

func TestPlanUsageProbeRefreshesOnBusyIdleTransition(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var active atomic.Int64
	active.Store(1)
	var calls atomic.Int64
	p := &planUsageProbe{
		name: "test plan-usage",
		fetch: func(context.Context, *http.Client) (*PlanUsage, error) {
			calls.Add(1)
			return &PlanUsage{Provider: providerCodex}, nil
		},
	}
	go p.runWithIntervals(
		ctx,
		func() int { return int(active.Load()) },
		func() bool { return false },
		5*time.Millisecond,
		time.Hour,
		time.Hour,
	)
	waitForPlanUsageCalls(t, &calls, 1)
	active.Store(0)
	waitForPlanUsageCalls(t, &calls, 2)
}

func TestPlanUsageRefreshDueUsesResetBeforeInterval(t *testing.T) {
	now := time.Date(2026, 7, 2, 14, 0, 0, 0, time.UTC)
	lastFetch := now.Add(-time.Minute)
	resetAt := now.Add(-time.Second)
	usage := &PlanUsage{
		Provider: providerCodex,
		Primary:  &PlanUsageWindow{Utilization: 12, ResetsAt: resetAt.Format(time.RFC3339)},
	}
	if !planUsageRefreshDue(lastFetch, usage, now.Add(planUsageResetRefreshDelay), time.Hour) {
		t.Fatalf("expected reset timestamp to make refresh due before idle interval")
	}
}

func TestPlanUsageRefreshDueIgnoresAlreadyAttemptedReset(t *testing.T) {
	now := time.Date(2026, 7, 2, 14, 0, 0, 0, time.UTC)
	lastFetch := now
	resetAt := now.Add(-time.Minute)
	usage := &PlanUsage{
		Provider: providerCodex,
		Primary:  &PlanUsageWindow{Utilization: 12, ResetsAt: resetAt.Format(time.RFC3339)},
	}
	if planUsageRefreshDue(lastFetch, usage, now.Add(time.Minute), time.Hour) {
		t.Fatalf("reset before last fetch should not force immediate retry")
	}
}

func waitForPlanUsageCalls(t *testing.T, calls *atomic.Int64, want int64) {
	t.Helper()
	deadline := time.After(500 * time.Millisecond)
	tick := time.NewTicker(5 * time.Millisecond)
	defer tick.Stop()
	for {
		if calls.Load() >= want {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("fetch calls = %d, want at least %d", calls.Load(), want)
		case <-tick.C:
		}
	}
}
