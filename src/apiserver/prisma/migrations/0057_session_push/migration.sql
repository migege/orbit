-- "Push" button on the worktree status bar. A "Merge to main" that stayed local (no `origin`
-- remote at merge time, or an out-of-band merge) leaves the local target branch ahead of origin;
-- the bar now offers Push so the user can catch origin up without dropping to a command line.
-- `target_unpushed` is the runner's `git rev-list origin/<target>..<target>` check (true → the
-- repo's default merge target has local commits not yet on origin, and an origin exists to push
-- to), refreshed alongside branch_merged on every worktree report → the bar shows a "Push" button
-- next to the "✓ In main" chip. `push_status` drives the button while it runs: 'pending' (queued
-- for the assigned runner's next heartbeat) → 'pushed' (pushed_at set) | 'error' (push_error
-- carries git's message / the reason). All NULL until reported / clicked; no backfill.
ALTER TABLE "session" ADD COLUMN "target_unpushed" BOOLEAN;
ALTER TABLE "session" ADD COLUMN "push_status" TEXT;
ALTER TABLE "session" ADD COLUMN "push_error" TEXT;
ALTER TABLE "session" ADD COLUMN "push_requested_at" TIMESTAMP(3);
ALTER TABLE "session" ADD COLUMN "pushed_at" TIMESTAMP(3);
