import XCTest
@testable import OrbitKit

final class AgentListLogicTests: XCTestCase {

    private func agent(_ json: String) -> Agent {
        try! JSONDecoder().decode(Agent.self, from: Data(json.utf8))
    }

    func testGroupsByRunnerHostLast() {
        let agents = [
            agent(#"{"id":"1","name":"a","runnerId":"r1"}"#),
            agent(#"{"id":"2","name":"b"}"#),                      // host-level
            agent(#"{"id":"3","name":"c","runnerId":"r2"}"#),
            agent(#"{"id":"4","name":"d","runnerId":"r1"}"#),
        ]
        let groups = AgentListLogic.grouped(agents)
        XCTAssertEqual(groups.map(\.runnerId), ["r1", "r2", nil])  // first-seen runner order, host last
        XCTAssertEqual(groups.first?.agents.map(\.id), ["1", "4"]) // r1 keeps both, in order
        XCTAssertEqual(groups.last?.agents.map(\.id), ["2"])       // host group
    }

    func testEffectiveModelEnvOverrideWins() {
        XCTAssertEqual(
            AgentListLogic.effectiveModel(model: "claude-opus-4-8", env: ["ANTHROPIC_MODEL": "deepseek-chat"]),
            "deepseek-chat")
        XCTAssertEqual(AgentListLogic.effectiveModel(model: "claude-sonnet-4-6", env: nil), "claude-sonnet-4-6")
        XCTAssertEqual(AgentListLogic.effectiveModel(model: nil, env: ["ANTHROPIC_MODEL": ""]),
                       AgentDefaults.defaultModelID)   // empty override ignored → default
    }
}
