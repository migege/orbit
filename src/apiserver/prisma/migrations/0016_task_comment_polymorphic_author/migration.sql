-- TaskComment.author becomes polymorphic (USER | AGENT), mirroring Task.creatorType/creatorId.
-- The runner MCP path lets an agent author comments, which cannot satisfy the User FK.

-- DropForeignKey
ALTER TABLE "task_comment" DROP CONSTRAINT "task_comment_author_id_fkey";

-- AlterTable: add author_type. Backfill existing rows to USER via a temporary default,
-- then drop the default so inserts must supply it (matches the schema, no @default).
ALTER TABLE "task_comment" ADD COLUMN "author_type" "creator_type" NOT NULL DEFAULT 'USER';
ALTER TABLE "task_comment" ALTER COLUMN "author_type" DROP DEFAULT;
