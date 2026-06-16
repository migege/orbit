-- AlterEnum: interactive-session run states (Route B).
-- ADD VALUE is run first and the new values are NOT used elsewhere in this
-- migration, so it is safe on PostgreSQL 12+ (incl. inside a transaction).
ALTER TYPE "RunStatus" ADD VALUE 'AWAITING_INPUT';
ALTER TYPE "RunStatus" ADD VALUE 'INTERRUPTED';

-- AlterTable
ALTER TABLE "Task" ADD COLUMN "interactive" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Task" ADD COLUMN "sessionUuid" TEXT;
ALTER TABLE "Task" ADD COLUMN "activeRunId" TEXT;

-- AlterTable
ALTER TABLE "TaskRun" ADD COLUMN "interactive" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "TaskRun" ADD COLUMN "lastTurnAt" TIMESTAMP(3);
ALTER TABLE "TaskRun" ADD COLUMN "idleDeadlineAt" TIMESTAMP(3);
ALTER TABLE "TaskRun" ADD COLUMN "cancelRequestedAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "TaskRun_runnerId_status_idx" ON "TaskRun"("runnerId", "status");

-- CreateTable
CREATE TABLE "ConversationTurn" (
    "id" TEXT NOT NULL,
    "runId" TEXT NOT NULL,
    "seq" INTEGER NOT NULL,
    "clientTurnId" TEXT NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'message',
    "content" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "deliveredAt" TIMESTAMP(3),
    "leaseDeadlineAt" TIMESTAMP(3),
    "answeredAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConversationTurn_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ConversationTurn_runId_clientTurnId_key" ON "ConversationTurn"("runId", "clientTurnId");

-- CreateIndex
CREATE UNIQUE INDEX "ConversationTurn_runId_seq_key" ON "ConversationTurn"("runId", "seq");

-- CreateIndex
CREATE INDEX "ConversationTurn_runId_status_idx" ON "ConversationTurn"("runId", "status");

-- AddForeignKey
ALTER TABLE "ConversationTurn" ADD CONSTRAINT "ConversationTurn_runId_fkey" FOREIGN KEY ("runId") REFERENCES "TaskRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
