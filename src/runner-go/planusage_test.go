package main

import "testing"

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
