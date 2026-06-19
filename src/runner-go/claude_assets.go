package main

import (
	"os"
	"path/filepath"
	"strings"
)

// scanSlashAssets discovers custom slash commands (.claude/commands/*.md) and
// skills (.claude/skills/<name>/SKILL.md) across the given project dirs plus the
// user's global ~/.claude. The result feeds the web composer's `/` autocomplete.
// Dedup is by name, first occurrence wins: workDirs are scanned before the global
// dir, so a project's own asset shadows a same-named global one.
func scanSlashAssets(workDirs []string) (commands, skills []SlashCommandInfo) {
	var roots []string
	seenRoot := map[string]bool{}
	addRoot := func(base string) {
		if base == "" {
			return
		}
		root := filepath.Join(expandTilde(base), ".claude")
		if seenRoot[root] {
			return
		}
		seenRoot[root] = true
		roots = append(roots, root)
	}
	for _, wd := range workDirs {
		addRoot(wd)
	}
	addRoot(userHome())

	cmdSeen := map[string]bool{}
	skillSeen := map[string]bool{}
	for _, root := range roots {
		for _, c := range scanCommands(filepath.Join(root, "commands")) {
			if !cmdSeen[c.Name] {
				cmdSeen[c.Name] = true
				commands = append(commands, c)
			}
		}
		for _, s := range scanSkills(filepath.Join(root, "skills")) {
			if !skillSeen[s.Name] {
				skillSeen[s.Name] = true
				skills = append(skills, s)
			}
		}
	}
	return commands, skills
}

func scanCommands(dir string) []SlashCommandInfo {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []SlashCommandInfo
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}
		_, desc := readFrontmatter(filepath.Join(dir, e.Name()))
		out = append(out, SlashCommandInfo{
			Name:        strings.TrimSuffix(e.Name(), ".md"),
			Description: desc,
			Type:        "command",
		})
	}
	return out
}

func scanSkills(dir string) []SlashCommandInfo {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []SlashCommandInfo
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name, desc := readFrontmatter(filepath.Join(dir, e.Name(), "SKILL.md"))
		if name == "" {
			name = e.Name()
		}
		out = append(out, SlashCommandInfo{Name: name, Description: desc, Type: "skill"})
	}
	return out
}

// readFrontmatter returns the `name` and `description` from a file's leading
// `---`-fenced YAML block. Minimal by design: it handles only the flat
// `key: value` lines orbit's command/skill files use (single-line values, no
// nested/multi-line YAML), which is all the composer hint needs.
func readFrontmatter(path string) (name, description string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", ""
	}
	lines := strings.Split(string(data), "\n")
	i := 0
	for i < len(lines) && strings.TrimSpace(lines[i]) == "" {
		i++
	}
	if i >= len(lines) || strings.TrimSpace(lines[i]) != "---" {
		return "", ""
	}
	for i++; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			break
		}
		key, val, ok := strings.Cut(lines[i], ":")
		if !ok {
			continue
		}
		val = strings.Trim(strings.TrimSpace(val), `"'`)
		switch strings.TrimSpace(key) {
		case "name":
			name = val
		case "description":
			description = val
		}
	}
	return name, description
}
