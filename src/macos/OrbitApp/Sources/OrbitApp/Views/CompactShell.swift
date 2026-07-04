#if os(iOS)
import SwiftUI
import OrbitKit

/// iPhone (compact width) navigation shell: a tab bar over the app's sections. iPad regular width
/// keeps `MainView`'s three-column split (see the size-class switch in the iOS app entry).
///
/// Each tab is its own `NavigationSplitView`, not a `NavigationStack`, on purpose: an iOS `List`
/// with a single-selection binding only drives navigation from a *tap* when it's the sidebar of a
/// split view (a plain stack needs edit mode). Collapsing the split on compact turns that same
/// selection into a push — so every existing `List(selection:)` sidebar + detail pair from the
/// iPad shell is reused verbatim, no row rewrites. Selection state is the shared `AppModel`'s, so
/// picking a row and drilling in works identically to the iPad columns.
struct CompactShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: tabBinding) {
            // ACTIVE — live sessions → console
            NavigationSplitView {
                SectionContent(section: .active, sessionSelection: $model.selectedSessionID)
                    .onChange(of: model.selectedSessionID, initial: true) { _, _ in
                        model.scheduleConsoleActivate()
                    }
                    .refreshable { await model.loadSessions() }
            } detail: {
                SectionDetail(section: .active)
            }
            .tabItem { Label(AppSection.active.title, systemImage: AppSection.active.systemImage) }
            .badge(model.groups.needsYou.count)
            .tag(CompactTab.active)

            // TASKS — task list → detail
            NavigationSplitView {
                TasksListView()
                    .refreshable { await model.tasks?.load() }
            } detail: {
                TaskDetailView()
            }
            .tabItem { Label(AppSection.tasks.title, systemImage: AppSection.tasks.systemImage) }
            .tag(CompactTab.tasks)

            // AGENTS — agent list → the agent's sessions → console (three levels, like the iPad)
            NavigationSplitView {
                AgentListCompact()
            } content: {
                AgentContentColumn()
            } detail: {
                AgentConsoleDetail()
            }
            .tabItem { Label(AppSection.agents.title, systemImage: AppSection.agents.systemImage) }
            .tag(CompactTab.agents)

            // RUNNERS — runner list → detail
            NavigationSplitView {
                RunnersListView()
                    .refreshable { await model.runners?.load() }
            } detail: {
                RunnerDetailView()
            }
            .tabItem { Label(AppSection.runners.title, systemImage: AppSection.runners.systemImage) }
            .tag(CompactTab.runners)

            // MORE — the single-pane / low-traffic sections
            NavigationStack {
                MoreList()
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(CompactTab.more)
        }
        .task { model.startPolling() }
        // New session (the AgentPanes toolbar's compose button). On compact the three-column split
        // collapses to a stack whose detail pane is only *pushed* by a session selection — flipping
        // `composingAgentSession` can't reach it, so the button looked dead. Present the draft
        // composer as a sheet instead (the iPhone-idiomatic compose surface, à la Mail). Attached to
        // the TabView so it presents regardless of the active tab (e.g. a future ⌘N deep link).
        .sheet(isPresented: $model.composingAgentSession) { AgentComposeSheet() }
    }

    /// Bridge the tab bar to `selectedSection` so deep links (which set the section) land on the
    /// right tab; Skills/Settings/Admin all live behind the More tab.
    private var tabBinding: Binding<CompactTab> {
        Binding(
            get: { CompactTab(section: model.selectedSection) },
            set: { model.selectedSection = $0.section }
        )
    }
}

/// The four primary tabs. Skills, Settings and Admin fold into `.more`.
enum CompactTab: Hashable {
    case active, tasks, agents, runners, more

    init(section: AppSection) {
        switch section {
        case .active:  self = .active
        case .tasks:   self = .tasks
        case .agents:  self = .agents
        case .runners: self = .runners
        case .skills, .settings, .admin: self = .more
        }
    }

    /// The section a tap on this tab selects (the More tab defaults to Settings' section group).
    var section: AppSection {
        switch self {
        case .active:  return .active
        case .tasks:   return .tasks
        case .agents:  return .agents
        case .runners: return .runners
        case .more:    return .settings
        }
    }
}

/// The Agents sidebar for compact width — the runner-grouped agent list that lives in the iPad
/// main sidebar, pulled out as a standalone list so the Agents tab can drill agent → sessions →
/// console. Selecting an agent clears any stale session/compose state, mirroring the iPad sidebar.
private struct AgentListCompact: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedAgentID) {
            if let agents = model.agents, !agents.items.isEmpty {
                ForEach(agents.groups) { group in
                    Section(agents.runnerLabel(group.runnerId)) {
                        ForEach(group.agents) { a in
                            AgentRowView(agent: a).tag(a.id)
                        }
                    }
                }
            } else {
                Text(model.agents?.loading == true ? "Loading…" : "No agents")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Agents")
        .refreshable { await model.agents?.load() }
        .onChange(of: model.selectedAgentID) { _, _ in
            model.selectedAgentSessionID = nil
            model.composingAgentSession = false
        }
        .task { await model.agents?.load() }
    }
}

/// The new-session draft composer, presented as a sheet on compact width. The regular-width shell
/// renders this same `NewSessionView` inline in the Agents detail pane; the collapsed compact split
/// can't reach that pane from a boolean, so we surface it as a modal instead. Sending creates the
/// session, then dismisses and selects it so its console pushes onto the Agents stack.
private struct AgentComposeSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let registry = model.consoleRegistry, let agents = model.agents,
                   let id = model.selectedAgentID, let agent = agents.agent(id) {
                    NewSessionView(agent: agent, registry: registry) { session in
                        model.composingAgentSession = false
                        model.selectedAgentSessionID = session.id
                    }
                    .navigationTitle(agent.name)
                } else {
                    ContentUnavailableView("Select an agent", systemImage: "person.2")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.composingAgentSession = false }
                }
            }
        }
    }
}

/// Root of the More tab: the sections that don't warrant their own tab. Skills and Settings are
/// single-pane; Admin is role-gated and links to the user list.
private struct MoreList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            NavigationLink {
                SkillsView()
            } label: {
                Label(AppSection.skills.title, systemImage: AppSection.skills.systemImage)
            }
            NavigationLink {
                SettingsView()
            } label: {
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
            }
            if model.user?.role == "ADMIN" {
                NavigationLink {
                    AdminUsersView()
                } label: {
                    Label(AppSection.admin.title, systemImage: AppSection.admin.systemImage)
                }
            }
        }
        .navigationTitle("More")
    }
}
#endif
