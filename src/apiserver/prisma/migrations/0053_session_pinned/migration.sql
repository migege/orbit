-- "Pin to top": a personal, per-owner flag that floats a session above unpinned ones in the
-- session list (the list query ORDER BYs `pinned_at IS NOT NULL` first, then last activity).
-- null = not pinned. POST /sessions/:id/pin sets it to now(); DELETE clears it. Ordering only —
-- it never changes visibility (archived_at/deleted_at) and is never sent to the runner. NULL for
-- all existing rows → unpinned, so the list keeps its current time order until something is pinned.
ALTER TABLE "session" ADD COLUMN "pinned_at" TIMESTAMP(3);
