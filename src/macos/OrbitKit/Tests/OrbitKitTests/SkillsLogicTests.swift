import XCTest
@testable import OrbitKit

final class SkillsLogicTests: XCTestCase {

    private func runner(_ json: String) -> Runner {
        try! JSONDecoder().decode(Runner.self, from: Data(json.utf8))
    }

    func testGroupsByAgentSharedLast() {
        let r = runner(#"""
        {"id":"r1","name":"box","displayName":"Box","online":true,
         "skills":[{"name":"deep-research","type":"skill","agentId":"a1"},
                   {"name":"host-skill","type":"skill"}],
         "commands":[{"name":"commit","type":"command","agentId":"a1"}]}
        """#)
        let groups = SkillsLogic.grouped(runners: [r], agentName: { $0 == "a1" ? "Builder" : $0 })
        XCTAssertEqual(groups.count, 2)
        // agent group first, Shared last
        XCTAssertEqual(groups.first?.title, "Builder")
        XCTAssertEqual(groups.first?.agentId, "a1")
        XCTAssertEqual(groups.first?.count, 2)           // deep-research + commit
        XCTAssertEqual(groups.first?.runnerName, "Box")  // displayName preferred
        XCTAssertNil(groups.last?.agentId)               // Shared
        XCTAssertEqual(groups.last?.title, "Shared")
        XCTAssertEqual(groups.last?.skills.map(\.name), ["host-skill"])
    }

    func testSearchFilters() {
        let r = runner(#"""
        {"id":"r1","name":"box",
         "skills":[{"name":"deep-research","agentId":"a1"},{"name":"commit-helper","agentId":"a1"}]}
        """#)
        let groups = SkillsLogic.grouped(runners: [r], agentName: { _ in "A" }, search: "deep")
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.skills.map(\.name), ["deep-research"])  // commit-helper filtered out
    }

    func testEmptyWhenNoMatches() {
        let r = runner(#"{"id":"r1","name":"box","skills":[{"name":"x","agentId":"a1"}]}"#)
        XCTAssertTrue(SkillsLogic.grouped(runners: [r], agentName: { _ in "A" }, search: "zzz").isEmpty)
    }

    func testRunnerDecodesPlanUsageAndSlots() throws {
        let r = runner(#"""
        {"id":"r1","name":"box","activeSessions":3,"maxConcurrent":8,
         "lastHeartbeatAt":"2026-06-26T00:00:00Z",
         "planUsage":{"fiveHour":{"utilization":42,"resetsAt":"2026-06-26T05:00:00Z"},
                      "sevenDay":{"utilization":71.5},"fetchedAt":"2026-06-26T00:00:00Z"}}
        """#)
        XCTAssertEqual(r.activeSessions, 3)
        XCTAssertEqual(r.planUsage?.fiveHour?.utilization, 42)       // integer JSON → Double
        XCTAssertEqual(r.planUsage?.sevenDay?.utilization, 71.5)
        XCTAssertNil(r.planUsage?.sevenDayOpus)
    }

    func testCreateUserResultDecodesGeneratedPassword() throws {
        let res = try JSONDecoder().decode(CreateUserResult.self,
            from: Data(#"{"id":"u1","email":"a@b.com","role":"MEMBER","password":"gen-pw-123"}"#.utf8))
        XCTAssertEqual(res.password, "gen-pw-123")   // returned once on create
        XCTAssertEqual(res.role, "MEMBER")
    }
}
