import XCTest
@testable import OrbitKit

final class SSEFrameParserTests: XCTestCase {

    func testParsesFramesIgnoringCommentsAndCRLF() {
        // A heartbeat comment, a CRLF event, then an LF event.
        let wire = ":keepalive\r\n" +
                   "data: {\"seq\":1,\"type\":\"assistant\",\"payload\":{\"text\":\"hi\"}}\r\n" +
                   "\r\n" +
                   "data: {\"seq\":2,\"type\":\"turn_end\",\"payload\":{\"status\":\"AWAITING_INPUT\"}}\n" +
                   "\n"
        var p = SSEFrameParser()
        let events = p.parse(wire)
        guard events.count == 2 else { return XCTFail("expected 2 frames, got \(events.count)") }

        let first = SSEDecoding.runEvent(from: events[0])
        XCTAssertEqual(first?.seq, 1)
        XCTAssertEqual(first?.type, .assistant)
        XCTAssertEqual(first?.payload["text"]?.stringValue, "hi")

        let second = SSEDecoding.runEvent(from: events[1])
        XCTAssertEqual(second?.type, .turnEnd)
    }

    func testMultiLineDataIsJoinedWithNewline() {
        var p = SSEFrameParser()
        let events = p.parse("data: line one\ndata: line two\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "line one\nline two")
    }

    func testIncrementalConsumeDispatchesOnBlankLine() {
        var p = SSEFrameParser()
        XCTAssertNil(p.consume(line: "data: {\"seq\":7,\"type\":\"system\",\"payload\":{}}"))
        let ev = p.consume(line: "")
        XCTAssertNotNil(ev)
        XCTAssertEqual(SSEDecoding.runEvent(from: ev!)?.seq, 7)
    }

    func testSSEToReducerPath() {
        // The real path: wire bytes → frames → RunEvent → reducer.
        let wire = """
        data: {"seq":1,"type":"user","payload":{"text":"hello","clientTurnId":"c1"}}

        data: {"seq":2,"type":"assistant","payload":{"text":"hi there"}}

        data: {"seq":3,"type":"turn_end","payload":{"status":"AWAITING_INPUT"}}

        """
        var p = SSEFrameParser()
        var r = TranscriptReducer()
        for frame in p.parse(wire) {
            if let ev = SSEDecoding.runEvent(from: frame) { r.apply(ev) }
        }
        XCTAssertEqual(r.state.items.count, 2)
        XCTAssertEqual(r.state.status, .awaitingInput)
        XCTAssertEqual(r.state.maxSeq, 3)
    }
}
