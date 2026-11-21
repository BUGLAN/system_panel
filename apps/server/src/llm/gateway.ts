/**
 * 每个用户的 LLM 入口：设置（服务器默认 / 自己的）→ 客户端；同意闸门 + 额度闸门挂在客户端上。
 *  - 限速：每人每分钟 ratePerMin 次（文本 / 视觉分开算），自己的 Key 也限
 *  - 每日上限：只对用服务器默认 Key 的普通用户；管理员不限
 */
import { dayKey } from '@host/core/time/day';
import { LlmClient, type FetchLike } from '../agent/llmClient';
import type { AuthUser } from '../auth/accounts';
import type { Deps } from '../http/context';
import { hasConsent } from '../repo/consent';
import { effective, loadSettings, type StoredSettings } from '../repo/llmSettings';
import { bumpUsage, usageOf, type UsageKind } from '../repo/usage';

export interface UserLlm {
  mode: 'own' | 'server';
  /** 文本客户端：没配好也给（拆解链路要拿到 noKey 去走失败卡） */
  text: LlmClient;
  /** 视觉客户端：关了 / 没配视觉模型 = null（证据按未校验照收） */
  vision: LlmClient | null;
  temperature: number;
}

export function dailyLimits(deps: Deps, user: AuthUser, mode: 'own' | 'server') {
  if (mode === 'own' || user.role === 'admin') return null;
  return { text: deps.config.quotas.dailyText, vision: deps.config.quotas.dailyVision };
}

function gateFor(deps: Deps, user: AuthUser, mode: 'own' | 'server', kind: UsageKind) {
  return (): string | null => {
    const wait = deps.limiter.hit(`llm-${kind}:${user.id}`, deps.config.quotas.ratePerMin, 60_000);
    if (wait > 0) return `太快了，${wait} 秒后再试。`;
    const db = deps.dbh.db;
    const day = dayKey(deps.now(), user.tz);
    const lim = dailyLimits(deps, user, mode);
    if (lim) {
      const used = usageOf(db, user.id, day);
      const cap = kind === 'text' ? lim.text : lim.vision;
      if ((kind === 'text' ? used.text : used.vision) >= cap)
        return `今天的${kind === 'text' ? '文本' : '验图'}额度（${cap} 次）用完了，明天再来，或者在设置里填你自己的 Key。`;
    }
    bumpUsage(db, user.id, day, kind);
    return null;
  };
}

export function llmFor(deps: Deps, user: AuthUser, stored?: StoredSettings): UserLlm {
  const s = stored ?? loadSettings(deps.dbh.db, user.id);
  const e = effective(s, deps.config);
  const opts = (kind: UsageKind) => ({
    fetch: deps.fetch as FetchLike,
    consent: () => hasConsent(deps.dbh.db, user.id),
    gate: gateFor(deps, user, e.mode, kind),
    ...(deps.llmRetryDelayMs !== undefined ? { retryDelayMs: deps.llmRetryDelayMs } : {}),
  });
  const text = new LlmClient(
    { base: e.base, apiKey: e.apiKey, model: e.textModel, temperature: e.temperature },
    opts('text'),
  );
  const visionOk = e.visionEnabled && !!(e.base && e.apiKey && e.visionModel);
  const vision = visionOk
    ? new LlmClient({ base: e.base, apiKey: e.apiKey, model: e.visionModel }, opts('vision'))
    : null;
  return { mode: e.mode, text, vision, temperature: e.temperature };
}
