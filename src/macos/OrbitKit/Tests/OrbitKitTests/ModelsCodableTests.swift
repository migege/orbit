import XCTest
@testable import OrbitKit

final class ModelsCodableTests: XCTestCase {

    func testRunEventDecodesWithNestedPayload() throws {
        let json = #"{"seq":4,"type":"tool_use","ts":"2026-06-25T00:00:00Z","turnId":"tr1","payload":{"toolUseId":"t1","name":"Bash","input":{"command":"ls -la"}}}"#
        let ev = try JSONDecoder().decode(RunEvent.self, from: Data(json.utf8))
        XCTAssertEqual(ev.seq, 4)
        XCTAssertEqual(ev.type, .toolUse)
        XCTAssertEqual(ev.turnId, "tr1")
        XCTAssertEqual(ev.payload["name"]?.stringValue, "Bash")
        XCTAssertEqual(ev.payload["input"]?["command"]?.stringValue, "ls -la")
    }

    func testUnknownEventTypeFallsBackNotThrows() throws {
        let json = #"{"seq":9,"type":"some_future_event","payload":{}}"#
        let ev = try JSONDecoder().decode(RunEvent.self, from: Data(json.utf8))
        XCTAssertEqual(ev.type, .unknown)
        XCTAssertTrue(ev.type.isDurable)   // unknown is treated as durable for seq bookkeeping
    }

    func testRunEventToleratesMissingPayload() throws {
        let ev = try JSONDecoder().decode(RunEvent.self, from: Data(#"{"seq":1,"type":"system"}"#.utf8))
        XCTAssertEqual(ev.type, .system)
        XCTAssertEqual(ev.payload, .null)
    }

    func testEnumRawValuesMatchWireStrings() {
        XCTAssertEqual(RunStatus.awaitingInput.rawValue, "AWAITING_INPUT")
        XCTAssertEqual(PermissionMode.bypass.rawValue, "bypassPermissions")
        XCTAssertEqual(RunEventType.toolResult.rawValue, "tool_result")
        XCTAssertEqual(TaskStatus.inProgress.rawValue, "IN_PROGRESS")
    }

    func testJSONValueScalarCoercions() {
        let obj: JSONValue = .object(["n": .int(42), "b": .bool(true), "s": .string("x")])
        XCTAssertEqual(obj["n"]?.intValue, 42)
        XCTAssertEqual(obj["n"]?.asString, "42")
        XCTAssertEqual(obj["b"]?.boolValue, true)
        XCTAssertNil(obj["missing"]?.stringValue)
    }

    func testLoginResponseDecodes() throws {
        let json = #"{"accessToken":"jwt.abc.def","user":{"id":"u1","email":"a@b.com","name":"A","role":"ADMIN"}}"#
        let res = try JSONDecoder().decode(LoginResponse.self, from: Data(json.utf8))
        XCTAssertEqual(res.accessToken, "jwt.abc.def")
        XCTAssertEqual(res.user.email, "a@b.com")
    }
}
