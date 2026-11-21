/**
 * 模型设置 / 测试连接 / 今日用量 / 同意与撤回。
 */
import { Hono } from 'hono';
import { z } from 'zod';
import { dayKey } from '@host/core/time/day';
import { failureText, type LlmClient } from '../agent/llmClient';
import { me, type AppEnv } from '../http/context';
import { body } from '../http/zod';
import { dailyLimits, llmFor } from '../llm/gateway';
import { giveConsent, withdrawConsent } from '../repo/consent';
import {
  effective,
  loadSettings,
  mergeInput,
  saveSettings,
  settingsView,
} from '../repo/llmSettings';
import { usageOf } from '../repo/usage';
import { meView } from './auth';

const Form = z.object({
  useOwn: z.boolean(),
  base: z.string().max(300),
  apiKey: z.string().max(500).optional(),
  textModel: z.string().max(120),
  visionModel: z.string().max(120),
  temperature: z.number().min(0).max(2),
  visionEnabled: z.boolean(),
});

/** 一行测试结果：连上了 · 模型 · 毫秒 / 失败原因 */
async function probe(c: LlmClient | null, label: string, now: () => number) {
  if (!c)
    return { ok: false, line: `${label}：没配视觉模型（或关了视觉校验），证据按未校验照收。` };
  const t0 = now();
  const r = await c.ping();
  if (!r.ok) return { ok: false, line: failureText(r) };
  return { ok: true, line: `连上了 · ${r.model ?? c.config.model} · ${Math.max(0, now() - t0)}ms` };
}

export const llmRoutes = new Hono<AppEnv>()
  .get('/settings', (c) => {
    const s = loadSettings(c.var.deps.dbh.db, me(c).id);
    return c.json({ ok: true, settings: settingsView(s, c.var.deps.config) });
  })
  .put('/settings', async (c) => {
    const u = me(c);
    const f = await body(c, Form);
    const { dbh, config } = c.var.deps;
    const next = mergeInput(loadSettings(dbh.db, u.id), f, config.encryptionKey);
    saveSettings(dbh.db, u.id, next);
    return c.json({ ok: true, settings: settingsView(next, config) });
  })
  /** 测试连接：可带一份还没保存的表单（Key 留空 = 用已存的） */
  .post('/test', async (c) => {
    const u = me(c);
    const deps = c.var.deps;
    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      raw = {};
    }
    const form = Form.safeParse(raw);
    const stored = loadSettings(deps.dbh.db, u.id);
    const s = form.success ? mergeInput(stored, form.data, deps.config.encryptionKey) : stored;
    const llm = llmFor(deps, u, { ...s, visionEnabled: true });
    const e = effective(s, deps.config);
    const [text, vision] = await Promise.all([
      probe(llm.text, '文本', () => Date.now()),
      probe(llm.vision, '视觉', () => Date.now()),
    ]);
    return c.json({ ok: true, mode: e.mode, text, vision });
  })
  .get('/usage', (c) => {
    const u = me(c);
    const deps = c.var.deps;
    const day = dayKey(deps.now(), u.tz);
    const mode = effective(loadSettings(deps.dbh.db, u.id), deps.config).mode;
    return c.json({
      ok: true,
      day,
      used: usageOf(deps.dbh.db, u.id, day),
      limits: dailyLimits(deps, u, mode),
    });
  });

export const consentRoutes = new Hono<AppEnv>()
  .post('/', (c) => {
    const u = me(c);
    giveConsent(c.var.deps.dbh.db, u.id, c.var.deps.now());
    return c.json({ ok: true, me: meView(c, u) });
  })
  .delete('/', (c) => {
    const u = me(c);
    withdrawConsent(c.var.deps.dbh.db, u.id);
    return c.json({ ok: true, me: meView(c, u) });
  });
