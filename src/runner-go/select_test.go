package main

import (
	"io"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestDecodeKey(t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want keyEvent
	}{
		{"up arrow", []byte{0x1b, '[', 'A'}, keyUp},
		{"down arrow", []byte{0x1b, '[', 'B'}, keyDown},
		{"ss3 up arrow", []byte{0x1b, 'O', 'A'}, keyUp},
		{"left arrow is ignored", []byte{0x1b, '[', 'D'}, keyNone},
		{"k moves up", []byte{'k'}, keyUp},
		{"j moves down", []byte{'j'}, keyDown},
		{"space toggles", []byte{' '}, keyToggle},
		{"a toggles all", []byte{'a'}, keyToggleAll},
		{"enter confirms", []byte{'\r'}, keyConfirm},
		{"newline confirms", []byte{'\n'}, keyConfirm},
		{"ctrl-c aborts", []byte{0x03}, keyAbort},
		{"q aborts", []byte{'q'}, keyAbort},
		{"lone esc is ignored", []byte{0x1b}, keyNone},
		{"empty is ignored", []byte{}, keyNone},
		{"unknown is ignored", []byte{'z'}, keyNone},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := decodeKey(c.in); got != c.want {
				t.Fatalf("decodeKey(%v) = %v, want %v", c.in, got, c.want)
			}
		})
	}
}

func newModel(checked ...bool) *selectModel {
	labels := make([]string, len(checked))
	return &selectModel{labels: labels, checked: append([]bool(nil), checked...)}
}

func TestSelectModelNavigationClamps(t *testing.T) {
	m := newModel(true, true, true)
	if _, _ = m.apply(keyUp); m.cursor != 0 {
		t.Fatalf("cursor up at top = %d, want 0", m.cursor)
	}
	m.apply(keyDown)
	m.apply(keyDown)
	m.apply(keyDown) // past the end
	if m.cursor != 2 {
		t.Fatalf("cursor = %d, want clamped at 2", m.cursor)
	}
}

func TestSelectModelToggle(t *testing.T) {
	m := newModel(true, true)
	m.apply(keyToggle) // turn off item 0
	if want := []int{1}; !reflect.DeepEqual(want, m.selected()) {
		t.Fatalf("selected = %v, want [1]", m.selected())
	}
}

func TestSelectModelToggleAll(t *testing.T) {
	m := newModel(true, true, true)
	m.apply(keyToggleAll) // all on -> all off
	if m.anyChecked() {
		t.Fatalf("toggle-all from all-on should clear, got %v", m.selected())
	}
	m.apply(keyToggleAll) // all off -> all on
	if want := []int{0, 1, 2}; !reflect.DeepEqual(want, m.selected()) {
		t.Fatalf("toggle-all from all-off = %v, want all", m.selected())
	}
}

func TestSelectModelConfirmRequiresSelection(t *testing.T) {
	m := newModel(false, false)
	done, abort := m.apply(keyConfirm)
	if done || abort {
		t.Fatalf("confirm with nothing checked should be ignored, got done=%v abort=%v", done, abort)
	}
	m.checked[1] = true
	done, abort = m.apply(keyConfirm)
	if !done || abort {
		t.Fatalf("confirm with a selection should finish, got done=%v abort=%v", done, abort)
	}
}

func TestSelectModelRender(t *testing.T) {
	capture := func(redraw bool) string {
		old := os.Stdout
		r, w, _ := os.Pipe()
		os.Stdout = w
		(&selectModel{labels: []string{"Alpha", "Beta"}, checked: []bool{true, false}, cursor: 1}).render(redraw)
		w.Close()
		os.Stdout = old
		out, _ := io.ReadAll(r)
		return string(out)
	}

	got := capture(false)
	if !strings.Contains(got, "  [x] Alpha") {
		t.Errorf("unchecked-cursor row missing checked box: %q", got)
	}
	if !strings.Contains(got, "> [ ] Beta") {
		t.Errorf("cursor row missing pointer/empty box: %q", got)
	}
	if strings.Contains(got, "\x1b[2A") {
		t.Errorf("initial draw must not move the cursor up: %q", got)
	}

	// A redraw rewinds the cursor up over the two item lines first.
	if redraw := capture(true); !strings.HasPrefix(redraw, "\x1b[2A") {
		t.Errorf("redraw should start by moving up 2 lines, got %q", redraw)
	}
}

func TestSelectHint(t *testing.T) {
	// More than one row: advertise navigation and select-all.
	multi := selectHint(3)
	if !strings.Contains(multi, "↑/↓ move") || !strings.Contains(multi, "a all") {
		t.Errorf("multi-item hint should offer ↑/↓ and a all, got %q", multi)
	}
	// A single row can't be navigated, so drop ↑/↓ and "a all".
	one := selectHint(1)
	if strings.Contains(one, "↑/↓") || strings.Contains(one, "a all") {
		t.Errorf("single-item hint should drop ↑/↓ and a all, got %q", one)
	}
	if !strings.Contains(one, "space toggle") || !strings.Contains(one, "enter confirm") || !strings.Contains(one, "q cancel") {
		t.Errorf("single-item hint missing space/enter/q actions, got %q", one)
	}
}

func TestSelectModelAbort(t *testing.T) {
	m := newModel(true)
	done, abort := m.apply(keyAbort)
	if !done || !abort {
		t.Fatalf("abort should finish with abort=true, got done=%v abort=%v", done, abort)
	}
}
