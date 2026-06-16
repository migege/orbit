-- Migrate every id primary key and uuid foreign-key/reference column from TEXT
-- to the native `uuid` type (16 bytes, faster/smaller indexes). New rows are
-- generated as UUIDv7 by the Prisma client (@default(uuid(7))); existing v4
-- values are preserved unchanged.
--
-- Values are converted in place with `USING "col"::uuid` (no DROP/recreate, no
-- data loss). FK constraints are dropped and re-added around the type changes
-- because a column's type can't be altered while a FK depends on it. The whole
-- file runs in one transaction, so a failure rolls back cleanly.

-- 1. Drop FK constraints on the columns being retyped.
ALTER TABLE "Agent" DROP CONSTRAINT "Agent_ownerId_fkey";
ALTER TABLE "ConversationTurn" DROP CONSTRAINT "ConversationTurn_sessionId_fkey";
ALTER TABLE "EnrollmentToken" DROP CONSTRAINT "EnrollmentToken_ownerId_fkey";
ALTER TABLE "LlmUsage" DROP CONSTRAINT "LlmUsage_sessionId_fkey";
ALTER TABLE "RunEvent" DROP CONSTRAINT "RunEvent_sessionId_fkey";
ALTER TABLE "Runner" DROP CONSTRAINT "Runner_ownerId_fkey";
ALTER TABLE "Session" DROP CONSTRAINT "Session_agentId_fkey";
ALTER TABLE "Session" DROP CONSTRAINT "Session_assignedRunnerId_fkey";
ALTER TABLE "Session" DROP CONSTRAINT "Session_creatorId_fkey";
ALTER TABLE "Session" DROP CONSTRAINT "Session_ownerId_fkey";
ALTER TABLE "ToolCall" DROP CONSTRAINT "ToolCall_sessionId_fkey";

-- 2. Retype primary keys and uuid columns in place.
ALTER TABLE "User" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;

ALTER TABLE "Runner" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "Runner" ALTER COLUMN "ownerId" SET DATA TYPE UUID USING "ownerId"::uuid;

ALTER TABLE "EnrollmentToken" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "EnrollmentToken" ALTER COLUMN "ownerId" SET DATA TYPE UUID USING "ownerId"::uuid;

ALTER TABLE "DeviceEnrollment" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "DeviceEnrollment" ALTER COLUMN "runnerId" SET DATA TYPE UUID USING "runnerId"::uuid;
ALTER TABLE "DeviceEnrollment" ALTER COLUMN "approvedById" SET DATA TYPE UUID USING "approvedById"::uuid;

ALTER TABLE "Agent" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "Agent" ALTER COLUMN "ownerId" SET DATA TYPE UUID USING "ownerId"::uuid;
ALTER TABLE "Agent" ALTER COLUMN "targetRunnerId" SET DATA TYPE UUID USING "targetRunnerId"::uuid;

ALTER TABLE "Session" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "Session" ALTER COLUMN "ownerId" SET DATA TYPE UUID USING "ownerId"::uuid;
ALTER TABLE "Session" ALTER COLUMN "creatorId" SET DATA TYPE UUID USING "creatorId"::uuid;
ALTER TABLE "Session" ALTER COLUMN "assignedRunnerId" SET DATA TYPE UUID USING "assignedRunnerId"::uuid;
ALTER TABLE "Session" ALTER COLUMN "agentId" SET DATA TYPE UUID USING "agentId"::uuid;

ALTER TABLE "RunEvent" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "RunEvent" ALTER COLUMN "sessionId" SET DATA TYPE UUID USING "sessionId"::uuid;

ALTER TABLE "ToolCall" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "ToolCall" ALTER COLUMN "sessionId" SET DATA TYPE UUID USING "sessionId"::uuid;

ALTER TABLE "LlmUsage" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "LlmUsage" ALTER COLUMN "sessionId" SET DATA TYPE UUID USING "sessionId"::uuid;

ALTER TABLE "ConversationTurn" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "ConversationTurn" ALTER COLUMN "sessionId" SET DATA TYPE UUID USING "sessionId"::uuid;

ALTER TABLE "Activity" ALTER COLUMN "id" SET DATA TYPE UUID USING "id"::uuid;
ALTER TABLE "Activity" ALTER COLUMN "actorId" SET DATA TYPE UUID USING "actorId"::uuid;

-- 3. Re-add the FK constraints with their original referential actions.
ALTER TABLE "Runner" ADD CONSTRAINT "Runner_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE "EnrollmentToken" ADD CONSTRAINT "EnrollmentToken_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE "Agent" ADD CONSTRAINT "Agent_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE "Session" ADD CONSTRAINT "Session_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE "Session" ADD CONSTRAINT "Session_creatorId_fkey" FOREIGN KEY ("creatorId") REFERENCES "User"("id") ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE "Session" ADD CONSTRAINT "Session_assignedRunnerId_fkey" FOREIGN KEY ("assignedRunnerId") REFERENCES "Runner"("id") ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE "Session" ADD CONSTRAINT "Session_agentId_fkey" FOREIGN KEY ("agentId") REFERENCES "Agent"("id") ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE "RunEvent" ADD CONSTRAINT "RunEvent_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "Session"("id") ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE "ToolCall" ADD CONSTRAINT "ToolCall_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "Session"("id") ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE "LlmUsage" ADD CONSTRAINT "LlmUsage_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "Session"("id") ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE "ConversationTurn" ADD CONSTRAINT "ConversationTurn_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "Session"("id") ON UPDATE CASCADE ON DELETE CASCADE;
