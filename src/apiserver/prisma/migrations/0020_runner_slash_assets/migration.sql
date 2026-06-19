-- Slash commands / skills a runner discovered on its disk, reported via heartbeat
-- and surfaced to the web composer's `/` autocomplete. Each is a JSON array of
-- { name, description?, type? } (mirrors @orbit/shared SlashCommandInfo). NULL = not
-- yet reported (e.g. an older runner that predates this feature).
ALTER TABLE "runner" ADD COLUMN "available_commands" JSONB;
ALTER TABLE "runner" ADD COLUMN "available_skills" JSONB;
