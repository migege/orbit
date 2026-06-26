import XCTest
@testable import OrbitKit

/// Pins `GET /users/me` (now with createdAt + preferences) and the partial `me/preferences`
/// PATCH. `jsonObject` is shared from TasksCodableTests (same test target).
final class PreferencesCodableTests: XCTestCase {

    func testMeDecodesWithPreferences() throws {
        let json = """
        {"id":"u1","email":"a@b.com","name":"Jiang","role":"ADMIN","createdAt":"2026-06-01T00:00:00Z",
         "preferences":{"theme":"dark","defaultModel":"claude-opus-4-8","defaultPermissionMode":"dontAsk"}}
        """
        let u = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        XCTAssertEqual(u.role, "ADMIN")
        XCTAssertEqual(u.preferences?.theme, "dark")
        XCTAssertEqual(u.preferences?.defaultModel, "claude-opus-4-8")
        XCTAssertEqual(u.preferences?.defaultPermissionMode, "dontAsk")
    }

    /// The login payload omits createdAt/preferences — must still decode (→ nil).
    func testLoginUserToleratesMissingPrefs() throws {
        let u = try JSONDecoder().decode(User.self, from: Data(#"{"id":"u1","email":"a@b.com"}"#.utf8))
        XCTAssertNil(u.preferences)
        XCTAssertNil(u.createdAt)
    }

    func testUpdatePreferencesIsPartial() throws {
        let obj = try jsonObject(UpdatePreferencesRequest(theme: "dark"))
        XCTAssertEqual(obj["theme"] as? String, "dark")
        XCTAssertFalse(obj.keys.contains("defaultModel"))          // omitted key → server keeps it
        XCTAssertFalse(obj.keys.contains("defaultPermissionMode"))
    }
}
