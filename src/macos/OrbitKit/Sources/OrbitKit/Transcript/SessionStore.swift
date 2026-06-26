import Foundation

/// App-facing holder for one session's reduced transcript. Drives the reconnecting consumer
/// loop: stream from the durable high-water `maxSeq`, fold each event, retry with backoff.
///
/// Deliberately not `@Observable` (keeps OrbitKit cross-platform + UI-free): the SwiftUI layer
/// either wraps this in an `@Observable` adapter or observes via `onChange`.
public final class SessionStore: @unchecked Sendable {
    public let sessionID: String
    public private(set) var reducer = TranscriptReducer()
    /// Fired after each applied event so a view can re-read `state`.
    public var onChange: (@Sendable () -> Void)?

    public init(sessionID: String) { self.sessionID = sessionID }

    public var state: TranscriptState { reducer.state }

    public func ingest(_ ev: RunEvent) {
        reducer.apply(ev)
        onChange?()
    }

    public func addOptimisticUser(clientTurnId: String, text: String,
                                  attachments: [TurnAttachment] = []) {
        reducer.addOptimisticUser(clientTurnId: clientTurnId, text: text, attachments: attachments)
        onChange?()
    }

    /// Consume `stream` until cancelled, reconnecting with `?sinceSeq=maxSeq` and exponential
    /// backoff (≤12 attempts) on drops. On a clean end-of-stream (turn finished) it reconnects
    /// promptly to pick up the next turn.
    public func run(using stream: EventStreaming) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                for try await ev in stream.events(sessionID: sessionID, sinceSeq: state.maxSeq) {
                    ingest(ev)
                    attempt = 0
                }
                // Clean end → brief settle, then reconnect for the next turn.
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            } catch is CancellationError {
                return
            } catch {
                attempt += 1
                if attempt > 12 { return }
                let ms = min(15_000, 500 * (1 << min(attempt, 5)))   // 1s,2s,…,15s + cap
                let jitter = Int.random(in: 0...250)
                try? await Task.sleep(nanoseconds: UInt64(ms + jitter) * 1_000_000)
            }
        }
    }
}
