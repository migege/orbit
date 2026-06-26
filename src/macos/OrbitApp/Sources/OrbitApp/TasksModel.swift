import Foundation
import Observation
import OrbitKit

/// Drives the Tasks section: the list (filter/sort via the verified OrbitKit `TaskListLogic`)
/// plus the selected task's detail and the mutating actions. Orchestration + UI state only —
/// all list/sort/pill logic lives in OrbitKit. One instance is owned by `AppModel` so the list
/// (middle column) and the detail (right column) share it.
@MainActor
@Observable
final class TasksModel {
    private(set) var items: [TaskItem] = []
    var filter: TaskFilter = .all
    var sort: TaskSort = .created
    var descending = true

    private(set) var detail: TaskItem?
    private(set) var loading = false
    var errorText: String?

    private let api: APIClient

    init(baseURL: URL, tokenStore: TokenStore) {
        api = APIClient(baseURL: baseURL, tokenStore: tokenStore)
    }

    /// The list after filter + sort.
    var visible: [TaskItem] {
        TaskListLogic.sorted(TaskListLogic.filtered(items, filter), by: sort, descending: descending)
    }

    func load() async {
        loading = true
        defer { loading = false }
        do { items = try await api.tasks() }
        catch { errorText = friendly(error) }
    }

    func loadDetail(_ id: String) async {
        do { detail = try await api.task(id) }
        catch { errorText = friendly(error) }
    }

    // MARK: actions — each refreshes the list, and the open task's detail when it's the one changed.

    func execute(_ id: String) async { await mutate(id) { try await self.api.executeTask(id) } }

    func deleteTask(_ id: String) async {
        await mutate(nil) { try await self.api.deleteTask(id) }
        if detail?.id == id { detail = nil }
    }

    func setStatus(_ id: String, _ status: TaskStatus) async {
        await mutate(id) { _ = try await self.api.updateTask(id, UpdateTaskRequest(status: status)) }
    }

    func setAutoRun(_ id: String, _ on: Bool) async {
        await mutate(id) { _ = try await self.api.updateTask(id, UpdateTaskRequest(autoRunWhenReady: on)) }
    }

    func setAssignee(_ id: String, _ assigneeId: String?) async {
        let field: FieldUpdate<String> = assigneeId.map { .set($0) } ?? .clear
        await mutate(id) { _ = try await self.api.updateTask(id, UpdateTaskRequest(assigneeId: field)) }
    }

    func addComment(_ id: String, _ body: String) async {
        await mutate(id) { try await self.api.addTaskComment(taskID: id, CreateTaskCommentRequest(body: body)) }
    }

    func addDependency(_ id: String, dependsOn: String) async {
        await mutate(id) { try await self.api.addTaskDependency(taskID: id, AddDependencyRequest(dependsOnTaskId: dependsOn)) }
    }

    func removeDependency(_ id: String, dependsOn: String) async {
        await mutate(id) { try await self.api.removeTaskDependency(taskID: id, dependsOnTaskID: dependsOn) }
    }

    /// Run a mutating call, then refresh the list and — if `refreshDetailID` is the open task —
    /// its detail, so the panel reflects the change immediately.
    private func mutate(_ refreshDetailID: String?, _ op: @escaping () async throws -> Void) async {
        do {
            try await op()
            await load()
            if let rid = refreshDetailID, detail?.id == rid { await loadDetail(rid) }
        } catch { errorText = friendly(error) }
    }

    private func friendly(_ error: Error) -> String {
        if case APIError.unauthorized = error { return "Session expired — sign in again." }
        return "Request failed — check your connection."
    }
}
