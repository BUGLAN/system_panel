/**
 * 接单前简报（B6）：编号 + 档位；预计耗时 / 证据 / 奖励三行 + 她一句；
 * 【开始】才进执行面板、记 startAt；【再想想】/ 点遮罩 / 返回键收起，单子不动。不计时、不判负。
 */
import { lootText, questCode, timeLabel } from '@host/core/flow/questText';
import { RANK_COLORS } from '../../design/tokens';
import { startQuest } from '../../store/actions/exec';
import { setUi, useUi } from '../../store/uiStore';
import { Btn } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

export function Briefing() {
  const q = useUi((s) => s.briefing);
  const close = () => setUi({ briefing: null });
  return (
    <Sheet open={!!q} onClose={close} className="brief">
      {q && (
        <div style={{ ['--gc' as string]: RANK_COLORS[q.rank] }}>
          <div className="bf-h">
            <span className="gbadge">{q.rank}</span>
            <span className="bf-code">BRIEF · 接单前简报 · {questCode(q)}</span>
          </div>
          <h3 className="bf-t">{q.name}</h3>
          <div className="bf-rows">
            <div>
              <span>耗时</span>
              <b>{timeLabel(q)} · 不计时</b>
            </div>
            <div>
              <span>证据</span>
              <b>{q.proof} · 1–3 张</b>
            </div>
            <div>
              <span>奖励</span>
              <b>{lootText(q)}</b>
            </div>
          </div>
          <p className="bf-line">看清楚再接。做完拍下来交给我，不赶时间。</p>
          <div className="bf-act">
            <Btn kind="ghost" sm onClick={close}>
              再想想
            </Btn>
            <Btn kind="pri" sm grow onClick={() => void startQuest(q)}>
              开始
            </Btn>
          </div>
        </div>
      )}
    </Sheet>
  );
}
