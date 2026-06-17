-- Rename all DB identifiers to snake_case to match @@map/@map in schema.prisma.
-- Prisma Client field names are unchanged; this only renames physical DB objects.
-- All statements are RENAME (data-preserving); no DROP/CREATE.

-- enum types
ALTER TYPE "RunStatus" RENAME TO "run_status";
ALTER TYPE "RunnerStatus" RENAME TO "runner_status";

-- tables
ALTER TABLE "Activity" RENAME TO "activity";
ALTER TABLE "Agent" RENAME TO "agent";
ALTER TABLE "ConversationTurn" RENAME TO "conversation_turn";
ALTER TABLE "DeviceEnrollment" RENAME TO "device_enrollment";
ALTER TABLE "EnrollmentToken" RENAME TO "enrollment_token";
ALTER TABLE "LlmUsage" RENAME TO "llm_usage";
ALTER TABLE "RunEvent" RENAME TO "run_event";
ALTER TABLE "Runner" RENAME TO "runner";
ALTER TABLE "Session" RENAME TO "session";
ALTER TABLE "ToolCall" RENAME TO "tool_call";
ALTER TABLE "User" RENAME TO "user";

-- columns
ALTER TABLE "activity" RENAME COLUMN "actorId" TO "actor_id";
ALTER TABLE "activity" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "agent" RENAME COLUMN "appendSystemPrompt" TO "append_system_prompt";
ALTER TABLE "agent" RENAME COLUMN "systemPrompt" TO "system_prompt";
ALTER TABLE "agent" RENAME COLUMN "allowedTools" TO "allowed_tools";
ALTER TABLE "agent" RENAME COLUMN "disallowedTools" TO "disallowed_tools";
ALTER TABLE "agent" RENAME COLUMN "permissionMode" TO "permission_mode";
ALTER TABLE "agent" RENAME COLUMN "maxTurns" TO "max_turns";
ALTER TABLE "agent" RENAME COLUMN "maxBudgetUsd" TO "max_budget_usd";
ALTER TABLE "agent" RENAME COLUMN "mcpConfig" TO "mcp_config";
ALTER TABLE "agent" RENAME COLUMN "targetRunnerId" TO "target_runner_id";
ALTER TABLE "agent" RENAME COLUMN "targetLabels" TO "target_labels";
ALTER TABLE "agent" RENAME COLUMN "ownerId" TO "owner_id";
ALTER TABLE "agent" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "conversation_turn" RENAME COLUMN "sessionId" TO "session_id";
ALTER TABLE "conversation_turn" RENAME COLUMN "clientTurnId" TO "client_turn_id";
ALTER TABLE "conversation_turn" RENAME COLUMN "deliveredAt" TO "delivered_at";
ALTER TABLE "conversation_turn" RENAME COLUMN "leaseDeadlineAt" TO "lease_deadline_at";
ALTER TABLE "conversation_turn" RENAME COLUMN "answeredAt" TO "answered_at";
ALTER TABLE "conversation_turn" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "device_enrollment" RENAME COLUMN "deviceCodeHash" TO "device_code_hash";
ALTER TABLE "device_enrollment" RENAME COLUMN "userCode" TO "user_code";
ALTER TABLE "device_enrollment" RENAME COLUMN "maxConcurrent" TO "max_concurrent";
ALTER TABLE "device_enrollment" RENAME COLUMN "runnerId" TO "runner_id";
ALTER TABLE "device_enrollment" RENAME COLUMN "runnerToken" TO "runner_token";
ALTER TABLE "device_enrollment" RENAME COLUMN "approvedById" TO "approved_by_id";
ALTER TABLE "device_enrollment" RENAME COLUMN "approvedAt" TO "approved_at";
ALTER TABLE "device_enrollment" RENAME COLUMN "expiresAt" TO "expires_at";
ALTER TABLE "device_enrollment" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "enrollment_token" RENAME COLUMN "tokenHash" TO "token_hash";
ALTER TABLE "enrollment_token" RENAME COLUMN "ownerId" TO "owner_id";
ALTER TABLE "enrollment_token" RENAME COLUMN "expiresAt" TO "expires_at";
ALTER TABLE "enrollment_token" RENAME COLUMN "usedAt" TO "used_at";
ALTER TABLE "enrollment_token" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "llm_usage" RENAME COLUMN "sessionId" TO "session_id";
ALTER TABLE "llm_usage" RENAME COLUMN "inputTokens" TO "input_tokens";
ALTER TABLE "llm_usage" RENAME COLUMN "outputTokens" TO "output_tokens";
ALTER TABLE "llm_usage" RENAME COLUMN "cacheCreationInputTokens" TO "cache_creation_input_tokens";
ALTER TABLE "llm_usage" RENAME COLUMN "cacheReadInputTokens" TO "cache_read_input_tokens";
ALTER TABLE "llm_usage" RENAME COLUMN "costUsd" TO "cost_usd";
ALTER TABLE "llm_usage" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "run_event" RENAME COLUMN "sessionId" TO "session_id";
ALTER TABLE "run_event" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "runner" RENAME COLUMN "ownerId" TO "owner_id";
ALTER TABLE "runner" RENAME COLUMN "maxConcurrent" TO "max_concurrent";
ALTER TABLE "runner" RENAME COLUMN "tokenHash" TO "token_hash";
ALTER TABLE "runner" RENAME COLUMN "lastHeartbeatAt" TO "last_heartbeat_at";
ALTER TABLE "runner" RENAME COLUMN "enrolledAt" TO "enrolled_at";
ALTER TABLE "runner" RENAME COLUMN "displayName" TO "display_name";
ALTER TABLE "session" RENAME COLUMN "ownerId" TO "owner_id";
ALTER TABLE "session" RENAME COLUMN "creatorId" TO "creator_id";
ALTER TABLE "session" RENAME COLUMN "assignedRunnerId" TO "assigned_runner_id";
ALTER TABLE "session" RENAME COLUMN "agentId" TO "agent_id";
ALTER TABLE "session" RENAME COLUMN "claudeSessionId" TO "claude_session_id";
ALTER TABLE "session" RENAME COLUMN "permissionMode" TO "permission_mode";
ALTER TABLE "session" RENAME COLUMN "sumInputTokens" TO "sum_input_tokens";
ALTER TABLE "session" RENAME COLUMN "sumOutputTokens" TO "sum_output_tokens";
ALTER TABLE "session" RENAME COLUMN "sumCacheRead" TO "sum_cache_read";
ALTER TABLE "session" RENAME COLUMN "sumCacheWrite" TO "sum_cache_write";
ALTER TABLE "session" RENAME COLUMN "numTurns" TO "num_turns";
ALTER TABLE "session" RENAME COLUMN "costUsd" TO "cost_usd";
ALTER TABLE "session" RENAME COLUMN "lastTurnAt" TO "last_turn_at";
ALTER TABLE "session" RENAME COLUMN "cancelRequestedAt" TO "cancel_requested_at";
ALTER TABLE "session" RENAME COLUMN "startedAt" TO "started_at";
ALTER TABLE "session" RENAME COLUMN "finishedAt" TO "finished_at";
ALTER TABLE "session" RENAME COLUMN "createdAt" TO "created_at";
ALTER TABLE "session" RENAME COLUMN "updatedAt" TO "updated_at";
ALTER TABLE "tool_call" RENAME COLUMN "sessionId" TO "session_id";
ALTER TABLE "tool_call" RENAME COLUMN "isError" TO "is_error";
ALTER TABLE "tool_call" RENAME COLUMN "startedAt" TO "started_at";
ALTER TABLE "tool_call" RENAME COLUMN "finishedAt" TO "finished_at";
ALTER TABLE "user" RENAME COLUMN "passwordHash" TO "password_hash";
ALTER TABLE "user" RENAME COLUMN "createdAt" TO "created_at";

-- primary/foreign key constraints (pkey rename also renames its backing index)
ALTER TABLE "activity" RENAME CONSTRAINT "Activity_pkey" TO "activity_pkey";
ALTER TABLE "agent" RENAME CONSTRAINT "Agent_ownerId_fkey" TO "agent_owner_id_fkey";
ALTER TABLE "agent" RENAME CONSTRAINT "Agent_pkey" TO "agent_pkey";
ALTER TABLE "conversation_turn" RENAME CONSTRAINT "ConversationTurn_pkey" TO "conversation_turn_pkey";
ALTER TABLE "conversation_turn" RENAME CONSTRAINT "ConversationTurn_sessionId_fkey" TO "conversation_turn_session_id_fkey";
ALTER TABLE "device_enrollment" RENAME CONSTRAINT "DeviceEnrollment_pkey" TO "device_enrollment_pkey";
ALTER TABLE "enrollment_token" RENAME CONSTRAINT "EnrollmentToken_ownerId_fkey" TO "enrollment_token_owner_id_fkey";
ALTER TABLE "enrollment_token" RENAME CONSTRAINT "EnrollmentToken_pkey" TO "enrollment_token_pkey";
ALTER TABLE "llm_usage" RENAME CONSTRAINT "LlmUsage_pkey" TO "llm_usage_pkey";
ALTER TABLE "llm_usage" RENAME CONSTRAINT "LlmUsage_sessionId_fkey" TO "llm_usage_session_id_fkey";
ALTER TABLE "run_event" RENAME CONSTRAINT "RunEvent_pkey" TO "run_event_pkey";
ALTER TABLE "run_event" RENAME CONSTRAINT "RunEvent_sessionId_fkey" TO "run_event_session_id_fkey";
ALTER TABLE "runner" RENAME CONSTRAINT "Runner_ownerId_fkey" TO "runner_owner_id_fkey";
ALTER TABLE "runner" RENAME CONSTRAINT "Runner_pkey" TO "runner_pkey";
ALTER TABLE "session" RENAME CONSTRAINT "Session_agentId_fkey" TO "session_agent_id_fkey";
ALTER TABLE "session" RENAME CONSTRAINT "Session_assignedRunnerId_fkey" TO "session_assigned_runner_id_fkey";
ALTER TABLE "session" RENAME CONSTRAINT "Session_creatorId_fkey" TO "session_creator_id_fkey";
ALTER TABLE "session" RENAME CONSTRAINT "Session_ownerId_fkey" TO "session_owner_id_fkey";
ALTER TABLE "session" RENAME CONSTRAINT "Session_pkey" TO "session_pkey";
ALTER TABLE "tool_call" RENAME CONSTRAINT "ToolCall_pkey" TO "tool_call_pkey";
ALTER TABLE "tool_call" RENAME CONSTRAINT "ToolCall_sessionId_fkey" TO "tool_call_session_id_fkey";
ALTER TABLE "user" RENAME CONSTRAINT "User_pkey" TO "user_pkey";

-- remaining indexes (unique _key and plain _idx; _pkey handled above)
ALTER INDEX "Agent_ownerId_idx" RENAME TO "agent_owner_id_idx";
ALTER INDEX "ConversationTurn_sessionId_clientTurnId_key" RENAME TO "conversation_turn_session_id_client_turn_id_key";
ALTER INDEX "ConversationTurn_sessionId_seq_key" RENAME TO "conversation_turn_session_id_seq_key";
ALTER INDEX "ConversationTurn_sessionId_status_idx" RENAME TO "conversation_turn_session_id_status_idx";
ALTER INDEX "DeviceEnrollment_deviceCodeHash_key" RENAME TO "device_enrollment_device_code_hash_key";
ALTER INDEX "DeviceEnrollment_userCode_key" RENAME TO "device_enrollment_user_code_key";
ALTER INDEX "EnrollmentToken_tokenHash_key" RENAME TO "enrollment_token_token_hash_key";
ALTER INDEX "LlmUsage_sessionId_idx" RENAME TO "llm_usage_session_id_idx";
ALTER INDEX "RunEvent_sessionId_seq_idx" RENAME TO "run_event_session_id_seq_idx";
ALTER INDEX "RunEvent_sessionId_seq_key" RENAME TO "run_event_session_id_seq_key";
ALTER INDEX "Runner_ownerId_idx" RENAME TO "runner_owner_id_idx";
ALTER INDEX "Session_assignedRunnerId_status_idx" RENAME TO "session_assigned_runner_id_status_idx";
ALTER INDEX "Session_ownerId_idx" RENAME TO "session_owner_id_idx";
ALTER INDEX "Session_status_idx" RENAME TO "session_status_idx";
ALTER INDEX "ToolCall_sessionId_idx" RENAME TO "tool_call_session_id_idx";
ALTER INDEX "User_email_key" RENAME TO "user_email_key";
