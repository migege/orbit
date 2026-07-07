import XCTest
@testable import OrbitKit

/// Pins `GET /users/me` (now with createdAt + preferences) and the partial `me/preferences`
/// PATCH. `jsonObject` is shared from TasksCodableTests (same test target).
final class PreferencesCodableTests: XCTestCase {

    func testMeDecodesWithPreferences() throws {
        let json = """
        {"id":"u1","email":"a@b.com","name":"Jiang","role":"ADMIN","createdAt":"2026-06-01T00:00:00Z",
         "preferences":{"theme":"dark","defaultModel":"claude-opus-4-8","defaultPermissionMode":"dontAsk",
                        "defaultEffort":"high"}}
        """
        let u = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        XCTAssertEqual(u.role, "ADMIN")
        XCTAssertEqual(u.preferences?.theme, "dark")
        XCTAssertEqual(u.preferences?.defaultModel, "claude-opus-4-8")
        XCTAssertEqual(u.preferences?.defaultPermissionMode, "dontAsk")
        XCTAssertEqual(u.preferences?.defaultEffort, "high")
    }

    /// A `me` payload from before the defaultEffort key existed must still decode (→ nil), so an
    /// old server / never-set account falls back to the model default instead of throwing.
    func testPreferencesToleratesMissingEffort() throws {
        let json = #"{"id":"u1","email":"a@b.com","preferences":{"theme":"light"}}"#
        let u = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        XCTAssertNil(u.preferences?.defaultEffort)
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
        XCTAssertFalse(obj.keys.contains("defaultEffort"))
    }

    /// Sending only defaultEffort must emit just that key (so the shallow-merge keeps theme/model)
    /// and must include "" (Default), which the composer sends to clear the effort override.
    func testUpdatePreferencesEffortOnly() throws {
        let obj = try jsonObject(UpdatePreferencesRequest(defaultEffort: ""))
        XCTAssertEqual(obj["defaultEffort"] as? String, "")
        XCTAssertFalse(obj.keys.contains("theme"))
        XCTAssertFalse(obj.keys.contains("defaultModel"))
    }
}
