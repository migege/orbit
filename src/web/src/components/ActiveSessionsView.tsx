import { LoadingOutlined } from '@ant-design/icons';
import { useQuery } from '@tanstack/react-query';
import { Spin } from 'antd';
import { useNavigate } from 'react-router-dom';
import { encodeId } from '../lib/idCodec';
import { sessionsQuery } from '../lib/queries';

// "Active" = sessions that need your click, are working, or are queued right now.
// A session only counts as "需要你回复" when a clickable card is pending — an
// AskUserQuestion, a Plan (ExitPlanMode) approval, or a tool-permission allow/deny.
// Such a card blocks inside an in-flight turn, so the session's status is RUNNING;
// we promote it by its pending-approval count (server-provided), not by status.
// Sessions that merely parked for your next message (AWAITING_INPUT / INTERRUPTED,
// no card) are intentionally NOT shown here — find them in the session list/history.
//   需要你回复 — a card is waiting for your click (pendingApprovals > 0)
//   正在运行   — Claude is working, nothing to click (RUNNING, no card)
//   排队中     — waiting for a runner slot (PENDING)
const GROUPS = [
  { key: 'attention', label: 'Needs you' },
  { key: 'running', label: 'Running' },
  { key: 'queued', label: 'Queued' },
];
// Only RUNNING (working / blocked on a card) and PENDING (queued) ever show here.
const VISIBLE = ['RUNNING', 'PENDING'];
// A pending card blocks inside a RUNNING turn, so attention is decided by the
// approval count, not the raw status; everything else falls through by status.
const hasCard = (s: any): boolean => (s.pendingApprovals ?? 0) > 0;
const groupOf = (s: any): string =>
  hasCard(s) ? 'attention' : s.status === 'RUNNING' ? 'running' : 'queued';

// Compact relative time: just now / Nm / Nh / Nd.
const fmtAgo = (d?: string | null): string => {
  if (!d) return '';
  const diff = Date.now() - new Date(d).getTime();
  const min = 60_000;
  const hour = 60 * min;
  const day = 24 * hour;
  if (diff < min) return 'just now';
  if (diff < hour) return `${Math.floor(diff / min)}m`;
  if (diff < day) return `${Math.floor(diff / hour)}h`;
  return `${Math.floor(diff / day)}d`;
};

// Most-recent activity drives both the time label and the in-group ordering.
const timeOf = (s: any): string => s.lastTurnAt ?? s.startedAt ?? s.createdAt;

// A time phrase tuned to the session's state: a pending card shows how long it's
// been waiting on you, a plain running session shows elapsed, queued says it's
// waiting for a slot.
function timeLabel(s: any): string {
  const ago = fmtAgo(timeOf(s));
  if (hasCard(s)) return ago ? `Waiting ${ago}` : '';
  if (s.status === 'RUNNING') return ago ? `Running ${ago}` : '';
  return 'Waiting for a slot'; // PENDING
}

function StatusBadge({ session }: { session: any }) {
  if (hasCard(session))
    return (
      <span className="status-pill awaiting">
        <span className="status-dot" />
        Awaiting reply
      </span>
    );
  if (session.status === 'RUNNING')
    return (
      <span className="status-pill running">
        <LoadingOutlined spin />
        Running
      </span>
    );
  return (
    <span className="status-pill queued">
      <span className="status-dot" />
      Queued
    </span>
  );
}

export function ActiveSessionsView() {
  const navigate = useNavigate();
  // Same query the agent console uses; poll often since this is the "what's live now" view.
  const sessionsQ = useQuery({ ...sessionsQuery({ view: 'active' }), refetchInterval: 4000 });

  // view=active is "not archived, not deleted" — it still includes finished
  // sessions, so filter to still-live ones here. System (task-execution) sessions
  // ARE shown: a queued/running task is live work the user expects to see here.
  const active = (sessionsQ.data ?? []).filter((s: any) => VISIBLE.includes(s.status));

  const renderRow = (s: any) => {
    const meta = [s.agent?.name, s.assignedRunner?.name, timeLabel(s)].filter(Boolean).join(' · ');
    return (
      <div
        className="task-row clickable session-row"
        key={s.id}
        onClick={() => navigate(`/sessions/${encodeId(s.id)}`)}
      >
        <div className="task-status-cell">
          <StatusBadge session={s} />
        </div>
        <div className="task-title-cell">
          <span className="task-title">{s.title || '(untitled session)'}</span>
          {s.pendingApprovals > 0 ? (
            <span className="session-approval-badge">{s.pendingApprovals} pending</span>
          ) : null}
        </div>
        <div className="task-cell session-meta">{meta}</div>
      </div>
    );
  };

  return (
    <>
      <h1 className="page-title">Active</h1>
      {sessionsQ.isLoading ? (
        <div style={{ padding: 48, textAlign: 'center' }}>
          <Spin />
        </div>
      ) : active.length === 0 ? (
        <div style={{ padding: '32px 16px', color: '#8a9099', fontSize: 13 }}>
          No live sessions right now.
        </div>
      ) : (
        <div className="orbit-sessionlist">
          {GROUPS.map((g) => {
            // Oldest activity first within a group: the longest-waiting / longest-running
            // session floats to the top, where it most needs attention.
            const rows = active
              .filter((s: any) => groupOf(s) === g.key)
              .sort((a: any, b: any) => timeOf(a).localeCompare(timeOf(b)));
            if (rows.length === 0) return null;
            return (
              <div className="session-group" key={g.key}>
                <div className={`session-group-head ${g.key}`}>
                  {g.label}
                  <span className="session-group-count">{rows.length}</span>
                </div>
                {rows.map((s: any) => renderRow(s))}
              </div>
            );
          })}
        </div>
      )}
    </>
  );
}
