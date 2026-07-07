import XCTest
@testable import OrbitKit

/// Pins the wire contract the iOS Share sheet depends on: the `POST /sessions/:id/share` response
/// (`ShareInfo`) and the `shareToken` the owner `GET /sessions/:id` carries so the sheet can seed
/// its create-vs-revoke state.
final class ShareCodableTests: XCTestCase {

    func testShareInfoDecodes() throws {
        let json = #"{"shareToken":"abc-DEF_123","sharedAt":"2026-07-06T10:00:00.000Z"}"#
        let info = try JSONDecoder().decode(ShareInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.shareToken, "abc-DEF_123")
        XCTAssertEqual(info.sharedAt, "2026-07-06T10:00:00.000Z")
    }

    func testSessionDetailDecodesShareToken() throws {
        let json = #"{"id":"s1","shareToken":"tok123"}"#
        let d = try JSONDecoder().decode(SessionDetail.self, from: Data(json.utf8))
        XCTAssertEqual(d.shareToken, "tok123")
    }

    func testSessionDetailShareTokenNilWhenUnshared() throws {
        // A never-shared session omits the field (or sends null); either decodes to nil.
        let d = try JSONDecoder().decode(SessionDetail.self, from: Data(#"{"id":"s2"}"#.utf8))
        XCTAssertNil(d.shareToken)
    }
}
