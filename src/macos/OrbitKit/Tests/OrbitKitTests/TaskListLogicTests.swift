import XCTest
@testable import OrbitKit

final class TaskListLogicTests: XCTestCase {

    private func task(_ json: String) -> TaskItem {
        try! JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
    }

    func testFilterMatches() {
        XCTAssertTrue(TaskFilter.ongoing.matches(.open))
        XCTAssertTrue(TaskFilter.ongoing.matches(.inProgress))
        XCTAssertFalse(TaskFilter.ongoing.matches(.done))
        XCTAssertTrue(TaskFilter.failed.matches(.failed))
        XCTAssertTrue(TaskFilter.all.matches(.cancelled))
    }

    /// running outranks queued outranks any lifecycle status; a running DONE task still sorts
    /// above an OPEN one — the live overlay wins.
    func testStatusRankOrder() {
        let running = task(#"{"id":"1","title":"r","status":"DONE","running":true}"#)
        let queued  = task(#"{"id":"2","title":"q","status":"OPEN","queued":true}"#)
        let prog    = task(#"{"id":"3","title":"p","status":"IN_PROGRESS"}"#)
        let open    = task(#"{"id":"4","title":"o","status":"OPEN"}"#)
        let done    = task(#"{"id":"5","title":"d","status":"DONE"}"#)
        XCTAssertLessThan(TaskListLogic.statusRank(running), TaskListLogic.statusRank(queued))
        XCTAssertLessThan(TaskListLogic.statusRank(queued), TaskListLogic.statusRank(prog))
        XCTAssertLessThan(TaskListLogic.statusRank(prog), TaskListLogic.statusRank(open))
        XCTAssertLessThan(TaskListLogic.statusRank(open), TaskListLogic.statusRank(done))
    }

    func testSortByStatusPutsLiveFirst() {
        let items = [
            task(#"{"id":"1","title":"done","status":"DONE"}"#),
            task(#"{"id":"2","title":"run","status":"OPEN","running":true}"#),
            task(#"{"id":"3","title":"open","status":"OPEN"}"#),
        ]
        let sorted = TaskListLogic.sorted(items, by: .status, descending: false)
        // running(rank 0) first; then OPEN(rank 4) before DONE(rank 5).
        XCTAssertEqual(sorted.map(\.id), ["2", "3", "1"])
    }

    func testTitleSortIsNumeric() {
        let items = [
            task(#"{"id":"1","title":"Unit 73","status":"OPEN"}"#),
            task(#"{"id":"2","title":"Unit 9","status":"OPEN"}"#),
        ]
        let sorted = TaskListLogic.sorted(items, by: .title, descending: false)
        XCTAssertEqual(sorted.map(\.title), ["Unit 9", "Unit 73"])   // 9 before 73, not lexicographic
    }

    func testFilteredAllIsIdentity() {
        let items = [task(#"{"id":"1","title":"a","status":"DONE"}"#)]
        XCTAssertEqual(TaskListLogic.filtered(items, .all).count, 1)
        XCTAssertEqual(TaskListLogic.filtered(items, .ongoing).count, 0)
    }

    func testPillOverlayWinsOverLifecycle() {
        XCTAssertEqual(TaskListLogic.pill(task(#"{"id":"1","title":"a","status":"DONE","running":true}"#)).kind, .running)
        XCTAssertEqual(TaskListLogic.pill(task(#"{"id":"1","title":"a","status":"OPEN","queued":true}"#)).kind, .queued)
        XCTAssertEqual(TaskListLogic.pill(task(#"{"id":"1","title":"a","status":"IN_PROGRESS"}"#)).kind, .inProgress)
        XCTAssertEqual(TaskListLogic.pill(task(#"{"id":"1","title":"a","status":"FAILED"}"#)).label, "Failed")
    }
}
