import XCTest
@testable import OrbitKit

/// Ports the web `sessionLine` cases: the Agent-console list's second line.
final class SessionLineTests: XCTestCase {
    private func session(status: RunStatus, lastAssistantText: String? = nil, lastToolUse: String? = nil,
                         runningBgCount: Int? = nil, pendingApprovals: Int? = nil) -> Session {
        Session(id: "s", title: "t", status: status, agentId: nil, assignedRunnerId: nil,
                pendingApprovals: pendingApprovals, branch: nil, updatedAt: nil,
                lastAssistantText: lastAssistantText, lastToolUse: lastToolUse, runningBgCount: runningBgCount)
    }

    func testRunningPrioritisesApprovalThenToolThenPreview() {
        let approval = session(status: .running, lastToolUse: "Bash", pendingApprovals: 2)
        XCTAssertEqual(SessionLine.make(for: approval, live: true), .init(text: "Waiting for approval", tone: .approval))

        let tool = session(status: .running, lastAssistantText: "hi", lastToolUse: "mcp__orbit__task_create")
        XCTAssertEqual(SessionLine.make(for: tool, live: true), .init(text: "Running task_create…", tone: .running))

        let preview = session(status: .running, lastAssistantText: "Working on it")
        XCTAssertEqual(SessionLine.make(for: preview, live: true), .init(text: "Working on it", tone: .preview))

        let bare = session(status: .running)
        XCTAssertEqual(SessionLine.make(for: bare, live: true), .init(text: "Running…", tone: .running))
    }

    func testPendingAndBackground() {
        XCTAssertEqual(SessionLine.make(for: session(status: .pending), live: true),
                       .init(text: "Queued", tone: .queued))
        XCTAssertEqual(SessionLine.make(for: session(status: .awaitingInput, runningBgCount: 2), live: true),
                       .init(text: "2 background processes running…", tone: .running))
    }

    func testParkedShowsLastReplyAndStripsMarkdown() {
        let parked = session(status: .awaitingInput,
                             lastAssistantText: "## Done\n\nFixed the `Session` model and ran ```swift\ntest()\n``` — all green.")
        let line = SessionLine.make(for: parked, live: true)
        XCTAssertEqual(line?.tone, .preview)
        XCTAssertEqual(line?.text, "Done Fixed the Session model and ran — all green.")
    }

    func testNoLineWhenIdleWithoutReply() {
        XCTAssertNil(SessionLine.make(for: session(status: .succeeded), live: true))
    }

    /// The list payload's preview fields decode (server keys: lastAssistantText / lastToolUse /
    /// runningBgCount).
    func testSessionDecodesPreviewFields() throws {
        let json = #"{"id":"s1","status":"RUNNING","lastAssistantText":"hello","lastToolUse":"Read","runningBgCount":1}"#
        let s = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(s.lastAssistantText, "hello")
        XCTAssertEqual(s.lastToolUse, "Read")
        XCTAssertEqual(s.runningBgCount, 1)
    }
}
