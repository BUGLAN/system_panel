/** 断网时顶部一条细提示：只能看、不能改（写操作会提示「需要联网」） */
import { AnimatePresence, motion } from 'motion/react';
import { useSync } from '../../store/game';
import { useUi } from '../../store/uiStore';

export function OfflineBar() {
  const online = useSync((s) => s.online);
  const scene = useUi((s) => s.scene);
  const show = !online && scene !== 'boot';
  return (
    <AnimatePresence>
      {show && (
        <motion.div
          className="offline-bar"
          role="status"
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ duration: 0.24 }}
        >
          OFFLINE · 没联网，只能看，不能改
        </motion.div>
      )}
    </AnimatePresence>
  );
}
