import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

export type ThemeMode = 'system' | 'light' | 'dark';
type Resolved = 'light' | 'dark';

const STORAGE_KEY = 'orbit-theme';
const mq = () => window.matchMedia('(prefers-color-scheme: dark)');

function readMode(): ThemeMode {
  const v = localStorage.getItem(STORAGE_KEY);
  return v === 'light' || v === 'dark' || v === 'system' ? v : 'system';
}

function resolve(mode: ThemeMode): Resolved {
  if (mode === 'system') return mq().matches ? 'dark' : 'light';
  return mode;
}

type Ctx = { mode: ThemeMode; resolved: Resolved; setMode: (m: ThemeMode) => void };
const ThemeContext = createContext<Ctx | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<ThemeMode>(readMode);
  const [resolved, setResolved] = useState<Resolved>(() => resolve(readMode()));

  // Reflect the resolved theme onto <html data-theme> (drives the CSS tokens) and
  // persist the user's choice. Re-runs whenever the mode changes.
  useEffect(() => {
    const r = resolve(mode);
    setResolved(r);
    document.documentElement.setAttribute('data-theme', r);
    localStorage.setItem(STORAGE_KEY, mode);
  }, [mode]);

  // While following the system, track OS-level light/dark changes live.
  useEffect(() => {
    if (mode !== 'system') return;
    const m = mq();
    const onChange = () => {
      const r = m.matches ? 'dark' : 'light';
      setResolved(r);
      document.documentElement.setAttribute('data-theme', r);
    };
    m.addEventListener('change', onChange);
    return () => m.removeEventListener('change', onChange);
  }, [mode]);

  return (
    <ThemeContext.Provider value={{ mode, resolved, setMode: setModeState }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useThemeMode(): Ctx {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useThemeMode must be used within ThemeProvider');
  return ctx;
}
