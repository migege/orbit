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
}
