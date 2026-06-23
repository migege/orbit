import { CheckCircleFilled, CheckOutlined, CopyOutlined } from '@ant-design/icons';
import { useQuery } from '@tanstack/react-query';
import { Segmented } from 'antd';
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api';

type OS = 'macOS' | 'Linux' | 'Windows';

// The deployment serves install.sh, the runner binaries (/dl) and the API all from its own
// origin. __PUBLIC_ORIGIN__ is that origin, baked into the bundle at build time from the
// PUBLIC_ORIGIN env (.env → web image build arg, see vite.config). It defaults to the hosted
// host below, so self-hosted deploys just set PUBLIC_ORIGIN instead of being hardwired to it.
declare const __PUBLIC_ORIGIN__: string;
const DEFAULT_HOST = 'https://orbit.wikova.com';

// Only the install line differs per OS; everything else is identical.
function buildCommands(origin: string): { install: Record<OS, string>; register: string } {
  // On the canonical hosted instance the CLI/script defaults already match its origin, so
  // keep the commands clean there; on any other origin pass it through explicitly.
  const custom = origin !== DEFAULT_HOST;
  const sh = `curl -fsSL ${origin}/install.sh | ${custom ? `ORBIT_BASE_URL=${origin} ` : ''}bash`;
  const ps = custom
    ? `$env:ORBIT_BASE_URL='${origin}'; irm ${origin}/install.ps1 | iex`
    : `irm ${origin}/install.ps1 | iex`;
  return {
    install: { macOS: sh, Linux: sh, Windows: ps },
    register: custom ? `orbit register --server ${origin}` : 'orbit register',
  };
}

interface Runner {
  id: string;
  name: string;
  online?: boolean;
}

function CommandBox({ cmd, copied, onCopy }: { cmd: string; copied: boolean; onCopy: () => void }) {
  return (
    <div className="runner-cmd">
      <code className="runner-cmd-text">
        <span className="runner-cmd-prompt">$</span>
        {cmd}
      </code>
      <button className={`runner-copy ${copied ? 'copied' : ''}`} onClick={onCopy} type="button">
        {copied ? <CheckOutlined /> : <CopyOutlined />}
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  );
}

function Step({
  index,
  done,
  lineDone,
  last,
  title,
  desc,
  children,
}: {
  index: number;
  done: boolean;
  lineDone?: boolean;
  last?: boolean;
  title: string;
  desc: string;
  children: React.ReactNode;
}) {
  return (
    <div className="runner-step">
      <div className="runner-step-rail">
        <div className={`runner-step-dot ${done ? 'done' : ''}`}>
          {done ? <CheckOutlined /> : index}
        </div>
        {!last && <div className={`runner-step-line ${lineDone ? 'done' : ''}`} />}
      </div>
      <div className="runner-step-body">
        <div className="runner-step-title">{title}</div>
        <div className="runner-step-desc">{desc}</div>
        {children}
      </div>
    </div>
  );
}

/** Right-pane guide for connecting a new runner machine (shown from the side panel's “Add”). */
export function RunnerRegisterGuide() {
  const navigate = useNavigate();
  const [os, setOs] = useState<OS>('macOS');
  const [copied, setCopied] = useState<string | null>(null);
  const { install: installCmd, register: registerCmd } = buildCommands(__PUBLIC_ORIGIN__);

  const copy = (key: string, text: string) => {
    void navigator.clipboard?.writeText(text)?.catch(() => {});
    setCopied(key);
    // Revert the “✓ Copied” affordance after a beat (unless another copy supersedes it).
    setTimeout(() => setCopied((k) => (k === key ? null : k)), 1600);
  };

  // Reuse the sidebar's runner-online signal (same ['runners'] query + cache); poll a
  // little faster while the user is actively waiting for the handshake to complete.
  const runners = useQuery({
    queryKey: ['runners'],
    queryFn: () => api<Runner[]>('/runners'),
    refetchInterval: 5000,
  });
  const list = runners.data;

  // There is no realtime "runner came online" push, so detect the handshake by polling
  // the runner list (the same signal that drives the sidebar's online dot) and watching
  // for a runner that wasn't already online when this page opened.
  // TODO: switch to a push signal if the API ever exposes one.
  const baselineOnline = useRef<Set<string> | null>(null);
  const [connectedName, setConnectedName] = useState<string | null>(null);
  useEffect(() => {
    if (!list) return;
    if (baselineOnline.current === null) {
      // First load establishes the baseline; nothing to detect yet.
      baselineOnline.current = new Set(list.filter((r) => r.online).map((r) => r.id));
      return;
    }
    if (connectedName) return; // latch the first runner we see come online
    const fresh = list.find((r) => r.online && !baselineOnline.current!.has(r.id));
    if (fresh) setConnectedName(fresh.name);
  }, [list, connectedName]);

  const connected = connectedName !== null;

  return (
    <div className="runner-guide">
      <div className="runner-center">
        <h1 className="page-title">Add a runner</h1>
        <p className="runner-sub">
          A runner is a machine that runs Claude Code tasks for you. Run these on the machine you
          want to add — it appears in the list on the left once it comes online.
        </p>

        <Segmented
          className="runner-os"
          value={os}
          onChange={(v) => setOs(v as OS)}
          options={['macOS', 'Linux', 'Windows']}
        />

        {/* Step 1 reads as complete by design; step 2 flips to done on handshake. */}
        <Step
          index={1}
          done
          lineDone={connected}
          title="Install the CLI"
          desc="Installs the orbit CLI on this machine."
        >
          <CommandBox
            cmd={installCmd[os]}
            copied={copied === 'install'}
            onCopy={() => copy('install', installCmd[os])}
          />
        </Step>

        <Step
          index={2}
          done={connected}
          last
          title="Register & approve"
          desc="Opens your browser to confirm this machine belongs to you."
        >
          <CommandBox
            cmd={registerCmd}
            copied={copied === 'register'}
            onCopy={() => copy('register', registerCmd)}
          />
        </Step>

        {connected ? (
          <div className="runner-status connected">
            <CheckCircleFilled className="runner-status-icon" />
            <div className="runner-status-text">
              <div className="runner-status-title">Runner online — “{connectedName}” is ready</div>
              <div className="runner-status-sub">
                It's now in the sidebar under Runners. You can close this page.
              </div>
            </div>
            <button className="runner-done-btn" onClick={() => navigate('/tasks')} type="button">
              Done
            </button>
          </div>
        ) : (
          <div className="runner-status waiting">
            <span className="runner-spinner" />
            <div className="runner-status-text">
              <div className="runner-status-title">
                Waiting for your first runner to come online…
              </div>
              <div className="runner-status-sub">
                Keep this page open — it'll update automatically once the handshake completes.
              </div>
            </div>
            {/* TODO: link to runner setup/troubleshooting docs when available. */}
            <a className="runner-help-link">Having trouble?</a>
          </div>
        )}
      </div>
    </div>
  );
}
