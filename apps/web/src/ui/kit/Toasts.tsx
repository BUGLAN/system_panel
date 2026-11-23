/** 顶部提示条（参考稿 #toasts / .toast） */
import { AnimatePresence, motion } from 'motion/react';
import { EASE } from '../../design/tokens';
import { useUi } from '../../store/uiStore';

export function Toasts() {
  const toasts = useUi((s) => s.toasts);
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
      </AnimatePresence>
    </div>
  );
}
