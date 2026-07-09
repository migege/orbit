# Postmortem — `codex@m5` sessions stuck "queued" (2026-07-09)

New sessions for the `codex@m5` agent sat in `PENDING` ("queued" in the UI) for up to
**10m33s** while the runner was demonstrably online. The apiserver was healthy the whole
time and never at capacity.

**Root cause:** a session whose agent has no `workDir` falls back to an arbitrary
directory, where `autoInitGit` runs `git init && git add -A`. `git` is invoked with **no
timeout**, and worktree setup runs **synchronously on the runner's claim loop**. One slow
`git` therefore froze *every* subsequent claim on that runner for 16 minutes.

All times UTC. Investigated entirely from the control plane — the runner's own log was
never available.

## Symptom

The user observed that new messages to `codex@m5` were all "queued".

"Queued" is a session in `RunStatus.PENDING`: created, assigned to a runner, but not yet
claimed. It is *not* a queued conversation turn — turn delivery was never at fault.

## Timeline

| Time (UTC) | Event |
|---|---|
| `12:32:47.725` | Session `019f46dd` created; claimed 6 ms later. |
| `12:32:47.731` | Runner begins `setupWorktree` for it — and never returns. |
| `12:34:49` | Reaper force-fails `019f46dd`: `codex runtime not initialized` (2 min `CODEX_STARTUP_GRACE_MS`). |
| `12:38:21.522` | Session `019f46e2` created → **stays PENDING**. |
| `12:47:03.979` | Session `019f46ea` created → **stays PENDING**. |
| `12:48:53.815` | Codex conversation for `019f46dd` is finally minted — **966.090 s** after its session was created. |
| `12:48:54.758` | `019f46e2` claimed (queued **10m33s**). |
| `12:48:55.008` | `019f46ea` claimed (queued **1m51s**). |
| `12:49:21` | Runner opens its first inbox poll for `019f46dd` — 15 min after the server had already failed it. |

Throughout the stall the runner polled the inbox of a *different* session (`019f45ff`)
every 25 s with no gap. **The runner process was alive and never restarted.** Only its
claim loop was blocked.

## Root cause chain

1. `codex@m5` is the **only** agent in the database with `work_dir = NULL`, and it has
   `auto_init_git = true`.
2. `sessionExecDir` (`runner-go/runloop.go:38`) resolves an empty `workDir` to
   `cfg.WorkDir`, then to `os.Getwd()` — a directory nobody chose as a project root.
3. That directory is not a git repo, so `setupWorktree` (`runner-go/worktree.go:225`)
   takes the `autoInitGit` branch and calls `initGitRepo`.
4. `initGitRepo` (`runner-go/worktree.go:178`) runs `git init`, then **`git add -A`**,
   whose cost is proportional to the size of the tree.
5. `git()` (`runner-go/worktree.go:40`) is `exec.Command(...).Output()` — **no context,
   no timeout**. It can block forever.
6. `startSession` (`runner-go/runloop.go:296`) calls `setupWorktree` **synchronously**,
   before spawning the per-session goroutine, and `startSession` is only ever called from
   the claim/reclaim loop (`runloop.go:335`, `runloop.go:385`).

So a single slow `git` on one session stops the runner from claiming *any* new session.
Those sessions stay `PENDING` — the "queued" the user saw.

Independently, the apiserver's reaper kills a codex session that hasn't reported a
runtime id within 2 minutes (`apiserver/src/realtime/reaper.service.ts:124`), which is why
`019f46dd` ended `FAILED` with `codex runtime not initialized` while its `git` was still
running.

## Evidence, without runner logs

Four control-plane signals were sufficient:

1. **`runtime_session_id` is a uuid7 minted by codex.** Its first 48 bits are a
   millisecond timestamp, so it records exactly when codex created the conversation —
   `12:48:53.815` for `019f46dd`, i.e. 966.090 s after the session row. A timestamp
   fossil that needs no logging.
2. **`started_at - created_at`** is the true queue wait. `started_at` is written by the
   claim `UPDATE` in `QueueService.trySessionClaim`, *not* at creation. Both stalled
   sessions were released in the same 250 ms window, immediately after (1).
3. **`isolation_status`** is the runner's own report of its worktree decision. The three
   healthy sessions report `shared-nogit`; `019f46dd` reports `NULL` — `setupWorktree`
   never returned. Since 2026-07-01 it is the **only** claimed session with a null
   `isolation_status`.
4. **Gateway access logs** show inbox long-polls per session, which proved the runner was
   alive and un-restarted during the stall.

Ruled out by evidence: runner offline (heartbeat 20 s old), slot exhaustion (3 live
sessions against `max_concurrent = 16`), server-side claim gate, and runner restart.

## Diagnostic pitfall: `delivered_at` is not a delivery timestamp

`conversation_turn.delivered_at` is **overwritten on every lease re-delivery**. The inbox
lease is at-least-once with `INBOX_LEASE_MS = 300_000`
(`apiserver/src/runner-api/runner-api.controller.ts:500`), so any turn that runs longer
than 5 minutes is re-delivered and its `delivered_at` jumps forward. The runner ignores the
duplicate via its `inflight[turnID]` guard, so this is harmless — but it makes a promptly
delivered turn look badly delayed.

Concretely, turn `seq 12` of `019f45ff` looked like a 10-minute delivery delay. The gateway
log shows it was delivered at `12:34:23` — the same second it was created — then
re-delivered at `12:39:24` and `12:44:26`.

**Do not measure delivery latency with `delivered_at`.** Use the gateway log, or add a
separate `first_delivered_at`.

## Secondary finding: zombie inbox poller

The runner kept long-polling the inbox of `019f46dd` from `12:49:21` onward, although the
server had finalized it `FAILED` at `12:34:49`. It consumes no slot (the concurrency gate
counts only `RUNNING`/`AWAITING_INPUT`/`INTERRUPTED`) and the server answers empty, but the
session goroutine leaks until the runner restarts. The runner has no path to learn that a
session it is driving was finalized server-side.

## Recommended fixes

**Immediate (config, no deploy):** give `codex@m5` a real `work_dir`, or set
`auto_init_git = false`. Verify by creating a session and checking
`started_at - created_at < 1s`.

**Code:**

1. Bound `git()` with a `context.WithTimeout` (`runner-go/worktree.go:40`). No git
   invocation on the claim path should be able to block indefinitely.
2. Move `setupWorktree` off the claim loop, into the per-session goroutine
   (`runner-go/runloop.go:300`), so one session's slow startup cannot starve the runner.
3. Do not `autoInitGit` when the agent's `workDir` is unset. Running `git add -A` in a
   fallback directory is never what the user asked for.
4. Let the runner stop driving a session the server has finalized (fixes the zombie poller).

**Detection:** a session that has been claimed but has not reported `isolation_status`
after ~30 s is a precise signature of this class of stall.

## Open question

Whether `git init` or `git add -A` was the call that hung, and why the other three sessions
fast-failed to `shared-nogit` instead. Both commands are unbounded, so either is possible.
Resolving this needs the state of the fallback directory on the runner host, or
`~/.orbit/runner.log`.
