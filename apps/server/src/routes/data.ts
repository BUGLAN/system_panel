/**
 * 导出 / 导入 / 重置（docs/05 第 3.5 节）。导入、重置是整档覆盖：要求 baseVersion 与当前严格相等。
 */
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { bundleFileName, checkBundle } from '@host/core/save/bundle';
import { me, type AppEnv, type Ctx } from '../http/context';
import { ApiError, badRequest } from '../http/errors';
import { stale } from '../http/intent';
import { runFlow } from '../flow/runner';
import { checkBundlePhotos, exportBundle, importBundle, wipeUserData } from '../repo/bundle';
import { saveVersion } from '../repo/saves';

export const IMPORT_MAX_BYTES = 50 * 1024 * 1024;

function baseVersionOf(raw: unknown): number {
  const v =
    raw && typeof raw === 'object' ? (raw as Record<string, unknown>)['baseVersion'] : undefined;
  if (typeof v !== 'number' || !Number.isInteger(v)) throw badRequest('参数不对（baseVersion）。');
  return v;
}

async function overwrite(c: Ctx, baseVersion: number, work: () => Promise<number> | number) {
  const u = me(c);
  const deps = c.var.deps;
  await deps.locks.run(u.id, async () => {
    if (saveVersion(deps.dbh.db, u.id) !== baseVersion)
      throw stale('另一台设备刚改过存档。刷新后再试一次。');
    deps.jobs.cancel(u.id);
    const v = await work();
    deps.bus.publish(u.id, { type: 'state', version: v });
  });
  const r = await runFlow(deps, u, () => undefined);
  return c.json({ ok: true, state: r.state, events: r.events });
}

export const dataRoutes = new Hono<AppEnv>()
  .get('/export', async (c) => {
    const u = me(c);
    const deps = c.var.deps;
    const now = deps.now();
    const b = await exportBundle(deps.dbh.db, deps.config.dataDir, u.id, now);
    const name = encodeURIComponent(bundleFileName(now));
    return c.body(JSON.stringify(b), 200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': `attachment; filename*=UTF-8''${name}`,
    });
  })
  .post(
    '/import',
    bodyLimit({
      maxSize: IMPORT_MAX_BYTES,
      onError: () => {
        throw new ApiError(413, 'too_large', '存档文件太大了（超过 50MB）。');
      },
    }),
    async (c) => {
      const u = me(c);
      const deps = c.var.deps;
      let raw: unknown;
      try {
        raw = await c.req.json();
      } catch {
        throw badRequest('这不是一个存档文件（JSON 读不出来）。');
      }
      const base = baseVersionOf(raw);
      const bundle = (raw as Record<string, unknown>)['bundle'];
      const check = checkBundle(bundle, deps.now());
      if (!check.ok) throw new ApiError(400, 'bad_bundle', check.reason);
      const photo = checkBundlePhotos(check.value);
      if (photo) throw new ApiError(400, 'bad_bundle', `存档内容损坏：${photo}`);
      return overwrite(c, base, () =>
        importBundle(deps.dbh.db, deps.config.dataDir, u.id, check.value, deps.now()),
      );
    },
  )
  .post('/reset', async (c) => {
    const u = me(c);
    const deps = c.var.deps;
    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      raw = null;
    }
    const base = baseVersionOf(raw);
    return overwrite(c, base, () =>
      wipeUserData(deps.dbh.db, deps.config.dataDir, u.id, deps.now()),
    );
  });
