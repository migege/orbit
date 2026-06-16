package main

import (
	"fmt"
	"os"

	"golang.org/x/term"
)

// keyEvent is a decoded keypress from the interactive selector.
type keyEvent int

const (
	keyNone keyEvent = iota
	keyUp
	keyDown
	keyToggle    // space — flip the item under the cursor
	keyToggleAll // a — select all, or clear all if everything is already on
	keyConfirm   // Enter
	keyAbort     // Ctrl-C or q
)

// decodeKey maps the raw bytes read in raw mode to a keyEvent. Arrow keys
// arrive as the escape sequence ESC [ A/B (or ESC O A/B from some terminals);
// we also accept vim-style j/k so the selector works without arrow keys.
func decodeKey(b []byte) keyEvent {
	if len(b) == 0 {
		return keyNone
	}
	if len(b) >= 3 && b[0] == 0x1b && (b[1] == '[' || b[1] == 'O') {
		switch b[2] {
		case 'A':
			return keyUp
		case 'B':
			return keyDown
		}
		return keyNone
	}
	switch b[0] {
	case 0x03: // Ctrl-C — raw mode delivers it as a byte, not a signal
		return keyAbort
	case 'q', 'Q':
		return keyAbort
	case 'k', 'K':
		return keyUp
	case 'j', 'J':
		return keyDown
	case ' ':
		return keyToggle
	case 'a', 'A':
		return keyToggleAll
	case '\r', '\n':
		return keyConfirm
	}
	return keyNone
}

// selectModel is the state of the checkbox list: which items are checked and
// where the cursor sits. apply/decodeKey are kept free of I/O so they can be
// unit-tested without a terminal.
type selectModel struct {
	labels  []string
	checked []bool
	cursor  int
}

func (m *selectModel) anyChecked() bool {
	for _, c := range m.checked {
		if c {
			return true
		}
	}
	return false
}

func (m *selectModel) allChecked() bool {
	for _, c := range m.checked {
		if !c {
			return false
		}
	}
	return true
}

func (m *selectModel) selected() []int {
	out := []int{}
	for i, c := range m.checked {
		if c {
			out = append(out, i)
		}
	}
	return out
}

// apply updates the model for a key and reports whether the interaction is
// done and, if so, whether it was aborted. Confirming with nothing checked is
// ignored so the caller always gets at least one selection.
func (m *selectModel) apply(k keyEvent) (done, abort bool) {
	switch k {
	case keyUp:
		if m.cursor > 0 {
			m.cursor--
		}
	case keyDown:
		if m.cursor < len(m.labels)-1 {
			m.cursor++
		}
	case keyToggle:
		m.checked[m.cursor] = !m.checked[m.cursor]
	case keyToggleAll:
		all := !m.allChecked()
		for i := range m.checked {
			m.checked[i] = all
		}
	case keyConfirm:
		if m.anyChecked() {
			return true, false
		}
	case keyAbort:
		return true, true
	}
	return false, false
}

// render draws the item list. When redraw is true it first moves the cursor
// back up over the previously drawn lines so the list updates in place.
func (m *selectModel) render(redraw bool) {
	if redraw {
		fmt.Printf("\x1b[%dA", len(m.labels))
	}
	for i, label := range m.labels {
		pointer := "  "
		if i == m.cursor {
			pointer = "> "
		}
		box := "[ ]"
		if m.checked[i] {
			box = "[x]"
		}
		// \x1b[K clears to end of line so a shorter redraw leaves no tail.
		fmt.Printf("\r%s%s %s\x1b[K\r\n", pointer, box, label)
	}
}

// multiSelect renders an interactive checkbox list and returns the chosen
// 0-based indices. It returns ok=false when stdin isn't a terminal or can't
// enter raw mode, so the caller can fall back to a line-based prompt. Ctrl-C
// or q aborts registration.
func multiSelect(title string, labels []string, checked []bool) (idx []int, ok bool) {
	fd := int(os.Stdin.Fd())
	if !term.IsTerminal(fd) {
		return nil, false
	}
	old, err := term.MakeRaw(fd)
	if err != nil {
		return nil, false
	}
	defer term.Restore(fd, old)

	m := &selectModel{labels: labels, checked: append([]bool(nil), checked...)}

	fmt.Printf("\r\n%s\r\n", title)
	fmt.Print("  ↑/↓ move · space toggle · a all · enter confirm · q cancel\r\n")
	m.render(false)

	buf := make([]byte, 8)
	for {
		n, err := os.Stdin.Read(buf)
		if err != nil || n == 0 {
			return nil, false
		}
		done, abort := m.apply(decodeKey(buf[:n]))
		m.render(true)
		if done {
			fmt.Print("\r\n")
			if abort {
				term.Restore(fd, old)
				abortRegister("selection cancelled")
			}
			return m.selected(), true
		}
	}
}
