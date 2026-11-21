/** 确认弹窗（参考稿 #modal）：弹入 .2,1.4,.4,1；遮罩点击 = 再想想 */
import { AnimatePresence, motion } from 'motion/react';
import { EASE } from '../../design/tokens';
import { useUi } from '../../store/uiStore';
import { Btn } from './Btn';
import { parseHighlight } from './Typewriter';

export function ConfirmHost() {
  const c = useUi((s) => s.confirm);
  return (
    <AnimatePresence>
      {c && (
        <motion.div
          className="ovl on"
          style={{ zIndex: 80 }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, transition: { duration: 0.24 } }}
          onPointerDown={(e) => {
            if (e.target === e.currentTarget) c.resolve(false);
          }}
        >
          <motion.div
            className="modal"
            initial={{ scale: 0.8, y: 30, opacity: 0 }}
            animate={{ scale: 1, y: 0, opacity: 1 }}
            transition={{ duration: 0.42, ease: EASE.pop }}
          >
            <h3>{c.title}</h3>
            <p>
              {c.body.split('\n').map((line, i) => (
                <span key={i} style={{ display: 'block' }}>
                  {parseHighlight(line).map((ch, j) =>
                    ch.hl ? (
                      <b key={j} style={{ color: 'var(--cyan)' }}>
                        {ch.c}
                      </b>
                    ) : (
                      ch.c
                    ),
                  )}
                </span>
              ))}
            </p>
            <div className="mb">
              <Btn kind="ghost" onClick={() => c.resolve(false)}>
                {c.no}
              </Btn>
              <Btn
                kind="pri"
                onClick={() => c.resolve(true)}
                style={
                  c.danger
                    ? { ['--bd' as string]: 'var(--hot)', ['--bb' as string]: 'var(--hot)' }
                    : undefined
                }
              >
                {c.yes}
              </Btn>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
