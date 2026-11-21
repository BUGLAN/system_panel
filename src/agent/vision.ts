/**
 * 证据视觉校验：一张压缩后的 JPEG + 任务说明 → 4 态结论。
 * 移植自 flutter-final:app/lib/agent/vision_core.dart。
 *  - 超时 30 秒、超时不重试（客户端统一规则）
 *  - 没配 / 关了 / 失败 → 未校验（照收）
 */
import type { EvidenceStatus } from '../core/model/active';
import type { Quest } from '../core/model/quest';
import type { LlmClient } from './llmClient';

export const VERIFY_TIMEOUT_MS = 30_000;
/** 交单时最多等后台校验多久 */
export const SUBMIT_WAIT_MS = 20_000;

export interface VisionVerdict {
  status: EvidenceStatus;
  note: string;
}

const SYSTEM =
  '你是系统「小祥」的验收模块。给你一张任务证据图，判断它是否真实完成了任务。' +
  '只输出一个 JSON 对象，格式：{"match": true|false|"unsure","note":"≤40字中文短句"}。' +
  'match=true 表示证据可信；看不清、拿不准、像翻拍的一律 "unsure"；明显不符为 false。';

export const unverified = (note: string): VisionVerdict => ({ status: 'unverified', note });

/** 备注截到 40 个字 */
export function clampNote(raw: string): string {
  const t = raw.trim();
  const cs = [...t];
  return cs.length <= 40 ? t : cs.slice(0, 40).join('');
}

/** 解析模型回的判词（容忍前后有废话：取第一个 { 到最后一个 }） */
export function parseVerdict(text: string): VisionVerdict {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return unverified('响应不是有效 JSON');
  let v: unknown;
  try {
    v = JSON.parse(text.slice(start, end + 1));
  } catch {
    return unverified('JSON 解析失败');
  }
  if (!v || typeof v !== 'object' || Array.isArray(v)) return unverified('响应不是 JSON 对象');
  const o = v as Record<string, unknown>;
  const note = clampNote(String(o['note'] ?? ''));
  const match = o['match'];
  if (match === true || match === 'true') return { status: 'verified', note };
  if (match === false || match === 'false')
    return { status: 'mismatch', note: note || '证据和任务对不上' };
  if (match === 'unsure') return { status: 'unsure', note: note || '证据存疑' };
  return unverified('match 字段无法识别');
}

/** 校验一张证据（dataUrl = data:image/jpeg;base64,…）。永不抛。 */
export async function verifyEvidence(o: {
  client: LlmClient | null;
  quest: Quest;
  dataUrl: string;
  signal?: AbortSignal;
}): Promise<VisionVerdict> {
  if (!o.client) return unverified('视觉校验没开或没配好');
  try {
    const r = await o.client.chat({
      messages: [
        { role: 'system', text: SYSTEM },
        {
          role: 'user',
          text: `任务《${o.quest.name}》，证明要求：${o.quest.proof}。判断下面这些证据图。`,
          images: [o.dataUrl],
        },
      ],
      temperature: 0,
      timeoutMs: VERIFY_TIMEOUT_MS,
      ...(o.signal ? { signal: o.signal } : {}),
    });
    if (!r.ok) return unverified(`校验失败：${r.detail}`);
    return parseVerdict(r.text);
  } catch {
    return unverified('校验失败');
  }
}
