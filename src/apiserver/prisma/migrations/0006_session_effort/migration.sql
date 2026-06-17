-- Per-session effort-level override (interactive sessions, Route B).
-- NULL omits --effort, so claude uses the model's default effort.
ALTER TABLE "Task" ADD COLUMN "effort" TEXT;
