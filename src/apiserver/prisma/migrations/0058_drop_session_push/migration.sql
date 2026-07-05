-- Revert of 0057_session_push. The standalone "Push to origin" button on the worktree status
-- bar is removed: Merge already pushes to origin when it tracks the target (and reconciles
-- divergence), so a separate Push added little and couldn't proactively detect divergence anyway.
-- Drop the columns 0057 introduced. Their data is feature-only (push status/timestamps) and is
-- safe to discard. IF EXISTS keeps this idempotent on a DB where 0057 never landed.
ALTER TABLE "session" DROP COLUMN IF EXISTS "target_unpushed";
ALTER TABLE "session" DROP COLUMN IF EXISTS "push_status";
ALTER TABLE "session" DROP COLUMN IF EXISTS "push_error";
ALTER TABLE "session" DROP COLUMN IF EXISTS "push_requested_at";
ALTER TABLE "session" DROP COLUMN IF EXISTS "pushed_at";
