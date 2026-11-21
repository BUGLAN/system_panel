/**
 * 证据（docs/05 第 3.3 节）：
 *  - 上传：前端已压成 JPEG（长边 ≤1024）；服务端再验大小（≤2MB）和文件头，入槽（未校验）后后台视觉校验
 *  - 结论经 SSE 推 verdict：不符撤槽 + 原因；其余换状态照收；已交单（封存）的迟到结论丢弃
 *  - 读图：只有主人能读（别人 404），不走公开静态目录
 */
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { MAX_EVIDENCE } from '@host/core/flow/questFlow';
import type { Quest } from '@host/core/model/quest';
import type { VerdictEvent } from '@host/core/api/types';
import { unverified, verifyEvidence } from '../agent/vision';
import type { AuthUser } from '../auth/accounts';
import {
  EVIDENCE_MAX_BYTES,
  evidenceRow,
  putEvidenceFile,
  readEvidenceFile,
  setEvidenceVerdict,
  sniffImage,
} from '../evidence/store';
import { me, type AppEnv, type Deps } from '../http/context';
import { ApiError, badRequest, notFound } from '../http/errors';
import { intent, rejected, stale } from '../http/intent';
import { runFlow } from '../flow/runner';
import { llmFor } from '../llm/gateway';
import { errInfo, log } from '../log';

export type { VerdictEvent };

/** 后台校验一张：结论在锁内落到槽上，推给前端 */
function startCheck(
  deps: Deps,
  user: AuthUser,
  id: string,
  quest: Quest,
  bytes: Uint8Array,
  mime: string,
): boolean {
  const llm = llmFor(deps, user);
  if (!llm.vision) return false;
  const dataUrl = `data:${mime};base64,${Buffer.from(bytes).toString('base64')}`;
  const job = (async () => {
    const v = await verifyEvidence({ client: llm.vision, quest, dataUrl }).catch(() =>
      unverified('校验失败'),
    );
    const r = await runFlow(deps, user, (f) => f.applyVerdict(id, v.status, v.note), {
      touch: false,
    });
    if (r.value !== 'gone') setEvidenceVerdict(deps.dbh.db, user.id, id, v.status, v.note);
    const ev: VerdictEvent = {
      id,
      serial: quest.serial,
      result: r.value,
      status: v.status,
      note: v.note,
    };
    deps.bus.publish(user.id, { type: 'verdict', verdict: ev });
  })().catch((e: unknown) => log.error('视觉校验收尾失败', errInfo(e)));
  deps.checks.track(user.id, id, job);
  return true;
}

export const evidenceRoutes = new Hono<AppEnv>()
  .post(
    '/',
    bodyLimit({
      maxSize: EVIDENCE_MAX_BYTES + 64 * 1024,
      onError: () => {
        throw new ApiError(413, 'too_large', '照片太大了（超过 2MB）。');
      },
    }),
    async (c) => {
      const u = me(c);
      const deps = c.var.deps;
      let form: Record<string, unknown>;
      try {
        form = await c.req.parseBody();
      } catch {
        throw badRequest('上传的不是表单。');
      }
      const file = form['file'];
      const serial = Number(form['serial']);
      const demo = form['demo'] === '1' && deps.config.env !== 'production';
      if (!(file instanceof File)) throw badRequest('没有收到照片。');
      if (!Number.isInteger(serial)) throw badRequest('参数不对（serial）。');
      if (file.size > EVIDENCE_MAX_BYTES)
        throw new ApiError(413, 'too_large', '照片太大了（超过 2MB）。');
      const bytes = new Uint8Array(await file.arrayBuffer());
      const mime = sniffImage(bytes);
      if (mime !== 'image/jpeg') throw rejected('这不是图片。她不收奇怪的东西。');

      return intent(c, async () => {
        const now = deps.now();
        const row = putEvidenceFile(deps.dbh.db, deps.config.dataDir, {
          userId: u.id,
          bytes,
          mime,
          takenAt: now,
          serial,
        });
        let quest: Quest | null = null;
        const r = await runFlow(deps, u, (f) => {
          const a = f.active;
          if (!a || a.task.serial !== serial || a.sealed) throw stale('这一单已经不在执行了。');
          if (a.evidence.length >= MAX_EVIDENCE)
            throw rejected(`最多 ${MAX_EVIDENCE} 张。先撤一张。`);
          f.addEvidence({
            id: row.id,
            status: 'unverified',
            note: demo ? '演示截图' : '',
            takenAt: now,
          });
          quest = a.task;
        });
        const checking = !demo && quest !== null && startCheck(deps, u, row.id, quest, bytes, mime);
        return { state: r.state, events: r.events, shotId: row.id, checking };
      });
    },
  )
  .get('/:id', (c) => {
    const u = me(c);
    const deps = c.var.deps;
    const row = evidenceRow(deps.dbh.db, u.id, c.req.param('id'));
    if (!row) throw notFound();
    const buf = readEvidenceFile(deps.config.dataDir, row.file);
    if (!buf) throw notFound();
    return c.body(new Uint8Array(buf), 200, {
      'Content-Type': row.mime,
      'Cache-Control': 'private, max-age=86400',
      'X-Content-Type-Options': 'nosniff',
    });
  })
  .delete('/:id', (c) => {
    const id = c.req.param('id');
    return intent(c, async () => {
      const r = await runFlow(c.var.deps, me(c), (f) => {
        if (!f.removeEvidence(id)) throw stale('这张已经不在槽里了。');
      });
      return { state: r.state, events: r.events };
    });
  });
