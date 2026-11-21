/**
 * 系统说话的四个入口（四语气）：发布 / 结算 / 毒舌 / 追问。
 * 先从台词库取一句兜底；配了模型且场合值得时才问 LLM（8 秒到点就回台词库），永不抛。
 * 移植自 flutter-final:app/lib/agent/copy.dart。
 */
import { COPY, fillLine, pickBySeed } from '../core/data/lines';
import type { Rank } from '../core/data/rank';
import { fmtMin } from '../core/format';
import type { LlmClient } from './llmClient';
import type { MemoryStore } from './memory';
import { TONES, buildConversation, splitTag, type Emotion, type ToneKey } from './persona';

export const LINE_TIMEOUT_MS = 8_000;
export const LINE_MAX_CHARS = 300;

export interface CopyContext {
  lv: number;
  streak: number;
  bestStreak: number;
  queue: number;
  done: number;
  planTotal: number;
  goalShort: string;
  weakestAttr: string;
  failCount: number;
  questName: string;
  questRank: Rank | '';
  questMinutes: number;
  questCheckin: boolean;
  questProof: string;
  exp: number;
  coin: number;
  crit: boolean;
  photos: number;
  topic: string;
}

export function emptyCopyContext(): CopyContext {
  return {
    lv: 1,
    streak: 0,
    bestStreak: 0,
    queue: 0,
    done: 0,
    planTotal: 0,
    goalShort: '',
    weakestAttr: '',
    failCount: 0,
    questName: '',
    questRank: '',
    questMinutes: 0,
    questCheckin: false,
    questProof: '',
    exp: 0,
    coin: 0,
    crit: false,
    photos: 0,
    topic: '',
  };
}

export type SettleTier = 'low' | 'mid' | 'high' | 'top';

export function tierOf(rank: string): SettleTier {
  switch (rank.toUpperCase()) {
    case 'D':
    case 'C':
      return 'mid';
    case 'B':
    case 'A':
      return 'high';
    case 'S':
      return 'top';
    default:
      return 'low';
  }
}

const SETTLE_POOL: Record<SettleTier, readonly string[]> = {
  low: COPY.settleLow,
  mid: COPY.settleMid,
  high: COPY.settleHigh,
  top: COPY.settleTop,
};
const SETTLE_EMOTION: Record<SettleTier, Emotion> = {
  low: 'cold',
  mid: 'pleased',
  high: 'smug',
  top: 'proud',
};

export interface CopyLine {
  text: string;
  source: 'llm' | 'template';
  emotion: Emotion;
}

function seedOf(c: CopyContext): string {
  return `lv${c.lv}|st${c.streak}|q${c.queue}|done${c.done}|fail${c.failCount}|${c.questName}|${c.exp}|${c.coin}|${c.topic}`;
}

/** 填空（保证不残留 {xx}） */
export function fillCopy(template: string, c: CopyContext): string {
  const minutes = c.questCheckin
    ? '打卡单，随时交'
    : c.questMinutes > 0
      ? fmtMin(c.questMinutes)
      : '';
  return fillLine(template, {
    n: c.queue,
    lv: c.lv,
    streak: c.streak,
    best: c.bestStreak,
    queue: c.queue,
    fail: c.failCount,
    rank: c.questRank || 'F',
    name: c.questName || '无名之单',
    minutes,
    proof: c.questProof || '能证明的截图',
    exp: c.exp,
    coin: c.coin,
    photos: c.photos,
    done: c.done,
    left: Math.max(0, c.planTotal - c.done),
    total: c.planTotal,
    goal: c.goalShort || '你的目标',
    attr: c.weakestAttr,
    topic: c.topic || '目标与计划',
    dl: '明天',
  });
}

function brief(tone: ToneKey, c: CopyContext, extra: string): string {
  const quest = c.questName
    ? `本单「${c.questName}」（${c.questRank} 级 · ${c.questCheckin ? '打卡单，不计时' : `${c.questMinutes} 分钟`}` +
      `${c.questProof ? ` · 证据：${c.questProof}` : ''}）。`
    : '';
  const goal = c.goalShort ? `主线「${c.goalShort}」` : '未立目标';
  return (
    `现场事实：宿主 LV${c.lv}，连击 ${c.streak}（最好 ${c.bestStreak}），手里 ${c.queue} 单，` +
    `${goal}（${c.done}/${c.planTotal} 单），最弱维 ${c.weakestAttr}，连败 ${c.failCount} 次。${quest}` +
    `${extra ? ` ${extra}` : ''}\n` +
    `要求：${tone === '追问' ? '只输出一个问题，不超过 30 字' : '只输出一句台词，不超过 40 字'}，句首加 [情绪] 标签。`
  );
}

export class SystemCopy {
  constructor(
    private readonly client: LlmClient | null,
    private readonly memory: MemoryStore | null = null,
  ) {}

  private async speak(
    tone: ToneKey,
    c: CopyContext,
    pool: readonly string[],
    emotion: Emotion,
    extra = '',
    useLlm = true,
  ): Promise<CopyLine> {
    const template = fillCopy(pickBySeed(pool, `${seedOf(c)}|${tone}`), c);
    const fallback: CopyLine = { text: template, source: 'template', emotion };
    if (!useLlm || !this.client?.configured) return fallback;
    try {
      const digest = this.memory ? await this.memory.digest(`${c.questName} ${c.topic}`) : '';
      const r = await this.client.chat({
        messages: buildConversation({
          userText: brief(tone, c, extra),
          memoryDigest: digest,
          scenario: `${TONES[tone]} 只输出一句她的台词本身，不要任何解释。`,
        }).map((m) => ({ role: m.role, text: m.text })),
        timeoutMs: LINE_TIMEOUT_MS,
      });
      if (!r.ok) return fallback;
      const t = splitTag(r.text);
      if (!t.text) return fallback;
      return {
        text: t.text.slice(0, LINE_MAX_CHARS),
        source: 'llm',
        emotion: t.emotion === 'neutral' ? emotion : t.emotion,
      };
    } catch {
      return fallback;
    }
  }

  /** 发布：钉单时（发布 ≤800ms，只走台词库） */
  dispatchLine(c: CopyContext): Promise<CopyLine> {
    return this.speak('发布', c, COPY.dispatch, 'neutral', '', false);
  }

  /** 结算：按档位点评 */
  settleLine(c: CopyContext, useLlm = true): Promise<CopyLine> {
    const t = tierOf(c.questRank);
    return this.speak(
      '结算',
      c,
      SETTLE_POOL[t],
      SETTLE_EMOTION[t],
      `本单结算 EXP +${c.exp}、晶核 +${c.coin}${c.crit ? '（暴击！）' : ''}`,
      useLlm,
    );
  }

  /** 毒舌：连败 / 退缩 / 空证据 */
  roastLine(c: CopyContext, reason = ''): Promise<CopyLine> {
    return this.speak('毒舌', c, COPY.roast, 'annoyed', reason ? `宿主刚才的行为：${reason}` : '');
  }

  /** 追问 */
  probeLine(c: CopyContext, topic = ''): Promise<CopyLine> {
    return this.speak(
      '追问',
      c,
      COPY.probe,
      'neutral',
      `追问话题：${topic || c.topic || '目标与计划'}`,
    );
  }
}
