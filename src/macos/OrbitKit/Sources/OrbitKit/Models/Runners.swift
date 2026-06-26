import Foundation

// Runner write DTOs + the skill/command payload, mirroring runners.controller / runners.service.
// Skills are NOT a standalone endpoint: runners report what they found on disk via heartbeat and
// it rides the GET /runners payload as `skills` / `commands` (both `SlashCommandInfo[]`). The
// `Runner` response struct (DTOs.swift) is extended with those plus `displayName`.

/// A slash command (`.claude/commands/*.md`) or skill (`.claude/skills/<name>/SKILL.md`) a runner
/// discovered. `agentId` empty/nil ⇒ host-level (shared by all agents); else project-scoped to
/// that agent's workDir — the web composer scopes `/` autocomplete to host + the session's agent.
public struct SlashCommandInfo: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let description: String?
    public let type: String?        // "command" | "skill"
    public let agentId: String?
    /// Stable identity for SwiftUI lists (the same name can exist host-level and per-agent).
    public var id: String { "\(agentId ?? "host"):\(type ?? ""):\(name)" }
}

/// PATCH /runners/:id — `displayName` empty string clears the alias (falls back to machine name);
/// nil omits. `maxConcurrent` 1…64.
public struct UpdateRunnerRequest: Encodable, Sendable {
    public var displayName: String?
    public var maxConcurrent: Int?
    public init(displayName: String? = nil, maxConcurrent: Int? = nil) {
        self.displayName = displayName
        self.maxConcurrent = maxConcurrent
    }
}

/// POST /runners/enrollment-tokens
public struct CreateEnrollmentTokenRequest: Encodable, Sendable {
    public var label: String?
    public var ttlHours: Int?
    public init(label: String? = nil, ttlHours: Int? = nil) {
        self.label = label
        self.ttlHours = ttlHours
    }
}

/// POST /runners/:id/rotate-token → the new token, returned exactly once.
public struct RotateTokenResponse: Codable, Equatable, Sendable {
    public let token: String
}

/// Enrollment token. `token` is present only on create (one-shot); the list omits it.
public struct EnrollmentTokenInfo: Codable, Equatable, Sendable {
    public let id: String?
    public let token: String?
    public let label: String?
    public let expiresAt: String?
}

/// Generic `{ ok: true }` ack (delete runner, etc.).
public struct OkResponse: Codable, Equatable, Sendable {
    public let ok: Bool?
}

/// One rate-limit window of Claude's subscription quota (mirrors shared `PlanUsageWindow`).
public struct PlanUsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double   // 0…100
    public let resetsAt: String?
}

/// Claude subscription quota for a runner's account — same numbers as Claude Code's `/usage`.
/// Any window may be absent (plan lacks it, or the runner uses an API key / is too old).
public struct PlanUsage: Codable, Equatable, Sendable {
    public let fiveHour: PlanUsageWindow?
    public let sevenDay: PlanUsageWindow?
    public let sevenDayOpus: PlanUsageWindow?
    public let sevenDaySonnet: PlanUsageWindow?
    public let fetchedAt: String?
}

/// One labelled window for the composer's plan-usage popover (mirrors web's PLAN_USAGE_ROWS).
public struct PlanUsageRow: Equatable, Sendable, Identifiable {
    public let key: String
    public let label: String
    public let window: PlanUsageWindow
    public var id: String { key }
    /// Utilization rounded to a whole percent (0…100).
    public var percent: Int { Int(window.utilization.rounded()) }
}

public extension PlanUsage {
    /// Present windows in Claude `/usage` order — the binding 5-hour window first, then weekly.
    var rows: [PlanUsageRow] {
        [("fiveHour", "5-hour limit", fiveHour),
         ("sevenDay", "Weekly · all models", sevenDay),
         ("sevenDayOpus", "Weekly · Opus", sevenDayOpus),
         ("sevenDaySonnet", "Weekly · Sonnet", sevenDaySonnet)]
            .compactMap { key, label, window in
                window.map { PlanUsageRow(key: key, label: label, window: $0) }
            }
    }

    /// The binding window's percent (5-hour when present, else the first available), or nil
    /// when the runner reports no windows.
    var primaryPercent: Int? { rows.first?.percent }
}
