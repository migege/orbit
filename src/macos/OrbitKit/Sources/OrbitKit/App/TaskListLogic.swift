import Foundation

// Pure list logic for the Tasks page — filtering, the status-overlay sort rank, and the
// status-pill derivation — mirroring web TaskListView. UI-free so it's unit-tested; the SwiftUI
// list just renders `filtered`/`sorted` and `TaskListLogic.pill`.

public enum TaskFilter: String, CaseIterable, Sendable, Identifiable {
    case all, ongoing, failed, done, cancelled
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all:       return "All"
        case .ongoing:   return "Ongoing"
        case .failed:    return "Failed"
        case .done:      return "Done"
        case .cancelled: return "Cancelled"
        }
    }
    /// `ongoing` = OPEN or IN_PROGRESS; the rest are exact-status (matches web `matchesFilter`).
    public func matches(_ status: TaskStatus) -> Bool {
        switch self {
        case .all:       return true
        case .ongoing:   return status == .open || status == .inProgress
        case .failed:    return status == .failed
        case .done:      return status == .done
        case .cancelled: return status == .cancelled
        }
    }
}

public enum TaskSort: String, CaseIterable, Sendable, Identifiable {
    case created, status, title, assignee
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .created:  return "Created"
        case .status:   return "Status"
        case .title:    return "Title"
        case .assignee: return "Assignee"
        }
    }
}

/// The per-row pill: the live session overlay (running/queued) wins over the lifecycle label,
/// since "executing now" is the ground truth the agent-maintained status can lag behind.
public enum TaskPillKind: String, Sendable, Equatable {
    case running, queued, done, inProgress, open, failed, cancelled
}

public struct TaskPill: Equatable, Sendable {
    public let kind: TaskPillKind
    public let label: String
}

public enum TaskListLogic {
    /// Lifecycle rank (1…5) matching web STATUS_ORDER; overlay ranks (running/queued) sit below.
    private static func lifecycleRank(_ s: TaskStatus) -> Int {
        switch s {
        case .inProgress: return 1
        case .failed:     return 2
        case .open:       return 3
        case .done:       return 4
        case .cancelled:  return 5
        }
    }

    /// Sort rank: running (0) then queued (1) outrank any lifecycle status (+1 keeps lifecycle
    /// below both overlays), so the live task never intermixes with the queue. Mirrors web.
    public static func statusRank(_ t: TaskItem) -> Int {
        if t.running == true { return 0 }
        if t.queued == true { return 1 }
        return lifecycleRank(t.status) + 1
    }

    public static func filtered(_ items: [TaskItem], _ filter: TaskFilter) -> [TaskItem] {
        filter == .all ? items : items.filter { filter.matches($0.status) }
    }

    /// Stable sort by the chosen field; equal pairs keep input order (the caller pre-orders by
    /// createdAt-desc, which the server already does). `descending` flips the comparison.
    public static func sorted(_ items: [TaskItem], by sort: TaskSort, descending: Bool) -> [TaskItem] {
        let cmp: (TaskItem, TaskItem) -> Int
        switch sort {
        case .created:  cmp = { compareStr($0.createdAt, $1.createdAt) }
        case .status:   cmp = { statusRank($0) - statusRank($1) }
        // Numeric collation so "Unit 9" sorts before "Unit 73", not lexicographically.
        case .title:    cmp = { compareStr($0.title, $1.title, numeric: true) }
        case .assignee: cmp = { compareStr($0.assignee?.name, $1.assignee?.name, numeric: true) }
        }
        return items.enumerated().sorted { a, b in
            let c = descending ? -cmp(a.element, b.element) : cmp(a.element, b.element)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.element)
    }

    private static func compareStr(_ a: String?, _ b: String?, numeric: Bool = false) -> Int {
        let l = a ?? "", r = b ?? ""
        let opts: String.CompareOptions = numeric ? [.numeric, .caseInsensitive] : []
        switch l.compare(r, options: opts) {
        case .orderedAscending:  return -1
        case .orderedDescending: return 1
        case .orderedSame:       return 0
        }
    }

    /// Status pill: running/queued overlay wins, else the lifecycle label.
    public static func pill(_ t: TaskItem) -> TaskPill {
        if t.running == true { return TaskPill(kind: .running, label: "Running") }
        if t.queued == true  { return TaskPill(kind: .queued, label: "Queued") }
        switch t.status {
        case .done:       return TaskPill(kind: .done, label: "Done")
        case .inProgress: return TaskPill(kind: .inProgress, label: "In progress")
        case .open:       return TaskPill(kind: .open, label: "Open")
        case .failed:     return TaskPill(kind: .failed, label: "Failed")
        case .cancelled:  return TaskPill(kind: .cancelled, label: "Cancelled")
        }
    }
}
