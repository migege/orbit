-- Per-agent default reasoning effort. When a new session's create request omits `effort`, the
-- server seeds the session from the agent's value (mirroring how model/permission_mode default
-- from the agent). NULL = no per-agent default, so the session falls back to the model's default
-- effort exactly as today. Existing agents get NULL → unchanged behavior until an effort is set.
ALTER TABLE "agent" ADD COLUMN "effort" TEXT;
