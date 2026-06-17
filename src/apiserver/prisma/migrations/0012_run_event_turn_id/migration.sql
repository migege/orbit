-- Tag each output event with the conversation_turn that produced it (NULL for
-- session-level events). No FK: run_event is high-volume append-only (cf. activity)
-- and both tables already cascade-delete with session.
ALTER TABLE "run_event" ADD COLUMN "turn_id" UUID;
CREATE INDEX "run_event_turn_id_idx" ON "run_event"("turn_id");
