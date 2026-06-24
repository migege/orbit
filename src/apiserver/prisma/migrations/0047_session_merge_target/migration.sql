-- Choose-your-merge-target on the worktree status bar. The "Merge to main" button becomes a
-- split button whose caret offers other branches. `merge_target` holds the branch the user
-- picked (NULL = the default, which the runner auto-detects: main, else master) and is relayed
-- to the runner in the MergeCommand. `merge_targets` is the candidate list the runner reports
-- for the session's repo (local branches minus Orbit's own orbit/* session branches), which
-- populates the dropdown. No backfill: NULL/empty for existing sessions, so the bar keeps the
-- plain "Merge to main" behavior until a new-enough runner reports targets.
ALTER TABLE "session" ADD COLUMN "merge_target" TEXT;
ALTER TABLE "session" ADD COLUMN "merge_targets" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
