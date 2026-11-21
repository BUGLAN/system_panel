/** 顶部提示条 + 名牒解锁卡（参考稿 #toasts / .toast / .ach） */
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useRef } from 'react';
import { EASE } from '../../design/tokens';
import { TITLES } from '@host/core/data/titles';
import { sfx } from '../../audio/sfx';
import { uiStore, useUi } from '../../store/uiStore';
import { burst, center } from '../fx/fx';

function AchCard({ id, onDone }: { id: string; onDone: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const t = TITLES.find((x) => x.id === id);
  const no = String(TITLES.findIndex((x) => x.id === id) + 1).padStart(2, '0');
  useEffect(() => {
    sfx.play('unlock');
    const a = setTimeout(() => {
      const [x, y] = center(ref.current);
      burst(x, y, {
        type: 'star',
        n: 24,
        colors: ['#ffcc4d', '#fff'],
        min: 2,
        max: 8,
        g: 0.05,
        life: 40,
        sz: 3,
      });
    }, 200);
    const b = setTimeout(onDone, 2900);
    return () => {
      clearTimeout(a);
      clearTimeout(b);
    };
  }, [onDone]);
  if (!t) return null;
  return (
    <motion.div
      ref={ref}
      className={`ach ${t.shame ? 'shame' : ''}`}
      initial={{ opacity: 0, y: -40, scale: 0.8 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: -30 }}
      transition={{ duration: 0.52, ease: [0.2, 1.5, 0.4, 1] }}
    >
      <div className="medal">
        <span>{no}</span>
      </div>
      <div>
        <small>{t.shame ? '耻辱称号 · 摘不掉' : '名牒解锁 · NEW TITLE'}</small>
        <b>「{t.name}」</b>
        <p>{t.hint} · 去档案看看</p>
      </div>
    </motion.div>
  );
}

const achDone = () => uiStore.setState((s) => ({ achQueue: s.achQueue.slice(1) }));

export function Toasts() {
  const toasts = useUi((s) => s.toasts);
  const ach = useUi((s) => s.achQueue);
  const blocking = useUi((s) => s.show !== null);
  const cur = blocking ? null : (ach[0] ?? null);
  return (
    <div id="toasts">
      <AnimatePresence>
        {toasts.map((t) => (
          <motion.div
            key={t.id}
            className={`toast ${t.kind}`}
            initial={{ opacity: 0, y: -30, scale: 0.9 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -20, transition: { duration: 0.3 } }}
            transition={{ duration: 0.4, ease: EASE.pop }}
          >
            <i />
            <span>{t.text}</span>
          </motion.div>
        ))}
        {cur && <AchCard key={cur} id={cur} onDone={achDone} />}
      </AnimatePresence>
    </div>
  );
}
