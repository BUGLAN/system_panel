/**
 * 接单前简报（B6）：编号 + 档位 + TIME TRIAL / CHECK-IN；时长 / 证据 / 奖励 / 判负四行 + 她一句；
 * 【开始计时】才进执行面板、记 startAt；【再想想】/ 点遮罩 / 返回键收起，单子不动。
 */
import { attrsText, lootText, questCode } from '../../core/flow/questText';
import { fmtMin } from '../../core/format';
import { RANK_COLORS } from '../../design/tokens';
import { startQuest } from '../../store/actions/exec';
import { setUi, useUi } from '../../store/uiStore';
import { Btn } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

export function Briefing() {
  const q = useUi((s) => s.briefing);
  const close = () => setUi({ briefing: null });
  const line = !q
    ? ''
    : q.kind === 'remedy' && q.planIndex >= 0
      ? '这张顶替刚才那一环：做一半就算数，交了这一环就算过关。'
      : q.kind === 'remedy'
        ? '补救单，做一半就算数。别再半路跑了。'
        : !q.timed
          ? '打卡单不计时。做完拍下来，今天之内交就行。'
          : '看清楚再接。东西先备好，计时从你点「开始」那一刻算。';
  return (
    <Sheet open={!!q} onClose={close} className="brief">
      {q && (
        <div style={{ ['--gc' as string]: RANK_COLORS[q.rank] }}>
          <div className="bf-h">
            <span className="gbadge">{q.rank}</span>
            <span className="bf-code">BRIEF · 接单前简报 · {questCode(q)}</span>
            <span className="bf-mode">{q.timed ? 'TIME TRIAL' : 'CHECK-IN'}</span>
          </div>
          <h3 className="bf-t">{q.name}</h3>
          <div className="bf-rows">
            <div>
              <span>时长</span>
              <b>{q.timed ? `${fmtMin(q.minutes)} · 点开始才计时` : '不计时 · 今天内交'}</b>
            </div>
            <div>
              <span>证据</span>
              <b>{q.proof} · 1–3 张</b>
            </div>
            <div>
              <span>奖励</span>
              <b>
                {lootText(q)}
                {attrsText(q.attrs) ? ` · ${attrsText(q.attrs)}` : ''}
              </b>
            </div>
            {q.timed && (
              <div>
                <span>判负</span>
                <b>超过 {fmtMin(q.minutes)} 没交 / 认输</b>
              </div>
            )}
          </div>
          <p className="bf-line">{line}</p>
          <div className="bf-act">
            <Btn kind="ghost" sm onClick={close}>
              再想想
            </Btn>
            <Btn kind="pri" sm grow onClick={() => void startQuest(q)}>
              {q.timed ? '开始计时' : '开始 · 不计时'}
            </Btn>
          </div>
        </div>
      )}
    </Sheet>
  );
}
