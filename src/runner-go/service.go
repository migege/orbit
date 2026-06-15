package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// installService installs + starts a background service that runs `orbit run`
// and restarts on failure. Linux uses systemd; macOS uses a launchd LaunchAgent.
func installService() {
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, "cannot locate executable:", err)
		os.Exit(1)
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	orbitHome := baseDir()

	switch runtime.GOOS {
	case "linux":
		installSystemd(exe, orbitHome)
	case "darwin":
		installLaunchd(exe, orbitHome)
	default:
		fmt.Fprintln(os.Stderr,
			"`orbit service` supports Linux (systemd) and macOS (launchd). On this platform run `orbit run` under your own supervisor.")
		os.Exit(1)
	}
}

func installSystemd(exe, orbitHome string) {
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
EnvironmentFile=-%s/env

[Install]
WantedBy=multi-user.target
`, exe, orbitHome, orbitHome)

	if err := os.WriteFile(unitPath, []byte(unit), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "failed to write %s: %s\nRe-run with sudo:  sudo orbit service\n", unitPath, err)
		os.Exit(1)
	}
	if err := run("systemctl", "daemon-reload"); err != nil {
		fmt.Fprintln(os.Stderr, "systemctl daemon-reload failed — is this a systemd host, and are you root?")
		os.Exit(1)
	}
	if err := run("systemctl", "enable", "--now", "orbit-runner"); err != nil {
		fmt.Fprintln(os.Stderr, "systemctl enable failed — is this a systemd host, and are you root?")
		os.Exit(1)
	}
	fmt.Printf("\n✓ orbit-runner service installed and started.\n"+
		"  Put ANTHROPIC_API_KEY=... in %s/env if the runner needs it.\n"+
		"  Status:  systemctl status orbit-runner\n"+
		"  Logs:    journalctl -u orbit-runner -f\n", orbitHome)
}

func installLaunchd(exe, orbitHome string) {
	const label = "com.orbit.runner"
	home := os.Getenv("HOME")
	if home == "" {
		if h, err := os.UserHomeDir(); err == nil {
			home = h
		}
	}
	plistPath := filepath.Join(home, "Library", "LaunchAgents", label+".plist")
	logPath := filepath.Join(orbitHome, "runner.log")

	apiKeyEntry := ""
	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey != "" {
		apiKeyEntry = fmt.Sprintf("\n    <key>ANTHROPIC_API_KEY</key><string>%s</string>", apiKey)
	}

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
    <key>ORBIT_HOME</key><string>%s</string>%s
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>%s</string>
  <key>StandardErrorPath</key><string>%s</string>
</dict>
</plist>
`, label, exe, orbitHome, apiKeyEntry, logPath, logPath)

	if err := os.MkdirAll(filepath.Dir(plistPath), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "failed to create %s: %s\n", filepath.Dir(plistPath), err)
		os.Exit(1)
	}
	if err := os.WriteFile(plistPath, []byte(plist), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "failed to write %s: %s\n", plistPath, err)
		os.Exit(1)
	}
	_ = run("launchctl", "unload", plistPath) // ignore "not loaded"
	if err := run("launchctl", "load", "-w", plistPath); err != nil {
		fmt.Fprintln(os.Stderr, "launchctl load failed.")
		os.Exit(1)
	}

	apiNote := ""
	if apiKey == "" {
		apiNote = "  Add ANTHROPIC_API_KEY to the plist EnvironmentVariables if the runner needs it.\n"
	}
	fmt.Printf("\n✓ orbit-runner LaunchAgent installed and started.\n"+
		"  Plist:   %s\n"+
		"  Logs:    %s\n"+
		"%s"+
		"  Stop:    launchctl unload %s\n", plistPath, logPath, apiNote, plistPath)
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
