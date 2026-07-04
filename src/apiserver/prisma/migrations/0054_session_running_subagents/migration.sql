-- Denormalized set of a session's still-running sub-agents (Task/Agent tool). Holds the
-- tool_use ids of sub-agent launches that haven't reported a terminal `<task-notification>`
-- (background_task) yet: added on launch, removed on completion, cleared on (re)spawn.
-- The Agent tool runs async — its launch tool_result ("Async agent launched") lands at once
-- and the parent then streams its own top-scope system progress events, so `last_tool_use`
-- can't stay 'Agent'. This set lets the session list show "Running Agent…" the whole time a
-- sub-agent is in flight, without scanning run_event. No backfill — empty for existing
-- sessions (only meaningful while a session is live anyway).
ALTER TABLE "session" ADD COLUMN "running_subagents" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
