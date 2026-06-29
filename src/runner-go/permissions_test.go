package main

import "testing"

// unwrap pulls the single addRules directive rememberPermissions emits, returning its
// "rules" slice (or nil when the payload is empty).
func unwrapRules(t *testing.T, payload []interface{}) []interface{} {
	t.Helper()
	if payload == nil {
		return nil
	}
	if len(payload) != 1 {
		t.Fatalf("want 1 directive, got %d", len(payload))
	}
	d, ok := payload[0].(map[string]interface{})
	if !ok {
		t.Fatalf("directive is not a map: %T", payload[0])
	}
	if d["type"] != "addRules" || d["behavior"] != "allow" || d["destination"] != "session" {
		t.Fatalf("unexpected directive header: %v", d)
	}
	rules, ok := d["rules"].([]interface{})
	if !ok {
		t.Fatalf("rules is not a slice: %T", d["rules"])
	}
	return rules
}

func TestRememberPermissionsEmitsEveryRule(t *testing.T) {
	rules := rememberPermissions([]PermissionRule{
		{ToolName: "Bash", RuleContent: "cd:*"},
		{ToolName: "Bash", RuleContent: "git add:*"},
		{ToolName: "Bash", RuleContent: "grep:*"},
	})
	got := unwrapRules(t, rules)
	if len(got) != 3 {
		t.Fatalf("want 3 rules, got %d", len(got))
	}
	first := got[0].(map[string]interface{})
	if first["toolName"] != "Bash" || first["ruleContent"] != "cd:*" {
		t.Fatalf("unexpected first rule: %v", first)
	}
}

func TestRememberPermissionsToolWideRuleOmitsRuleContent(t *testing.T) {
	got := unwrapRules(t, rememberPermissions([]PermissionRule{{ToolName: "Edit"}}))
	r := got[0].(map[string]interface{})
	if r["toolName"] != "Edit" {
		t.Fatalf("want toolName Edit, got %v", r["toolName"])
	}
	if _, present := r["ruleContent"]; present {
		t.Fatalf("ruleContent should be omitted for a tool-wide rule, got %v", r["ruleContent"])
	}
}

func TestRememberPermissionsSkipsEmptyToolName(t *testing.T) {
	got := unwrapRules(t, rememberPermissions([]PermissionRule{
		{ToolName: ""},
		{ToolName: "Bash", RuleContent: "ls:*"},
	}))
	if len(got) != 1 {
		t.Fatalf("want 1 rule after filtering, got %d", len(got))
	}
}

func TestRememberPermissionsEmptyIsNil(t *testing.T) {
	if rememberPermissions(nil) != nil {
		t.Fatal("no rules should yield a nil payload so allowJSON omits the field")
	}
	if rememberPermissions([]PermissionRule{{ToolName: ""}}) != nil {
		t.Fatal("all-empty rules should yield a nil payload")
	}
}

func TestResolveRememberRulesPrefersArray(t *testing.T) {
	legacy := PermissionRule{ToolName: "Bash", RuleContent: "cd:*"}
	dec := ApprovalDecisionResponse{
		RememberRules: []PermissionRule{{ToolName: "Bash", RuleContent: "git add:*"}},
		RememberRule:  &legacy,
	}
	got := dec.resolveRememberRules()
	if len(got) != 1 || got[0].RuleContent != "git add:*" {
		t.Fatalf("array form should win, got %v", got)
	}
}

func TestResolveRememberRulesFallsBackToSingular(t *testing.T) {
	legacy := PermissionRule{ToolName: "Bash", RuleContent: "cd:*"}
	dec := ApprovalDecisionResponse{RememberRule: &legacy}
	got := dec.resolveRememberRules()
	if len(got) != 1 || got[0].RuleContent != "cd:*" {
		t.Fatalf("should fall back to the singular rule, got %v", got)
	}
}

func TestResolveRememberRulesEmpty(t *testing.T) {
	if got := (ApprovalDecisionResponse{}).resolveRememberRules(); got != nil {
		t.Fatalf("no rules should resolve to nil, got %v", got)
	}
}
