import { Injectable } from '@nestjs/common';
import { EventEmitter } from 'events';
import { NormalizedRunEvent } from '@orbit/shared';
import { Observable, Subject, filter, map } from 'rxjs';

/**
 * In-memory hub: runner-API writes events here, the SSE endpoint subscribes.
 * Also tracks cancellation requests delivered to runners via heartbeat, and an
 * inbox signal that wakes a runner's per-run input long-poll (interactive Route B).
 * (Single-process for v1; swap for Postgres LISTEN/NOTIFY or Redis to scale out.)
 */
@Injectable()
export class RealtimeService {
  private readonly hub = new Subject<{ runId: string; event: NormalizedRunEvent }>();
  private readonly cancellations = new Map<string, Set<string>>(); // runnerId -> runIds
  private readonly inbox = new EventEmitter(); // event name = runId

  constructor() {
    this.inbox.setMaxListeners(0);
  }

  /** Wake a runner parked in GET /runner/runs/:id/inbox after a turn is enqueued. */
  notifyInbox(runId: string): void {
    this.inbox.emit(runId);
  }

  /** Park until a turn is enqueued for this run, or the timeout elapses. */
  waitForInbox(runId: string, timeoutMs: number): Promise<void> {
    return new Promise((resolve) => {
      const done = (): void => {
        clearTimeout(timer);
        this.inbox.off(runId, done);
        resolve();
      };
      const timer = setTimeout(done, timeoutMs);
      this.inbox.once(runId, done);
    });
  }

  publish(runId: string, event: NormalizedRunEvent): void {
    this.hub.next({ runId, event });
  }

  streamForRun(runId: string): Observable<NormalizedRunEvent> {
    return this.hub.asObservable().pipe(
      filter((m) => m.runId === runId),
      map((m) => m.event),
    );
  }

  requestCancel(runnerId: string, runId: string): void {
    let set = this.cancellations.get(runnerId);
    if (!set) {
      set = new Set();
      this.cancellations.set(runnerId, set);
    }
    set.add(runId);
  }

  drainCancellations(runnerId: string): string[] {
    const set = this.cancellations.get(runnerId);
    if (!set || set.size === 0) return [];
    const ids = [...set];
    set.clear();
    return ids;
  }
}
