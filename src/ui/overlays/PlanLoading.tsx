/** 拆解的分步进度卡（整屏，防连点）：识别目标 → 拆这一段（段进度）→ 规则校验 */
import { AnimatePresence, motion } from 'motion/react';
import { useUi } from '../../store/uiStore';
import { Core } from '../kit/Core';
import { Typewriter } from '../kit/Typewriter';

const LINES: Record<string, string> = {
  match: '……我看看这是哪一类。',
  bind: '……行，让我把这条拆开。',
  retry: '再来一次。同一句话，我重新拆。',
  window: '这一段走完了 · 正在拆下一段。',
  finale: '整条主线走完了。下一条，我现在就排。',
  swap: '……行，让我把这条拆开。',
};

export function PlanLoading() {
  const job = useUi((s) => s.planJob);
  const steps =
    job?.kind === 'match'
      ? ['识别目标']
      : job?.kind === 'window'
        ? ['拆下一段', '规则校验']
        : ['识别目标', '拆这一段', '规则校验'];
  const stageIdx = (() => {
    if (!job) return 0;
    if (job.kind === 'window') return Math.max(0, job.progress.stage - 1);
    return job.progress.stage;
  })();
  return (
    <AnimatePresence>
      {job && (
        <motion.div
          className="ovl on plan-loading"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, transition: { duration: 0.24 } }}
        >
          <Core mood="scan" className="pl-core" />
          <h3 className="pl-t">{job.title}</h3>
          <Typewriter className="pl-line" text={LINES[job.kind] ?? ''} />
          <div className="pl-steps">
            {steps.map((s, i) => {
              const st = i < stageIdx ? 'done' : i === stageIdx ? 'cur' : '';
              const seg =
                st === 'cur' && job.progress.segTotal && job.progress.segTotal > 1
                  ? ` · ${job.progress.segDone ?? 0}/${job.progress.segTotal} 路`
                  : '';
              return (
                <div key={s} className={`pl-step ${st}`}>
                  <i>{st === 'done' ? '✓' : i + 1}</i>
                  <span>
                    {s}
                    {seg}
                  </span>
                </div>
              );
            })}
          </div>
          <small className="pl-hint">推理模型一轮可能要几十秒。别关页面。</small>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
