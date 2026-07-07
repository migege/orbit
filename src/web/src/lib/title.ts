/**
 * First non-blank line of a session title. Titles are normally one clean line, but a fallback
 * title (DeepSeek unavailable when the session was created) can be the raw multi-line prompt —
 * and showing all of it in a header, the browser tab, or an exported file's <title> reads as
 * broken. Collapse to line one; whitespace-only or empty yields ''.
 */
export function titleFirstLine(title: string): string {
  return title.split('\n').map((l) => l.trim()).find(Boolean) ?? title.trim();
}
