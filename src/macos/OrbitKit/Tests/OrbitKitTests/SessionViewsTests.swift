import XCTest
@testable import OrbitKit

final class SessionViewsTests: XCTestCase {

    func testQueryValueMapsCompletedToArchived() {
        XCTAssertEqual(SessionView.active.queryValue, "active")
        XCTAssertEqual(SessionView.completed.queryValue, "archived")   // server calls it "archived"
        XCTAssertEqual(SessionView.system.queryValue, "system")
        XCTAssertEqual(SessionView.allCases.map(\.title), ["Active", "Completed", "System"])
    }

    /// The list nests the agent — filtering must read `agent.id`, not the (absent) flat `agentId`.
    func testForAgentFiltersByNestedAgent() throws {
        let json = """
        [{"id":"s1","status":"AWAITING_INPUT","agent":{"id":"a1","name":"dev"}},
         {"id":"s2","status":"SUCCEEDED","agent":{"id":"a2","name":"other"}},
         {"id":"s3","status":"RUNNING","agent":{"id":"a1","name":"dev"}}]
        """
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        let mine = SessionFilter.forAgent(sessions, agentID: "a1")
        XCTAssertEqual(mine.map(\.id), ["s1", "s3"])   // order preserved, a2 excluded
    }

    func testSessionToleratesMissingAgent() throws {
        let s = try JSONDecoder().decode(Session.self, from: Data(#"{"id":"s1","status":"PENDING"}"#.utf8))
        XCTAssertNil(s.agent)
        XCTAssertTrue(SessionFilter.forAgent([s], agentID: "a1").isEmpty)
    }

    /// The Active tab hides auto-created (`source == "system"`) sessions — the server's `active`
    /// query returns them (slot accounting / deep-link), so the client must filter, matching web.
    func testForAgentViewHidesSystemSessionsOnActive() throws {
        let json = """
        [{"id":"s1","status":"RUNNING","source":"user","agent":{"id":"a1","name":"dev"}},
         {"id":"s2","status":"RUNNING","source":"system","agent":{"id":"a1","name":"dev"}},
         {"id":"s3","status":"PENDING","agent":{"id":"a1","name":"dev"}}]
        """
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        // Active: system session s2 is dropped; a missing source counts as non-system.
        XCTAssertEqual(SessionFilter.forAgent(sessions, agentID: "a1", view: .active).map(\.id), ["s1", "s3"])
        // Completed/System keep what the server returned (System is server-side `source == system`).
        XCTAssertEqual(SessionFilter.forAgent(sessions, agentID: "a1", view: .completed).map(\.id), ["s1", "s2", "s3"])
        XCTAssertEqual(SessionFilter.forAgent(sessions, agentID: "a1", view: .system).map(\.id), ["s1", "s2", "s3"])
    }
}
