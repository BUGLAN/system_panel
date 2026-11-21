/**
 * 底板（参考稿 #sheet）：遮罩淡入 200ms + 面板 440ms 从底部滑入；点遮罩关闭。
 * 另有整页面板（Panel）：给 LLM 设置、换目标这类「弹窗式面板」用，右上角 ✕（docs/50 A18）。
 */
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { ReactNode } from 'react';
import { EASE } from '../../design/tokens';
import { Tap } from './Btn';
import { IconClose } from './icons';

export function Sheet({
  open,
  onClose,
  title,
  children,
  className = '',
}: {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
  className?: string;
}) {
  const reduce = useReducedMotion();
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="ovl on"
          id="sheet"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, transition: { duration: 0.26 } }}
          transition={{ duration: 0.2 }}
          onPointerDown={(e) => {
            if (e.target === e.currentTarget) onClose();
          }}
        >
          <motion.div
            className={`sheet ${className}`}
            initial={reduce ? { opacity: 0 } : { y: '100%' }}
            animate={reduce ? { opacity: 1 } : { y: 0 }}
            exit={
              reduce
                ? { opacity: 0 }
                : { y: '100%', transition: { duration: 0.26, ease: [0.7, 0, 0.2, 1] } }
            }
            transition={{ duration: 0.44, ease: EASE.ease }}
          >
            <div className="grab" />
            {title && <h3>{title}</h3>}
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export function Panel({
  open,
  onClose,
  eyebrow,
  title,
  children,
  accent = 'var(--cyan)',
}: {
  open: boolean;
  onClose: () => void;
  eyebrow: string;
  title: string;
  children: ReactNode;
  accent?: string;
}) {
  const reduce = useReducedMotion();
  return (
    <AnimatePresence>
      {open && (
        <motion.section
          className="panel"
          style={{ ['--accent' as string]: accent }}
          initial={reduce ? { opacity: 0 } : { opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: reduce ? 0 : 30, transition: { duration: 0.24 } }}
          transition={{ duration: 0.42, ease: EASE.ease }}
        >
          <div className="sh">
            <div>
              <div className="eyebrow">{eyebrow}</div>
              <h1 className="h1">{title}</h1>
            </div>
            <Tap className="xbtn" aria-label="关闭" onClick={onClose}>
              <IconClose />
            </Tap>
          </div>
          <div className="panel-body">{children}</div>
        </motion.section>
      )}
    </AnimatePresence>
  );
}
