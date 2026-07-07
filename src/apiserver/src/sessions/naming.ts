import { randomUUID } from 'crypto';

/**
 * Turn a human title into a git-branch-safe slug: lowercase, non-alphanumerics → '-',
 * trimmed and capped. CJK and punctuation collapse to empty, so a non-ASCII title (e.g.
 * a Chinese task title) yields '' — the caller then falls back to a session-id stub.
 * Phase 2 layers an optional DeepSeek call on top to produce a clean English slug for
 * such titles; this is the no-LLM fallback that always works.
 */
export function slugify(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/g, '');
}

/**
 * A unique per-session git branch under the `orbit/` namespace. The short random suffix
 * guarantees uniqueness, so two sessions with the same title — or an empty slug — never
 * collide on a branch (and git never refuses a second worktree on a shared branch name).
 */
export function makeBranchName(title: string): string {
  const slug = slugify(title);
  const suffix = randomUUID().replace(/-/g, '').slice(0, 6);
  return slug ? `orbit/${slug}-${suffix}` : `orbit/session-${suffix}`;
}

/**
 * A display title derived from a raw prompt, for when there's no better source (no explicit
 * dto.title and DeepSeek is unavailable/failed). Takes the first non-blank line — never the
 * whole prompt — so a multi-line request doesn't become a multi-line "title" that then leaks
 * into the session list, the shared page, and its exported HTML's <title>. Capped at 80 chars.
 */
export function titleFromPrompt(prompt: string): string {
  const line = prompt.split('\n').map((l) => l.trim()).find(Boolean) ?? prompt.trim();
  return line.slice(0, 80);
}

export interface NamingResult {
  /** A clean human title from DeepSeek. Undefined → the caller keeps its own title. */
  title?: string;
  /** The git branch to use for this session's worktree. */
  branch: string;
}

/**
 * Produce a session's title + worktree branch. When DEEPSEEK_API_KEY is set, ask DeepSeek
 * (an OpenAI-compatible chat endpoint) for a concise title in the user's own language plus an
 * always-English branch slug — so a Chinese request yields a Chinese title yet still a readable
 * `orbit/fix-login-500` branch instead of the `orbit/session-<hash>` slug fallback. With no key configured — or on any error/timeout/
 * bad response — it falls back to a deterministic slug of the caller's title/prompt and
 * returns no title (the caller keeps its own). NEVER throws: session creation must not
 * depend on the LLM being reachable.
 */
export async function generateNaming(input: { prompt: string; title?: string }): Promise<NamingResult> {
  const fallback = (): NamingResult => ({ branch: makeBranchName(input.title ?? input.prompt.slice(0, 80)) });
  const apiKey = process.env.DEEPSEEK_API_KEY?.trim();
  if (!apiKey) return fallback();
  try {
    const base = (process.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com').replace(/\/+$/, '');
    const model = process.env.DEEPSEEK_MODEL || 'deepseek-chat';
    const task = [input.title, input.prompt].filter(Boolean).join('\n').slice(0, 600);
    const resp = await fetch(`${base}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        max_tokens: 120,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content:
              'You name a software-engineering session. Reply with ONLY a JSON object ' +
              '{"title": string, "slug": string}. "title": a concise summary, at most 6 words ' +
              '(or ~16 characters for languages without spaces), no trailing punctuation, written ' +
              "in the SAME language as the user's request — a Chinese request gets a Chinese title, " +
              'an English request an English one. "slug": a git-branch-safe kebab-case form — ' +
              'lowercase ASCII letters, digits and hyphens only, at most 5 words, ALWAYS in English ' +
              'regardless of the title language. No other text.',
          },
          { role: 'user', content: task },
        ],
      }),
      // Short, hard timeout so a slow/unreachable DeepSeek never stalls session creation.
      signal: AbortSignal.timeout(4000),
    });
    if (!resp.ok) return fallback();
    const data = (await resp.json()) as { choices?: { message?: { content?: string } }[] };
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== 'string') return fallback();
    const parsed = JSON.parse(content) as { title?: unknown; slug?: unknown };
    const title =
      typeof parsed.title === 'string' && parsed.title.trim() ? parsed.title.trim().slice(0, 80) : undefined;
    const slug = typeof parsed.slug === 'string' ? slugify(parsed.slug) : '';
    // Build the branch from the clean slug; if DeepSeek's slug was unusable, slug the title
    // it returned, then the caller's title/prompt — makeBranchName re-slugs defensively.
    return { title, branch: makeBranchName(slug || title || input.title || input.prompt.slice(0, 80)) };
  } catch {
    return fallback();
  }
}
