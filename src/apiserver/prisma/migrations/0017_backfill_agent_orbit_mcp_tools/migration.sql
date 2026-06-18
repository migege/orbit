-- The `orbit mcp` server is now injected into every session. Under DONT_ASK its tools
-- are blocked unless allow-listed, so existing agents need the orbit allowlist entry
-- too (new agents get it in AgentsService.create). allowed_tools is a jsonb array.
UPDATE "agent"
SET "allowed_tools" = "allowed_tools" || '["mcp__orbit__*"]'::jsonb
WHERE NOT ("allowed_tools" @> '["mcp__orbit__*"]'::jsonb);
