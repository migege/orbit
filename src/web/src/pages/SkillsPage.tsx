import { useQuery } from '@tanstack/react-query';
import { Spin } from 'antd';
import { useLayoutEffect, useRef, useState } from 'react';
import type { SlashCommandInfo } from '@orbit/shared';
import { api } from '../api';
import { agentsQuery } from '../lib/queries';
import type { Runner } from '../components/TasksSidePanel';

// One catalog row: the skill/command name plus its (often long) routing description.
// The description is the SKILL.md frontmatter written for the model, so it can run several
// lines; we clamp it to two and let the user expand only the ones that are actually cut off.
function SkillRow({ item }: { item: SlashCommandInfo }) {
  const descRef = useRef<HTMLSpanElement>(null);
  const [expanded, setExpanded] = useState(false);
  const [overflowing, setOverflowing] = useState(false);

  useLayoutEffect(() => {
    const el = descRef.current;
    if (!el) return;
    // Measured while collapsed (clamped) — only offer "expand" when text is truncated.
    setOverflowing(el.scrollHeight > el.clientHeight + 1);
  }, [item.description]);

  return (
    <div className="skill-item">
      <span className="skill-name">/{item.name}</span>
      {item.description && (
        <span className="skill-desc-wrap">
          <span ref={descRef} className={`skill-desc${expanded ? ' expanded' : ''}`}>
            {item.description}
          </span>
          {(overflowing || expanded) && (
            <button
              type="button"
              className="skill-desc-toggle"
              onClick={() => setExpanded((v) => !v)}
            >
              {expanded ? 'Collapse' : 'Expand'}
            </button>
          )}
        </span>
      )}
    </div>
  );
}

// Runners report the slash commands (.claude/commands) and skills (.claude/skills)
// they found on disk via heartbeat; GET /runners surfaces them as runner.commands /
// runner.skills, each tagged with the agent whose workDir it came from (empty = host,
// shared by all agents). This page groups that catalog by runner, then by scope —
// host-level assets, then each agent — so a skill two agents share (e.g. a dev and a
// prod checkout) reads as "both have it" instead of a bare duplicate.
export function SkillsPage() {
  const runners = useQuery({
    queryKey: ['runners'],
    queryFn: () => api<Runner[]>('/runners'),
    refetchInterval: 15_000,
  });
  const agents = useQuery(agentsQuery());
  const list = runners.data ?? [];

  // agentId -> display name, so a project-scoped group reads as the agent, not a uuid.
  const agentName = (id: string): string =>
    (agents.data ?? []).find((a: { id: string }) => a.id === id)?.name ?? id;

  const [query, setQuery] = useState('');
  const q = query.trim().toLowerCase();
  const match = (it: SlashCommandInfo) =>
    !q ||
    it.name.toLowerCase().includes(q) ||
    (it.description?.toLowerCase().includes(q) ?? false);

  const renderGroup = (title: string, items: SlashCommandInfo[], keyPrefix: string) => {
    if (items.length === 0) return null;
    return (
      <div className="skills-group">
        <div className="skills-group-title">{title}</div>
        {items.map((it) => (
          <SkillRow item={it} key={`${keyPrefix}:${it.name}`} />
        ))}
      </div>
    );
  };

  // Split a runner's assets by scope: the host bucket (no agentId, shared by every agent)
  // first, then one bucket per agent that owns project-level assets, sorted by name.
  type Scope = { key: string; title: string; skills: SlashCommandInfo[]; commands: SlashCommandInfo[] };
  const scopesFor = (skills: SlashCommandInfo[], commands: SlashCommandInfo[]): Scope[] => {
    const map = new Map<string, Scope>();
    const bucket = (agentId?: string): Scope => {
      const key = agentId || '';
      let s = map.get(key);
      if (!s) {
        s = { key, title: key === '' ? 'Host' : agentName(key), skills: [], commands: [] };
        map.set(key, s);
      }
      return s;
    };
    for (const sk of skills) bucket(sk.agentId).skills.push(sk);
    for (const c of commands) bucket(c.agentId).commands.push(c);
    return [...map.values()].sort((a, b) =>
      a.key === '' ? -1 : b.key === '' ? 1 : a.title.localeCompare(b.title),
    );
  };

  // Per-runner filtered view; when searching, runners with no match drop out entirely.
  const cards = list
    .map((r) => ({
      runner: r,
      skills: (r.skills ?? []).filter(match),
      commands: (r.commands ?? []).filter(match),
    }))
    .filter((c) => !q || c.skills.length > 0 || c.commands.length > 0);

  return (
    <div className="skills-page">
      <h1 className="page-title">Skills</h1>

      {runners.isLoading ? (
        <div style={{ padding: 48, textAlign: 'center' }}>
          <Spin />
        </div>
      ) : list.length === 0 ? (
        <div className="skills-empty">
          No skills yet — skills come from a runner's <code>.claude/skills/</code> (and
          commands from <code>.claude/commands/</code>). Register a machine to get started.
        </div>
      ) : (
        <>
          <input
            className="skills-search"
            type="text"
            placeholder="Search skills / commands…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {cards.length === 0 ? (
            <div className="skills-no-match">No skills or commands match "{query}".</div>
          ) : (
            <div className="skills-list">
              {cards.map(({ runner: r, skills, commands }) => {
                const empty = skills.length === 0 && commands.length === 0;
                const scopes = scopesFor(skills, commands);
                // Only surface scope headers when assets actually span agents; a runner
                // whose assets are all host-level keeps the simple flat layout.
                const flat = scopes.length <= 1;
                return (
                  <div className="skills-runner" key={r.id}>
                    <div className="skills-runner-head">
                      <span
                        className="runner-dot"
                        style={{ background: r.online ? 'var(--success-solid)' : 'var(--dot-idle)' }}
                        title={r.online ? 'Online' : 'Offline'}
                      />
                      <span className="skills-runner-name">{r.displayName || r.name}</span>
                      <span className="skills-runner-status">
                        {r.online ? 'Online' : 'Offline'}
                      </span>
                    </div>
                    {flat ? (
                      <>
                        {renderGroup('Skills', skills, 'skill')}
                        {renderGroup('Commands', commands, 'cmd')}
                      </>
                    ) : (
                      scopes.map((s) => (
                        <div className="skills-scope" key={s.key}>
                          <div className="skills-scope-title">{s.title}</div>
                          {renderGroup('Skills', s.skills, `${s.key}:skill`)}
                          {renderGroup('Commands', s.commands, `${s.key}:cmd`)}
                        </div>
                      ))
                    )}
                    {empty && (
                      <div className="skills-runner-empty">No skills or commands reported.</div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}
    </div>
  );
}
