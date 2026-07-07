-- Flip the default for per-agent worktree isolation to off: new agents no longer run each
-- session in its own git worktree unless the user opts in. Existing agents are left unchanged
-- (their explicit enable_worktree value is kept), so today's isolated sessions keep working.
ALTER TABLE "agent" ALTER COLUMN "enable_worktree" SET DEFAULT false;
