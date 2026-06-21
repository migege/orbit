-- Terminal-but-resumable session state. A session whose claude process was gracefully
-- torn down (the reaper recycled it for idle/task-done, or the user ended it) used to
-- settle to CANCELLED, indistinguishable from a real cancel without reading end_reason.
-- PARKED makes "dormant, send a message to resume" a first-class status. No backfill:
-- legacy CANCELLED rows stay put (they're already resumable via TERMINAL) and the UI
-- renders an unknown end_reason as dormant.
ALTER TYPE "run_status" ADD VALUE IF NOT EXISTS 'PARKED';
