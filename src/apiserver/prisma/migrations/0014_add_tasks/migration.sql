-- CreateEnum
CREATE TYPE "task_status" AS ENUM ('OPEN', 'IN_PROGRESS', 'DONE', 'CANCELLED');

-- CreateEnum
CREATE TYPE "creator_type" AS ENUM ('USER', 'AGENT');

-- AlterTable
ALTER TABLE "session" ADD COLUMN     "task_id" UUID;

-- CreateTable
CREATE TABLE "task" (
    "id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "status" "task_status" NOT NULL DEFAULT 'OPEN',
    "owner_id" UUID NOT NULL,
    "creator_type" "creator_type" NOT NULL,
    "creator_id" UUID NOT NULL,
    "assignee_id" UUID,
    "due_date" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "task_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "task_comment" (
    "id" UUID NOT NULL,
    "task_id" UUID NOT NULL,
    "author_id" UUID NOT NULL,
    "body" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "task_comment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "task_owner_id_idx" ON "task"("owner_id");

-- CreateIndex
CREATE INDEX "task_assignee_id_idx" ON "task"("assignee_id");

-- CreateIndex
CREATE INDEX "task_status_idx" ON "task"("status");

-- CreateIndex
CREATE INDEX "task_creator_type_creator_id_idx" ON "task"("creator_type", "creator_id");

-- CreateIndex
CREATE INDEX "task_comment_task_id_created_at_idx" ON "task_comment"("task_id", "created_at");

-- AddForeignKey
ALTER TABLE "session" ADD CONSTRAINT "session_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "task"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "task" ADD CONSTRAINT "task_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "task" ADD CONSTRAINT "task_assignee_id_fkey" FOREIGN KEY ("assignee_id") REFERENCES "agent"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "task_comment" ADD CONSTRAINT "task_comment_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "task"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "task_comment" ADD CONSTRAINT "task_comment_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
