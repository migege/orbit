import XCTest
@testable import OrbitKit

/// The Phase-0 gate: a recorded session transcript folded by the reducer must produce exactly
/// the expected bubbles / approvals / background state — with seq dedup and optimistic
/// reconciliation. This is the test that de-risks the whole native-console bet.
final class TranscriptReducerTests: XCTestCase {

    /// A representative turn: user → streamed assistant text → tool call+result → more text →
    /// a resolved approval → a background process → a DUPLICATE durable event → turn end.
    private func recordedSession() -> [RunEvent] {
        [
            RunEvent(seq: 1, type: .system, payload: .object(["text": .string("session started")])),
            RunEvent(seq: 2, type: .user, payload: .object(["text": .string("List the files"),
                                                            "clientTurnId": .string("c1")])),
            RunEvent(seq: 0, type: .textDelta, payload: .object(["delta": .string("I'll ")])),
            RunEvent(seq: 0, type: .textDelta, payload: .object(["delta": .string("list them.")])),
            RunEvent(seq: 3, type: .assistant, payload: .object(["text": .string("I'll list them.")])),
            RunEvent(seq: 4, type: .toolUse, payload: .object(["toolUseId": .string("t1"),
                                                               "name": .string("Bash"),
                                                               "input": .object(["command": .string("ls")])])),
            RunEvent(seq: 5, type: .toolResult, payload: .object(["toolUseId": .string("t1"),
                                                                  "content": .string("a.txt\nb.txt")])),
            RunEvent(seq: 0, type: .textDelta, payload: .object(["delta": .string("Done.")])),
            RunEvent(seq: 6, type: .assistant, payload: .object(["text": .string("Done.")])),
            RunEvent(seq: 0, type: .approvalRequest, payload: .object(["id": .string("ap1"),
                                                                       "toolName": .string("Bash"),
                                                                       "input": .object(["command": .string("rm x")])])),
            RunEvent(seq: 0, type: .approvalResolved, payload: .object(["id": .string("ap1")])),
            RunEvent(seq: 7, type: .backgroundTask, payload: .object(["id": .string("bg1"),
                                                                      "status": .string("running"),
                                                                      "command": .string("npm test")])),
            RunEvent(seq: 0, type: .backgroundOutput, payload: .object(["id": .string("bg1"),
                                                                        "output": .string("PASS")])),
            RunEvent(seq: 8, type: .backgroundTask, payload: .object(["id": .string("bg1"),
                                                                      "status": .string("completed")])),
            // Duplicate of seq 3 (e.g. an over-eager reconnect replay): must be deduped.
            RunEvent(seq: 3, type: .assistant, payload: .object(["text": .string("I'll list them.")])),
            RunEvent(seq: 9, type: .turnEnd, payload: .object(["status": .string("AWAITING_INPUT")])),
        ]
    }

    func testFoldsRecordedSession() {
        var r = TranscriptReducer()
        for ev in recordedSession() { r.apply(ev) }
        let s = r.state

        // 4 transcript items: user, assistant, tool, assistant (system is lifecycle, not an item).
        XCTAssertEqual(s.items.count, 4, "expected user + assistant + tool + assistant")

        XCTAssertEqual(s.items[0].asUser?.text, "List the files")
        XCTAssertEqual(s.items[0].asUser?.pending, false)

        // Streaming deltas folded into the bubble, then replaced by the durable full text.
        XCTAssertEqual(s.items[1].asAssistant?.displayText, "I'll list them.")
        XCTAssertEqual(s.items[1].asAssistant?.isFinalized, true)

        let tool = s.items[2].asTool
        XCTAssertEqual(tool?.id, "t1")
        XCTAssertEqual(tool?.name, "Bash")
        XCTAssertEqual(tool?.result, "a.txt\nb.txt")
        XCTAssertEqual(tool?.status, .ok)

        XCTAssertEqual(s.items[3].asAssistant?.displayText, "Done.")

        // Approval requested then resolved → nothing pending.
        XCTAssertTrue(s.pendingApprovals.isEmpty)

        // One background process, completed, with its output tail captured.
        XCTAssertEqual(s.background.count, 1)
        XCTAssertEqual(s.background.first?.status, "completed")
        XCTAssertEqual(s.background.first?.outputTail, "PASS")
        XCTAssertEqual(s.background.first?.command, "npm test")

        XCTAssertEqual(s.status, .awaitingInput)
        // maxSeq tracks the durable high-water (turn_end seq 9) — the reconnect cursor.
        XCTAssertEqual(s.maxSeq, 9)
    }

    func testDurableDedupKeepsSingleItem() {
        var r = TranscriptReducer()
        let ev = RunEvent(seq: 42, type: .assistant, payload: .object(["text": .string("hi")]))
        r.apply(ev)
        r.apply(ev)                              // replayed on reconnect
        XCTAssertEqual(r.state.items.count, 1)
        XCTAssertEqual(r.state.maxSeq, 42)
    }

    func testOptimisticUserReconciledByClientTurnId() {
        var r = TranscriptReducer()
        r.addOptimisticUser(clientTurnId: "c9", text: "deploy please")
        XCTAssertEqual(r.state.items.count, 1)
        XCTAssertEqual(r.state.items[0].asUser?.pending, true)

        // Server echoes the durable user turn carrying the same clientTurnId.
        r.apply(RunEvent(seq: 10, type: .user, payload: .object(["text": .string("deploy please"),
                                                                 "clientTurnId": .string("c9")])))
        XCTAssertEqual(r.state.items.count, 1, "must reconcile, not duplicate")
        XCTAssertEqual(r.state.items[0].asUser?.pending, false)
    }

    /// Real-world path: the runner's durable `user` event echoes the server `turnId` (top-level),
    /// NOT `clientTurnId` in the payload. The optimistic bubble — tagged with that turnId from the
    /// POST /turns response — must reconcile by turnId instead of duplicating. (Regression: macOS
    /// previously matched only on the never-echoed clientTurnId, so every sent message doubled.)
    func testOptimisticUserReconciledByServerTurnId() {
        var r = TranscriptReducer()
        r.addOptimisticUser(clientTurnId: "c9", text: "ask me a question")
        r.setOptimisticTurnId(clientTurnId: "c9", turnId: "turn-77")   // from POST /turns response
        XCTAssertEqual(r.state.items[0].asUser?.pending, true)

        r.apply(RunEvent(seq: 10, type: .user, turnId: "turn-77",
                         payload: .object(["text": .string("ask me a question")])))
        XCTAssertEqual(r.state.items.count, 1, "must reconcile by server turnId, not duplicate")
        XCTAssertEqual(r.state.items[0].asUser?.pending, false)
    }

    /// A message sent while another turn is in flight is flagged `queued` so the bubble reads
    /// "Queued" instead of "Sending…" (web parity); reconciling the durable event clears `pending`
    /// (which hides the indicator regardless of `queued`). An idle send leaves `queued` false.
    func testOptimisticUserCarriesQueuedFlag() {
        var r = TranscriptReducer()
        r.addOptimisticUser(clientTurnId: "c1", text: "do this next", queued: true)
        XCTAssertEqual(r.state.items[0].asUser?.pending, true)
        XCTAssertEqual(r.state.items[0].asUser?.queued, true)

        r.addOptimisticUser(clientTurnId: "c2", text: "right away")   // idle send → default false
        XCTAssertEqual(r.state.items[1].asUser?.queued, false)
    }

    /// The durable `user` event carries `attachments` ([{id,mime,name}]) and a `ts` — both must
    /// land on the bubble so it can render image thumbnails / file chips and a relative time
    /// (web parity; the runner echoes `attachments`, not `attachmentIds`).
    func testUserEventParsesAttachmentsAndTimestamp() {
        var r = TranscriptReducer()
        r.apply(RunEvent(seq: 7, type: .user, ts: "2026-06-26T10:00:00Z",
                         payload: .object([
                            "text": .string("look at this"),
                            "attachments": .array([
                                .object(["id": .string("att1"), "mime": .string("image/png"), "name": .string("a.png")]),
                                .object(["id": .string("att2"), "mime": .string("application/pdf")]),
                                .object(["mime": .string("image/png")]),   // no id → dropped
                            ]),
                         ])))
        let bubble = r.state.items[0].asUser
        XCTAssertEqual(bubble?.attachments.map(\.id), ["att1", "att2"])
        XCTAssertEqual(bubble?.attachments.first?.mime, "image/png")
        XCTAssertEqual(bubble?.attachments.first?.isImage, true)
        XCTAssertEqual(bubble?.attachments.last?.isImage, false)   // application/pdf
        XCTAssertEqual(bubble?.ts, "2026-06-26T10:00:00Z")
    }

    /// An optimistic image bubble (id-only, mime unknown) reconciles to the durable event, which
    /// supplies the real mime + a timestamp — without duplicating the bubble.
    func testOptimisticBubbleAdoptsDurableAttachmentsAndTs() {
        var r = TranscriptReducer()
        r.addOptimisticUser(clientTurnId: "c1", text: "see screenshot",
                            attachments: [TurnAttachment(id: "att1")])
        r.setOptimisticTurnId(clientTurnId: "c1", turnId: "t1")
        XCTAssertNil(r.state.items[0].asUser?.attachments.first?.mime)
        XCTAssertEqual(r.state.items[0].asUser?.attachments.first?.isImage, true)   // unknown mime ⇒ image

        r.apply(RunEvent(seq: 9, type: .user, ts: "2026-06-26T12:00:00Z", turnId: "t1",
                         payload: .object([
                            "text": .string("see screenshot"),
                            "attachments": .array([
                                .object(["id": .string("att1"), "mime": .string("image/jpeg")]),
                            ]),
                         ])))
        XCTAssertEqual(r.state.items.count, 1, "reconcile, not duplicate")
        XCTAssertEqual(r.state.items[0].asUser?.pending, false)
        XCTAssertEqual(r.state.items[0].asUser?.attachments.first?.mime, "image/jpeg")
        XCTAssertEqual(r.state.items[0].asUser?.ts, "2026-06-26T12:00:00Z")
    }

    func testTextDeltaWithoutDurableFinalizeStillRenders() {
        var r = TranscriptReducer()
        r.apply(RunEvent(seq: 0, type: .textDelta, payload: .object(["delta": .string("partial ")])))
        r.apply(RunEvent(seq: 0, type: .textDelta, payload: .object(["delta": .string("answer")])))
        r.apply(RunEvent(seq: 5, type: .turnEnd, payload: .object(["status": .string("AWAITING_INPUT")])))
        XCTAssertEqual(r.state.items.count, 1)
        XCTAssertEqual(r.state.items[0].asAssistant?.displayText, "partial answer")
    }

    /// A live AskUserQuestion nudge carries its questions nested under `input` (the control plane
    /// sends `{id, toolName, input, toolUseId}`). It must classify as `.question` so the form
    /// renders — not as a generic `.tool` allow/deny — and `input` must still parse the questions.
    func testLiveAskUserQuestionClassifiesAsQuestion() {
        var r = TranscriptReducer()
        r.apply(RunEvent(seq: 0, type: .approvalRequest, payload: .object([
            "id": .string("ap-q"),
            "toolName": .string("AskUserQuestion"),
            "input": .object(["questions": .array([
                .object(["question": .string("Which DB?"),
                         "options": .array([.object(["label": .string("Postgres")])])]),
            ])]),
        ])))
        XCTAssertEqual(r.state.pendingApprovals.count, 1)
        let appr = r.state.pendingApprovals[0]
        XCTAssertEqual(appr.kind, .question)
        XCTAssertEqual(appr.toolName, "AskUserQuestion")
        XCTAssertEqual(appr.input.map { Approvals.parseQuestions(from: $0) }?.first?.question, "Which DB?")
    }

    /// Durable approvals fetched via REST seed the state (add-only, deduped by id), and a human
    /// decision removes one optimistically — mirroring the live-only seq-0 nudges that aren't replayed.
    func testSeedAndRemoveApprovals() {
        var r = TranscriptReducer()
        // A live nudge already folded in for ap1.
        r.apply(RunEvent(seq: 0, type: .approvalRequest, payload: .object([
            "id": .string("ap1"), "toolName": .string("Bash"),
            "input": .object(["command": .string("ls")])])))

        r.seedApprovals([
            PendingApproval(id: "ap1", kind: .tool, toolName: "Bash", input: nil),         // dup → skipped
            PendingApproval(id: "ap2", kind: .question, toolName: "AskUserQuestion", input: nil),
        ])
        XCTAssertEqual(r.state.pendingApprovals.map(\.id), ["ap1", "ap2"], "ap1 not duplicated")

        r.removeApproval(id: "ap2")
        XCTAssertEqual(r.state.pendingApprovals.map(\.id), ["ap1"])
    }

    // MARK: - tail-first initial load (the "reopened session shows no reply" fix)

    /// The server's `/events/page` JSON decodes into `EventPage`, and folding that page — which
    /// starts mid-conversation (its first event is an orphan `tool_result` whose `tool_use` is on
    /// an earlier page) — still reconstructs the recent assistant reply and advances the status.
    /// This is the contract `ConsoleModel.run()` relies on to paint a reopened session at its latest
    /// message instead of replaying the whole history over SSE.
    func testFoldsTailPageWithOrphanBoundaryEvent() throws {
        let json = """
        { "hasMore": true, "events": [
          { "seq": 840, "type": "tool_result", "payload": { "toolUseId": "old", "content": "..." } },
          { "seq": 841, "type": "assistant", "payload": { "text": "侦察回来了。" } },
          { "seq": 842, "type": "turn_end", "payload": { "status": "AWAITING_INPUT" } }
        ] }
        """
        let page = try JSONDecoder().decode(EventPage.self, from: Data(json.utf8))
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.events.count, 3)

        var r = TranscriptReducer()
        for ev in page.events { r.apply(ev) }
        let s = r.state

        // The orphan tool_result folds to nothing; the assistant reply renders; status advances.
        XCTAssertEqual(s.items.compactMap(\.asAssistant).map(\.text), ["侦察回来了。"])
        XCTAssertEqual(s.status, .awaitingInput)
        // maxSeq is the tail's high-water mark, so the follow-on SSE resumes from seq > 842.
        XCTAssertEqual(s.maxSeq, 842)
    }
}

// Test-only convenience accessors (kept out of the library surface).
extension TranscriptItem {
    var asUser: UserBubble? { if case .user(let b) = self { return b }; return nil }
    var asAssistant: AssistantBubble? { if case .assistant(let b) = self { return b }; return nil }
    var asTool: ToolCard? { if case .toolCall(let c) = self { return c }; return nil }
}
