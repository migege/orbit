import XCTest
@testable import OrbitKit

final class AppSectionTests: XCTestCase {

    func testVisibleGatesAdminByRole() {
        XCTAssertFalse(AppSection.visible(isAdmin: false).contains(.admin))
        XCTAssertTrue(AppSection.visible(isAdmin: true).contains(.admin))
        // Non-admin sees everything except admin.
        XCTAssertEqual(AppSection.visible(isAdmin: false).count, AppSection.allCases.count - 1)
    }

    func testCanonicalOrderActiveFirst() {
        XCTAssertEqual(AppSection.allCases.first, .active)
        XCTAssertEqual(AppSection.visible(isAdmin: true), AppSection.allCases)
    }

    func testEverySectionHasTitleAndIcon() {
        for s in AppSection.allCases {
            XCTAssertFalse(s.title.isEmpty, "\(s) missing title")
            XCTAssertFalse(s.systemImage.isEmpty, "\(s) missing icon")
        }
    }

    /// Routing/notifications must land in the right section so the shell follows a deep link.
    func testRouteMapsToSection() {
        XCTAssertEqual(AppSection.forRoute(.active), .active)
        XCTAssertEqual(AppSection.forRoute(.session("s1")), .active)
        XCTAssertEqual(AppSection.forRoute(.task("t1")), .tasks)
        XCTAssertEqual(AppSection.forRoute(.runner("r1")), .runners)
    }
}
