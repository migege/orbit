# OrbitKit

The UI-free core of the Orbit macOS client (**Phase 0** of `docs/macos-client-design.md`).
Zero third-party dependencies. All protocol logic lives here so the SwiftUI app layer only
has to build views; this package is unit-tested in isolation.

## Build & test

```bash
cd src/macos/OrbitKit
swift build
swift test          # 14 tests
```

Builds and tests on **macOS** (the target) and on **Linux** (Swift 6.1 verified) — the pure
parser + reducer + models are platform-agnostic; the URLSession SSE transport and the
Keychain token store are guarded (`#if os(macOS)` / `#if canImport(Security)`) so Linux CI
runs the logic without them.

## Layout

```
Sources/OrbitKit/
  Models/
    Enums.swift          RunStatus · RunnerStatus · PermissionMode · RunEventType · TaskStatus
                         (string values mirror src/shared/src/enums.ts; RunEventType has an
                          `.unknown` fallback so a newer server event never breaks decoding)
    JSONValue.swift      lazily-typed JSON for the heterogeneous RunEvent.payload
    RunEvent.swift       NormalizedRunEvent, tolerant decoding
    DTOs.swift           User · Login · Session · Agent · Runner · turn/approval requests
  Realtime/
    SSEFrameParser.swift pure SSE framing (grapheme-aware newline split — see note below)
    EventStream.swift    EventStreaming protocol · MockEventStream · (macOS) URLSessionEventStream
  Transcript/
    Transcript.swift     the render model (bubbles, tool cards, approvals, bg procs)
    TranscriptReducer.swift  the seq/delta/approval/background state machine ← the heart
    SessionStore.swift   reconnecting consumer loop (sinceSeq + backoff)
  Net/APIClient.swift    async REST, JWT, 401→.unauthorized
  Auth/TokenStore.swift  protocol + InMemory + (macOS) Keychain
Tests/OrbitKitTests/
  TranscriptReducerTests.swift   the Phase-0 gate: a recorded transcript → asserted render
  SSEFrameParserTests.swift
  ModelsCodableTests.swift
```

## What Phase 0 proved (and one real bug it caught)

`TranscriptReducerTests.testFoldsRecordedSession` folds a representative recorded turn (user →
streamed assistant text → tool call+result → resolved approval → background process → a
**duplicate** durable event → turn end) and asserts the exact resulting items, approvals,
background state, status, and `maxSeq`. This is the de-risk gate for the whole native-console
bet: the streaming/seq/approval logic is correct before any UI exists.

Caught here, not in production: **the Swift CRLF grapheme trap.** `\r\n` is a *single*
Character (extended grapheme cluster) in Swift, so `split(separator: "\n")` silently fails to
break CRLF-terminated SSE lines and drops events. `SSEFrameParser.parse` splits with
`Character.isNewline` (matches LF, CR, and the CRLF cluster) instead. SSE servers commonly
emit CRLF, so this would have been a silent, intermittent event-loss bug.

## Native-vs-browser note

Browser `EventSource` can't set headers, so the web UI passes `?access_token=`. Native
`URLSession` sets the `Authorization` header directly — `URLSessionEventStream` does this,
keeping the token out of URLs and logs. The server accepts both.

## Next (Phase 1)

Wrap `SessionStore` in an `@Observable` adapter, add login + instance picker + an Active-
sessions sidebar, and render a live transcript from `URLSessionEventStream`. No new protocol
logic — Phase 1 is views over this core.
```
