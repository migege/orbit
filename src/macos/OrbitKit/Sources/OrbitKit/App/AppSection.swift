import Foundation

/// Top-level navigation sections, mirroring the web AppShell nav. Pure data — titles and SF
/// Symbol names are just strings — so it lives in OrbitKit and is unit-tested; the SwiftUI
/// sidebar renders `visible(isAdmin:)`. Admin is role-gated like the web's route guard.
public enum AppSection: String, CaseIterable, Sendable, Identifiable {
    case active, tasks, agents, skills, runners, settings, admin

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active:   return "Active"
        case .tasks:    return "Tasks"
        case .agents:   return "Agents"
        case .skills:   return "Skills"
        case .runners:  return "Runners"
        case .settings: return "Settings"
        case .admin:    return "Admin"
        }
    }

    /// SF Symbol for the sidebar row.
    public var systemImage: String {
        switch self {
        case .active:   return "bolt.horizontal.circle"
        case .tasks:    return "checklist"
        case .agents:   return "person.2"
        case .skills:   return "wand.and.stars"
        case .runners:  return "desktopcomputer"
        case .settings: return "gearshape"
        case .admin:    return "lock.shield"
        }
    }

    /// Admin-area sections are hidden from non-admins (mirrors the web route guard).
    public var adminOnly: Bool { self == .admin }

    /// Sections to show for a role, in canonical order (Active first).
    public static func visible(isAdmin: Bool) -> [AppSection] {
        allCases.filter { !$0.adminOnly || isAdmin }
    }

    /// The section a deep-link / notification `Route` lands in.
    public static func forRoute(_ route: Route) -> AppSection {
        switch route {
        case .active, .session: return .active
        case .task:             return .tasks
        case .runner:           return .runners
        }
    }
}
