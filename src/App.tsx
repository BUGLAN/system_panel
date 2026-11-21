/**
 * 应用根。第 1 步只接上读档与自动存档；场景与状态机在第 4 步起接入。
 */
import { useEffect } from 'react';
import { persistence } from './store/app';
import { useGame } from './store/gameStore';

let booted: Promise<unknown> | null = null;

export function App() {
  const loaded = useGame((s) => s.loaded);
  const source = useGame((s) => s.source);

  useEffect(() => {
    // StrictMode 下 effect 会跑两次，读档只做一次
    booted ??= persistence.boot();
  }, []);

  return (
    <main
      style={{
        height: '100%',
        display: 'grid',
        placeItems: 'center',
        background: 'var(--bg)',
        fontFamily: 'var(--fm)',
        color: 'var(--acid)',
        letterSpacing: 4,
        fontSize: 12,
      }}
    >
      {loaded ? `SYSTEM ONLINE · ${source ?? ''}` : 'BOOTING…'}
    </main>
  );
}
