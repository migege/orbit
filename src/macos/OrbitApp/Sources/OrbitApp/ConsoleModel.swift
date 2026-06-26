import Foundation
import Observation
import UniformTypeIdentifiers
import OrbitKit

struct PendingAttachment: Identifiable, Equatable, Sendable {
    let id: String
    let filename: String
}

/// Active "Chat about this" reply: the composer's next send resolves this pending question as a
/// deny+message (claude reads it as in-turn feedback) instead of starting a fresh turn.
struct QuestionReply: Equatable, Sendable {
    let approvalID: String
    let question: String
}

/// Drives one open session: the reconnecting SSE consume loop (folded through the verified
/// `TranscriptReducer`) plus the interactive actions — send/queue/interrupt, tool approvals,
/// and worktree commit/merge. All decision logic lives in OrbitKit (ComposerLogic / Approvals);
/// this is the orchestration + UI-facing state.
@MainActor
@Observable
final class ConsoleModel {
    let sessionID: String
    let agentID: String?
    private(set) var state = TranscriptState()
    private(set) var connected = false

    // composer
    var composerText = ""
    var shellMode = false
    var modelID = AgentDefaults.defaultModelID
    var permissionMode: PermissionMode = .default
    private(set) var pendingAttachments: [PendingAttachment] = []
    private(set) var sending = false
    /// Set while replying to a pending question via "Chat about this" (see send()).
    private(set) var replyContext: QuestionReply?

    // `/` command & skill autocomplete (the `+` menu opens it scoped). `slashItems` is the
    // runner-reported set already narrowed to host-level + this session's agent (see loadSlashItems).
    private(set) var slashItems: [SlashCommandInfo] = []
    var slashScope: String?   // nil = both kinds; "command"/"skill" when opened from the + menu

    // worktree
    private(set) var diff: [FilePatch] = []
    private(set) var worktreeBusy = false

    var statusMessage: String?

    private var reducer = TranscriptReducer()
    private let stream: EventStreaming
    private let api: APIClient

    init(sessionID: String, agentID: String? = nil, baseURL: URL, tokenStore: TokenStore) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.api = APIClient(baseURL: baseURL, tokenStore: tokenStore)
        #if os(macOS)
        self.stream = URLSessionEventStream(baseURL: baseURL, token: { tokenStore.token(for: baseURL) })
        #else
        self.stream = MockEventStream([])
        #endif
    }

    // MARK: live stream

    func run() async {
        Task { await loadSlashItems() }   // one-shot; concurrent with the stream connect
        // Durable approvals aren't in the replayed stream (the `approval_request` nudge rides
        // seq 0, live-only) — fetch them once on open so a prompt already pending (e.g. an
        // AskUserQuestion awaiting an answer) surfaces. Decoupled from the stream; cancels with run().
        let approvalsSeed = Task { [weak self] in await self?.refreshApprovals() }
        defer { approvalsSeed.cancel() }
        var attempt = 0
        while !Task.isCancelled {
            do {
                connected = true
                for try await ev in stream.events(sessionID: sessionID, sinceSeq: reducer.state.maxSeq) {
                    reducer.apply(ev)
                    scheduleStatePublish()
                    attempt = 0
                }
                connected = false
                publishStateNow()
                try? await Task.sleep(nanoseconds: 300_000_000)
            } catch is CancellationError {
                publishStateNow()
                return
            } catch {
                connected = false
                attempt += 1
                if attempt > 12 { return }
                let ms = min(15_000, 500 * (1 << min(attempt, 5)))
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            }
        }
    }

    // Coalesce transcript publishes. A busy replay or live stream would otherwise copy the full
    // state and re-render the whole transcript PER event (≈ O(N²) over the session), pegging the
    // main actor — opening a busy session froze the app near 100% CPU. Events still fold into the
    // reducer eagerly; the rendered snapshot is pushed to the view at most ~20×/sec.
    private var publishScheduled = false
    private func scheduleStatePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            self.publishScheduled = false
            self.state = self.reducer.state
            self.reconcileReplyContext()
        }
    }
    private func publishStateNow() {
        publishScheduled = false
        state = reducer.state
        reconcileReplyContext()
    }

    /// Drop the chat-reply context if its question was resolved another way (an option was picked,
    /// or an SSE `approval_resolved` arrived) — mirrors the web clearing replyTo when it leaves.
    private func reconcileReplyContext() {
        if let r = replyContext, !state.pendingApprovals.contains(where: { $0.id == r.approvalID }) {
            replyContext = nil
        }
    }

    // MARK: composer

    var availability: SendAvailability { ComposerLogic.availability(status: state.status) }

    var canSend: Bool {
        guard !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !sending else { return false }
        if replyContext != nil { return true }   // a question reply always sends (deny+message)
        return availability != .blocked
    }

    // MARK: `/` autocomplete

    var hasCommands: Bool { slashItems.contains { $0.type == "command" } }
    var hasSkills: Bool { slashItems.contains { $0.type == "skill" } }
    var slashToken: String? { ComposerSlash.token(in: composerText) }
    var slashMatches: [SlashCommandInfo] {
        ComposerSlash.matches(items: slashItems, token: slashToken, scope: slashScope)
    }

    /// Fold every runner's reported commands + skills, scoped to host-level + this session's
    /// agent (web parity). Best-effort: a failure just leaves the menu empty.
    func loadSlashItems() async {
        guard let runners = try? await api.runners() else { return }
        let all = runners.flatMap { ($0.commands ?? []) + ($0.skills ?? []) }
        slashItems = ComposerSlash.scoped(items: all, agentID: agentID)
    }

    /// `+` menu → Command/Skill: pop the menu scoped to one kind by inserting a `/`.
    func openSlash(scope: String) {
        slashScope = scope
        composerText = ComposerSlash.opening(text: composerText)
    }

    /// Replace the active `/token` with `/name `; clears the scope so the next manual `/` shows both.
    func pickSlash(_ name: String) {
        composerText = ComposerSlash.pick(text: composerText, name: name)
        slashScope = nil
    }

    func send() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        // "Chat about this": resolve the pending question as a deny+message so claude reads the
        // text as in-turn feedback and continues — not a fresh turn. (Mirrors the web reroute.)
        if let reply = replyContext {
            composerText = ""
            replyContext = nil
            await replyToQuestion(approvalID: reply.approvalID, text: text)
            return
        }
        let clientTurnId = UUID().uuidString
        let attachmentIds = pendingAttachments.map(\.id)

        // Optimistic bubble; reconciled by the server's `user` event (same clientTurnId).
        reducer.addOptimisticUser(clientTurnId: clientTurnId, text: text, attachmentIds: attachmentIds)
        state = reducer.state
        composerText = ""
        pendingAttachments = []

        sending = true
        defer { sending = false }
        do {
            if ComposerLogic.shouldResume(status: state.status) {
                _ = try await api.resume(sessionID: sessionID,
                                         ResumeRequest(clientTurnId: clientTurnId, content: text,
                                                       kind: shellMode ? "shell" : "message",
                                                       model: modelID, permissionMode: permissionMode.rawValue))
            } else {
                _ = try await api.sendTurn(sessionID: sessionID,
                                           ComposerLogic.makeTurn(clientTurnId: clientTurnId, text: text,
                                                                  shell: shellMode, attachmentIds: attachmentIds))
            }
        } catch {
            statusMessage = "Send failed — \(error)"
        }
    }

    func interrupt() async {
        do { try await api.interrupt(sessionID: sessionID) }
        catch { statusMessage = "Interrupt failed" }
    }

    /// `+` menu → Attach image / Upload file: read a picked file, enforce the size cap (web
    /// parity), and upload it via the existing attachment path.
    func attachFile(url: URL) async {
        guard let data = try? Data(contentsOf: url) else {
            statusMessage = "Couldn't read \(url.lastPathComponent)"
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        if let reason = Attachments.rejectReason(mimeType: mime, byteCount: data.count) {
            statusMessage = reason
            return
        }
        await attach(filename: url.lastPathComponent, mimeType: mime, data: data)
    }

    func attach(filename: String, mimeType: String, data: Data) async {
        do {
            let id = try await api.uploadAttachment(sessionID: sessionID, filename: filename,
                                                    mimeType: mimeType, data: data)
            pendingAttachments.append(PendingAttachment(id: id, filename: filename))
        } catch {
            statusMessage = "Upload failed"
        }
    }

    func removeAttachment(_ att: PendingAttachment) {
        pendingAttachments.removeAll { $0.id == att.id }
    }

    // MARK: approvals

    /// Begin a "Chat about this" reply to a pending question: the next composer send resolves it
    /// as a deny+message instead of a fresh turn (see send()). The card stays until then.
    func startChatReply(approvalID: String, question: String) {
        replyContext = QuestionReply(approvalID: approvalID, question: question)
    }

    func cancelChatReply() { replyContext = nil }

    /// Resolve a pending question conversationally (deny + the typed text → claude reads it as
    /// in-turn feedback). Optimistic-removes the card; re-seeds from REST on failure.
    private func replyToQuestion(approvalID: String, text: String) async {
        sending = true
        defer { sending = false }
        reducer.removeApproval(id: approvalID)
        publishStateNow()
        let req = ApprovalDecisionRequest(behavior: .deny, message: text, answers: nil, rememberRule: nil)
        do { try await api.decideApproval(sessionID: sessionID, approvalID: approvalID, req) }
        catch {
            statusMessage = "Reply failed"
            await refreshApprovals()
        }
    }

    func decide(_ approval: PendingApproval, behavior: ApprovalBehavior,
                answers: [String: [String]]? = nil, remember: Bool = false) async {
        var rule: PermissionRule?
        if remember, behavior == .allow, let input = approval.input {
            rule = Approvals.rememberRule(toolName: approval.toolName ?? "", input: input)
        }
        // Optimistic: drop the card now (the SSE `approval_resolved` echoes this). On failure,
        // re-seed from REST so it reappears rather than silently vanishing.
        reducer.removeApproval(id: approval.id)
        publishStateNow()
        let req = ApprovalDecisionRequest(behavior: behavior, message: nil, answers: answers, rememberRule: rule)
        do { try await api.decideApproval(sessionID: sessionID, approvalID: approval.id, req) }
        catch {
            statusMessage = "Approval failed"
            await refreshApprovals()
        }
    }

    /// Fetch durable pending approvals (the REST source of truth) and fold them in. Without this
    /// a prompt that predates the stream — or whose seq-0 nudge landed during a reconnect gap —
    /// never surfaces, since those nudges aren't replayed.
    private func refreshApprovals() async {
        guard let infos = try? await api.approvals(sessionID: sessionID) else { return }
        reducer.seedApprovals(infos.map {
            PendingApproval(id: $0.id, kind: Approvals.kind(toolName: $0.toolName),
                            toolName: $0.toolName, input: $0.input)
        })
        publishStateNow()
    }

    // MARK: worktree

    func loadDiff() async {
        worktreeBusy = true
        defer { worktreeBusy = false }
        do { diff = try await api.diff(sessionID: sessionID).patches }
        catch { /* keep last */ }
    }

    func commit() async {
        worktreeBusy = true
        defer { worktreeBusy = false }
        do { try await api.commit(sessionID: sessionID); statusMessage = "Commit requested" }
        catch { statusMessage = "Commit failed" }
    }

    func merge(target: String?) async {
        worktreeBusy = true
        defer { worktreeBusy = false }
        do { try await api.merge(sessionID: sessionID, targetBranch: target); statusMessage = "Merge requested" }
        catch { statusMessage = "Merge failed" }
    }
}
