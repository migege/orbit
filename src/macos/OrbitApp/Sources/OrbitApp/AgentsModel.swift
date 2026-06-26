import Foundation
import Observation
import OrbitKit

/// Drives the Agents section: the list (grouped by runner via OrbitKit `AgentListLogic`) plus
/// edit/delete. Owned by `AppModel` so the list and the edit form share it. Also fetches runner
/// names (best-effort) for the group headers.
@MainActor
@Observable
final class AgentsModel {
    private(set) var items: [Agent] = []
    private(set) var runnerNames: [String: String] = [:]
    private(set) var loading = false
    var errorText: String?

    private let api: APIClient

    init(baseURL: URL, tokenStore: TokenStore) {
        api = APIClient(baseURL: baseURL, tokenStore: tokenStore)
    }

    var groups: [AgentGroup] { AgentListLogic.grouped(items) }

    /// Display name for a group header (runner display-name, else id, else "Shared" for host).
    func runnerLabel(_ runnerId: String?) -> String {
        guard let id = runnerId else { return "Shared" }
        return runnerNames[id] ?? id
    }

    func agent(_ id: String) -> Agent? { items.first { $0.id == id } }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await api.agents()
            // Best-effort: map runner ids → names for the group headers.
            if let runners = try? await api.runners() {
                runnerNames = Dictionary(runners.map { ($0.id, $0.displayName ?? $0.name) },
                                         uniquingKeysWith: { a, _ in a })
            }
        } catch { errorText = friendly(error) }
    }

    func save(_ id: String, _ req: UpdateAgentRequest) async {
        do { _ = try await api.updateAgent(id, req); await load() }
        catch { errorText = friendly(error) }
    }

    func delete(_ id: String) async {
        do { try await api.deleteAgent(id); await load() }
        catch { errorText = friendly(error) }
    }

    private func friendly(_ error: Error) -> String {
        if case APIError.unauthorized = error { return "Session expired — sign in again." }
        return "Request failed — check your connection."
    }
}
