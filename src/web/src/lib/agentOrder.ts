// Agent ordering, shared by the sidebar (⌘1‒9), the boot pre-warm, and the default landing so
// that "the first agent" means the same thing everywhere. Custom drag order (`position`) first;
// agents never dragged (position null) fall to the end, oldest-first by `createdAt` — mirroring
// the server's ordering.

export interface OrderableAgent {
  id: string;
  createdAt: string;
  // Drag-to-reorder slot (0-based). null until the user reorders, so it sorts last.
  position?: number | null;
  // The machine this agent belongs to; an agent with no runner has no console to open.
  runnerId?: string | null;
  runner?: { id: string } | null;
}

export function orderAgents<T extends OrderableAgent>(agents: readonly T[]): T[] {
  return [...agents].sort((a, b) => {
    const pa = a.position ?? null;
    const pb = b.position ?? null;
    if (pa !== null && pb !== null) return pa - pb;
    if (pa !== null) return -1;
    if (pb !== null) return 1;
    return a.createdAt < b.createdAt ? -1 : 1;
  });
}

/** The agent id → runner id, whichever shape the payload carries (nested `runner` or flat). */
export const agentRunnerId = (a: OrderableAgent): string | null => a.runner?.id ?? a.runnerId ?? null;

/**
 * The agent the app lands on by default: the first (in sidebar order) that has a runner, so its
 * console can actually open. Config-only agents (no runner) are skipped — the same rule the
 * sidebar's `openAgent` uses.
 */
export function firstOpenableAgent<T extends OrderableAgent>(agents: readonly T[]): T | undefined {
  return orderAgents(agents).find((a) => agentRunnerId(a) != null);
}
