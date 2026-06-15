import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { api, getToken } from '../api';

// Routes that render their own loaders and have no first-screen data to wait on.
const BYPASS = ['/login', '/enroll'];

// Fade out and remove the first-paint splash defined in index.html.
const finishBoot = () => (window as unknown as { __bootDone?: () => void }).__bootDone?.();

/**
 * Holds the app behind the index.html boot splash until the first-screen data
 * (tasks + runners) has resolved, so the UI appears in one shot instead of
 * filling in piecemeal. The queries share their keys with the page/sidebar, so
 * those read straight from cache and never refetch. Only the authenticated app
 * waits — login/enroll pass straight through. The decision is made once on mount
 * and latched, so the 15s/3s background refetches never bring the splash back.
 */
export function BootGate({ children }: { children: React.ReactNode }) {
  const loc = useLocation();
  const [gated] = useState(() => !!getToken() && !BYPASS.includes(loc.pathname));
  const [booted, setBooted] = useState(() => !gated);

  const tasks = useQuery({
    queryKey: ['tasks'],
    queryFn: () => api<unknown[]>('/tasks'),
    enabled: gated,
  });
  const runners = useQuery({
    queryKey: ['runners'],
    queryFn: () => api<unknown[]>('/runners'),
    enabled: gated,
  });

  // Reveal once both critical queries settle (success OR error — never trap the
  // user behind the splash), with a hard timeout as a final backstop.
  const ready = tasks.isFetched && runners.isFetched;
  useEffect(() => {
    if (booted) return;
    if (ready) {
      setBooted(true);
      return;
    }
    const t = setTimeout(() => setBooted(true), 8000);
    return () => clearTimeout(t);
  }, [ready, booted]);

  useEffect(() => {
    if (booted) finishBoot();
  }, [booted]);

  return booted ? <>{children}</> : null;
}
