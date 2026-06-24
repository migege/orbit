-- Remember the chosen merge target per agent. When the user switches the merge target in the
-- status bar's branch dropdown, that branch is stored here so every session of the agent
-- defaults its "Merge to <branch>" button to it. NULL = the default (runner auto-detects main,
-- else master). No backfill: NULL for existing agents, so they keep the plain main default.
ALTER TABLE "agent" ADD COLUMN "default_merge_target" TEXT;
