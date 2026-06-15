package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// installService is the `orbit service` command: fatal on error.
func installService() {
	if err := setupService(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// setupService installs + starts a background service that runs `orbit run` and
// restarts on failure. Linux uses systemd; macOS uses a launchd LaunchAgent.
// Returns an error instead of exiting, so `orbit register` can call it best-effort.
// The runner authenticates through the machine's local Claude Code login, so no
// API key is involved here.
func setupService() error {
	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("cannot locate executable: %w", err)
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	orbitHome := baseDir()

	switch runtime.GOOS {
	case "linux":
		return installSystemd(exe, orbitHome)
	case "darwin":
		return installLaunchd(exe, orbitHome)
	default:
		return errors.New("`orbit service` supports Linux (systemd) and macOS (launchd); on this platform run `orbit run` under your own supervisor")
	}
}

func installSystemd(exe, orbitHome string) error {
	unitPath := "/etc/systemd/system/orbit-runner.service"
	unit := fmt.Sprintf(`[Unit]
Description=Orbit runner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%s run
Restart=always
RestartSec=5
Environment=ORBIT_HOME=%s

[Install]
WantedBy=multi-user.target
`, exe, orbitHome)

	if err := os.WriteFile(unitPath, []byte(unit), 0o644); err != nil {
		return fmt.Errorf("failed to write %s: %w (try: sudo orbit service)", unitPath, err)
	}
	if err := run("systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("systemctl daemon-reload failed — is this a systemd host, and are you root?")
	}
	if err := run("systemctl", "enable", "--now", "orbit-runner"); err != nil {
		return fmt.Errorf("systemctl enable failed — is this a systemd host, and are you root?")
	}
	fmt.Printf("\n✓ orbit-runner service installed and started.\n" +
		"  Status:  systemctl status orbit-runner\n" +
		"  Logs:    journalctl -u orbit-runner -f\n")
	return nil
}

func installLaunchd(exe, orbitHome string) error {
	const label = "com.orbit.runner"
	home := os.Getenv("HOME")
	if home == "" {
		if h, err := os.UserHomeDir(); err == nil {
			home = h
		}
	}
	plistPath := filepath.Join(home, "Library", "LaunchAgents", label+".plist")
	logPath := filepath.Join(orbitHome, "runner.log")

	plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>%s</string>
  <key>ProgramArguments</key>
  <array>
    <string>%s</string>
    <string>run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ORBIT_HOME</key><string>%s</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>%s</string>
  <key>StandardErrorPath</key><string>%s</string>
</dict>
</plist>
`, label, exe, orbitHome, logPath, logPath)

	if err := os.MkdirAll(filepath.Dir(plistPath), 0o755); err != nil {
		return fmt.Errorf("failed to create %s: %w", filepath.Dir(plistPath), err)
	}
	if err := os.WriteFile(plistPath, []byte(plist), 0o644); err != nil {
		return fmt.Errorf("failed to write %s: %w", plistPath, err)
	}
	_ = run("launchctl", "unload", plistPath) // ignore "not loaded"
	if err := run("launchctl", "load", "-w", plistPath); err != nil {
		return fmt.Errorf("launchctl load failed")
	}

	fmt.Printf("\n✓ orbit-runner LaunchAgent installed and started.\n"+
		"  Plist:   %s\n"+
		"  Logs:    %s\n"+
		"  Stop:    launchctl unload %s\n", plistPath, logPath, plistPath)
	return nil
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
