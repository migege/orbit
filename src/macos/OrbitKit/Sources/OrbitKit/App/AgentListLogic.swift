import Foundation

// Pure logic for the Agents page: grouping by runner and the "effective model" display. UI-free
// so it's unit-tested; the SwiftUI list renders `grouped` and shows `effectiveModel` per row.

public struct AgentGroup: Equatable, Sendable, Identifiable {
    public let runnerId: String?
    public let agents: [Agent]
    public var id: String { runnerId ?? "host" }
}

public enum AgentListLogic {
    /// Group agents by their runner, preserving first-seen runner order; host-level agents
    /// (no runnerId) sink to the bottom — like the web's "Shared" group.
    public static func grouped(_ agents: [Agent]) -> [AgentGroup] {
        var order: [String] = []
        var map: [String: [Agent]] = [:]
        var host: [Agent] = []
        for a in agents {
            if let rid = a.runnerId {
                if map[rid] == nil { order.append(rid); map[rid] = [] }
                map[rid]?.append(a)
            } else {
                host.append(a)
            }
        }
        var groups = order.map { AgentGroup(runnerId: $0, agents: map[$0] ?? []) }
        if !host.isEmpty { groups.append(AgentGroup(runnerId: nil, agents: host)) }
        return groups
    }

    /// Agents flattened in sidebar display order — runner groups (first-seen) then host "Shared".
    /// This is the order ⌘1…⌘9 index into, so it stays in lockstep with what `grouped` renders.
    public static func ordered(_ agents: [Agent]) -> [Agent] {
        grouped(agents).flatMap(\.agents)
    }

    /// The model an agent actually runs: an `ANTHROPIC_MODEL` env override wins over the static
    /// `model` field (an agent can point at a DeepSeek-compatible endpoint via env), then the app
    /// default. Mirrors web RunnerDetailPage's `effectiveModel`.
    public static func effectiveModel(model: String?, env: [String: String]?) -> String {
        if let override = env?["ANTHROPIC_MODEL"], !override.isEmpty { return override }
        return model ?? AgentDefaults.defaultModelID
    }
}
