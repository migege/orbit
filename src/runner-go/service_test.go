package main

import "testing"

func TestSystemdServiceFor(t *testing.T) {
	cases := []struct{ user, want string }{
		{"husong", "orbit-runner-husong"},
		{"alice_2", "orbit-runner-alice_2"},
		{"web-svc", "orbit-runner-web-svc"},
		// Characters not allowed in a systemd unit name are mapped to '_'.
		{"foo.bar", "orbit-runner-foo_bar"},
		{"a/b c", "orbit-runner-a_b_c"},
	}
	for _, c := range cases {
		if got := systemdServiceFor(c.user); got != c.want {
			t.Errorf("systemdServiceFor(%q) = %q, want %q", c.user, got, c.want)
		}
	}
	// Distinct users must yield distinct unit names — the whole point of per-user units.
	if systemdServiceFor("alice") == systemdServiceFor("bob") {
		t.Fatal("different users produced the same unit name")
	}
}
