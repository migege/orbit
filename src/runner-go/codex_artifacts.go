package main

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type artifactUploader func(ctx context.Context, path, mimeType string) (string, error)

var markdownImageRE = regexp.MustCompile(`!\[([^\]]*)\]\((<?[^)\s]+>?)(\s+(?:"[^"]*"|'[^']*'))?\)`)

func rewriteLocalMarkdownImages(ctx context.Context, t *Transport, sessionID, text string, roots []string) string {
	return rewriteLocalMarkdownImagesWithUploader(ctx, text, roots, func(ctx context.Context, path, mimeType string) (string, error) {
		return t.uploadSessionAttachment(ctx, sessionID, path, mimeType)
	})
}

func rewriteLocalMarkdownImagesWithUploader(ctx context.Context, text string, roots []string, upload artifactUploader) string {
	if text == "" || upload == nil || len(roots) == 0 {
		return text
	}
	cleanRoots := cleanExistingRoots(roots)
	if len(cleanRoots) == 0 {
		return text
	}
	uploaded := map[string]string{}
	return markdownImageRE.ReplaceAllStringFunc(text, func(match string) string {
		parts := markdownImageRE.FindStringSubmatch(match)
		if len(parts) < 4 {
			return match
		}
		raw := strings.Trim(parts[2], "<>")
		if skipMarkdownImageSrc(raw) {
			return match
		}
		path := localMarkdownImagePath(raw, cleanRoots[0])
		if path == "" || !pathWithinRoots(path, cleanRoots) {
			return match
		}
		mimeType, ok := imageMime(path)
		if !ok {
			return match
		}
		id := uploaded[path]
		if id == "" {
			var err error
			id, err = upload(ctx, path, mimeType)
			if err != nil {
				logln("assistant image upload failed for", path+":", err)
				return match
			}
			uploaded[path] = id
		}
		return fmt.Sprintf("![%s](orbit-attachment:%s%s)", parts[1], id, parts[3])
	})
}

func skipMarkdownImageSrc(src string) bool {
	lower := strings.ToLower(strings.TrimSpace(src))
	return lower == "" ||
		strings.HasPrefix(lower, "data:") ||
		strings.HasPrefix(lower, "http://") ||
		strings.HasPrefix(lower, "https://") ||
		strings.HasPrefix(lower, "orbit-attachment:")
}

func localMarkdownImagePath(src, baseDir string) string {
	if strings.ContainsAny(src, "?#") {
		return ""
	}
	unescaped, err := url.PathUnescape(src)
	if err != nil {
		unescaped = src
	}
	if filepath.IsAbs(unescaped) {
		return filepath.Clean(unescaped)
	}
	return filepath.Clean(filepath.Join(baseDir, unescaped))
}

func cleanExistingRoots(roots []string) []string {
	out := make([]string, 0, len(roots))
	seen := map[string]bool{}
	for _, root := range roots {
		if root == "" {
			continue
		}
		clean, err := filepath.Abs(root)
		if err != nil {
			clean = filepath.Clean(root)
		}
		if seen[clean] {
			continue
		}
		if st, err := os.Stat(clean); err == nil && st.IsDir() {
			out = append(out, clean)
			seen[clean] = true
		}
	}
	return out
}

func pathWithinRoots(path string, roots []string) bool {
	abs, err := filepath.Abs(path)
	if err != nil {
		abs = filepath.Clean(path)
	}
	st, err := os.Stat(abs)
	if err != nil || st.IsDir() {
		return false
	}
	for _, root := range roots {
		rel, err := filepath.Rel(root, abs)
		if err == nil && rel != "." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && rel != ".." {
			return true
		}
	}
	return false
}

func imageMime(path string) (string, bool) {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png":
		return "image/png", true
	case ".jpg", ".jpeg":
		return "image/jpeg", true
	case ".gif":
		return "image/gif", true
	case ".webp":
		return "image/webp", true
	case ".svg":
		return "image/svg+xml", true
	}
	f, err := os.Open(path)
	if err != nil {
		return "", false
	}
	defer f.Close()
	buf := make([]byte, 512)
	n, _ := f.Read(buf)
	mimeType := http.DetectContentType(buf[:n])
	return mimeType, strings.HasPrefix(mimeType, "image/")
}
