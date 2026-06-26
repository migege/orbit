import SwiftUI
import OrbitKit

// Batch D: the Agents page — list grouped by runner (middle column) + an edit form (right
// column), reading the shared `AgentsModel` off `AppModel`. Grouping + effective-model logic
// come from the verified OrbitKit `AgentListLogic`; pickers reuse `AgentDefaults`. SwiftUI here
// is parse-checked only — verify on a Mac.
//
// IA note: the web edits agents *inside* the Runner detail page (an agent belongs to a runner);
// this surfaces a flatter top-level Agents list. The form fields mirror the web's exactly.

/// Middle column: agents grouped by runner; selection drives the edit form.
struct AgentsListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let agents = model.agents {
            List(selection: $model.selectedAgentID) {
                ForEach(agents.groups) { group in
                    Section(agents.runnerLabel(group.runnerId)) {
                        ForEach(group.agents) { a in
                            AgentRowView(agent: a).tag(a.id)
                        }
                    }
                }
            }
            .overlay {
                if agents.items.isEmpty {
                    ContentUnavailableView(agents.loading ? "Loading…" : "No agents",
                                           systemImage: "person.2")
                }
            }
            .navigationTitle("Agents")
            .task { await agents.load() }
        } else {
            ProgressView()
        }
    }
}

struct AgentRowView: View {
    let agent: Agent
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(agent.name).lineLimit(1)
                if agent.enabled == false {
                    Text("disabled").font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(AgentDefaults.friendlyName(AgentListLogic.effectiveModel(model: agent.model, env: agent.env))
                 + (agent.workDir.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

/// Right column: the selected agent's edit form (or a prompt to pick one).
struct AgentFormView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let agents = model.agents, let id = model.selectedAgentID, let a = agents.agent(id) {
            AgentFormContent(agents: agents, agent: a).id(a.id)
        } else {
            ContentUnavailableView("Select an agent", systemImage: "person.2",
                                   description: Text("Edit an agent's model, instructions, and more here."))
        }
    }
}

/// The edit form. Fields mirror the web RunnerDetailPage agent form: name, model, permission
/// mode, Instructions (appendSystemPrompt), working directory, enabled. Empty Instructions /
/// workDir omit the key (no change) — matching the web, which sends `undefined` when blank.
struct AgentFormContent: View {
    let agents: AgentsModel
    let agent: Agent

    @State private var name = ""
    @State private var model = ""
    @State private var mode: PermissionMode = .dontAsk
    @State private var instructions = ""
    @State private var workDir = ""
    @State private var enabled = true

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("e.g. tea-cli builder"))

                Picker("Model", selection: $model) {
                    // Surface a non-standard saved model (e.g. an env-overridden endpoint) so the
                    // picker still shows the current value rather than going blank.
                    if !AgentDefaults.models.contains(where: { $0.id == model }) {
                        Text(model.isEmpty ? "—" : model).tag(model)
                    }
                    ForEach(AgentDefaults.models) { Text($0.name).tag($0.id) }
                }

                Picker("Permission mode", selection: $mode) {
                    ForEach(AgentDefaults.permissionModes, id: \.self) {
                        Text(AgentDefaults.label($0)).tag($0)
                    }
                }

                Toggle("Enabled", isOn: $enabled)
            }

            Section("Instructions") {
                TextEditor(text: $instructions)
                    .frame(minHeight: 90)
                    .font(.body)
                Text("Added to this agent's system prompt on every run (optional).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Working directory") {
                TextField("Path", text: $workDir,
                          prompt: Text("/path/to/project on the runner (optional)"))
            }

            if let env = agent.env, !env.isEmpty {
                Section("Environment") {
                    ForEach(env.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        LabeledContent(k, value: v)
                    }
                    Text("Env editing is coming in a follow-up.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Save changes") { save() }
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    Button("Delete", role: .destructive) {
                        Task { await agents.delete(agent.id) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(agent.name)
        .onAppear(perform: prefill)
    }

    private func prefill() {
        name = agent.name
        model = agent.model ?? AgentDefaults.defaultModelID
        mode = PermissionMode(rawValue: agent.permissionMode ?? "dontAsk") ?? .dontAsk
        instructions = agent.appendSystemPrompt ?? ""
        workDir = agent.workDir ?? ""
        enabled = agent.enabled ?? true
    }

    private func save() {
        let req = UpdateAgentRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            appendSystemPrompt: instructions.isEmpty ? nil : instructions,
            permissionMode: mode.rawValue,
            workDir: workDir.isEmpty ? nil : workDir,
            enabled: enabled
        )
        Task { await agents.save(agent.id, req) }
    }
}
