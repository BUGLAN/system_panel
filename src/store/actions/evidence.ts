/**
 * 证据：选图后马上入槽（压缩后存 IndexedDB），校验在后台跑（C7）。
 *  - 判定不符：图撤出槽，她说明原因，槽下保留「上一张被拒：{原因}」直到下一张入槽（E2.1）
 *  - 交单时还有在途校验：最多等 20 秒，等不到的按未校验算
 *  - 交单那一刻证据封存，之后迟到的结论一律丢弃（由 QuestFlow.applyVerdict 保证）
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { SUBMIT_WAIT_MS, unverified, verifyEvidence } from '../../agent/vision';
import { sfx } from '../../audio/sfx';
import { appDb } from '../db';
import { game, now, runFlow } from '../game';
import { visionClient } from '../services';
import { putEvidence, getEvidence } from '../sideRepos';
import { sayWatch, toast } from '../uiStore';
import { blobToDataUrl, compressImage, demoShot } from '../media';
import { MAX_EVIDENCE } from '../../core/flow/questFlow';

export interface EvidenceUiState {
  /** 正在后台校验的证据 id */
  checking: string[];
  /** 选图 / 压缩中（防连点） */
  picking: boolean;
  /** 上一张被拒的原因 */
  rejectNote: string;
  /** 交单时在等校验 */
  waiting: boolean;
}

export const evidenceStore = createStore<EvidenceUiState>()(() => ({
  checking: [],
  picking: false,
  rejectNote: '',
  waiting: false,
}));
export const useEvidence = <T>(sel: (s: EvidenceUiState) => T) => useStore(evidenceStore, sel);

const inflight = new Map<string, Promise<void>>();
const urls = new Map<string, string>();

/** 缩略图 URL（按 id 缓存 object URL） */
export async function evidenceUrl(id: string): Promise<string | null> {
  const hit = urls.get(id);
  if (hit) return hit;
  const b = await getEvidence(appDb(), id);
  if (!b) return null;
  const u = URL.createObjectURL(b);
  urls.set(id, u);
  return u;
}

let seq = 0;
const newId = (serial: number) => `q${serial}-${now().toString(36)}-${seq++}`;

/** 换一单时清掉拒收留痕 */
export function resetEvidenceUi(): void {
  evidenceStore.setState({ checking: [], picking: false, rejectNote: '', waiting: false });
}

async function admit(blob: Blob, verify: boolean): Promise<void> {
  const a = game().active;
  if (!a || a.sealed) return;
  if (a.evidence.length >= MAX_EVIDENCE) {
    toast(`最多 ${MAX_EVIDENCE} 张。先撤一张。`, 'err');
    return;
  }
  const id = newId(a.task.serial);
  await putEvidence(appDb(), id, blob, now());
  urls.set(id, URL.createObjectURL(blob));
  const ok = runFlow((f) =>
    f.addEvidence({ id, status: 'unverified', note: verify ? '' : '演示截图', takenAt: now() }),
  );
  if (!ok) return;
  evidenceStore.setState({ rejectNote: '' });
  sfx.play('success');
  if (!verify) {
    sayWatch('收下了。她会盯着看。');
    return;
  }
  const client = visionClient();
  if (!client) {
    sayWatch('收下了。没开视觉校验，按[未校验]算。');
    return;
  }
  sayWatch('校验中……她在看。');
  evidenceStore.setState((s) => ({ checking: [...s.checking, id] }));
  const quest = a.task;
  const job = (async () => {
    try {
      const v = await verifyEvidence({ client, quest, dataUrl: await blobToDataUrl(blob) }).catch(
        () => unverified('校验失败'),
      );
      const res = runFlow((f) => f.applyVerdict(id, v.status, v.note));
      if (res === 'rejected') {
        sfx.play('error');
        evidenceStore.setState({ rejectNote: v.note });
        toast(`这张不收：${v.note}。重拍一张。`, 'err');
        sayWatch(`[不符]：${v.note}。重传。`);
      } else if (res === 'kept') {
        sayWatch(
          v.status === 'verified'
            ? `核过了：${v.note || '可信'}。`
            : `先收下：${v.note || '没核上'}。`,
        );
      }
    } finally {
      evidenceStore.setState((s) => ({ checking: s.checking.filter((x) => x !== id) }));
      inflight.delete(id);
    }
  })();
  inflight.set(id, job);
}

/** 选好图：压缩 → 入槽 → 后台校验 */
export async function addEvidenceFile(file: File): Promise<void> {
  if (evidenceStore.getState().picking) return;
  if (file.type && !file.type.startsWith('image/')) {
    sfx.play('error');
    toast('这不是图片。她不收奇怪的东西。', 'err');
    return;
  }
  evidenceStore.setState({ picking: true });
  try {
    const blob = await compressImage(file);
    await admit(blob, true);
  } catch (e) {
    console.error(e);
    sfx.play('error');
    toast('图片读不出来。换一张？', 'err');
  } finally {
    evidenceStore.setState({ picking: false });
  }
}

/** 开发环境的演示截图：入槽后不送校验，按未校验照收 */
export async function addDemoEvidence(): Promise<void> {
  const a = game().active;
  if (!a) return;
  await admit(await demoShot(a.task.name, a.task.proof), false);
}

export function removeEvidence(id: string): void {
  if (runFlow((f) => f.removeEvidence(id))) sfx.play('soft');
}

/** 交单前：等本单在途的校验，最多 20 秒 */
export async function waitForChecks(ids: string[]): Promise<void> {
  const jobs = ids.map((id) => inflight.get(id)).filter((p): p is Promise<void> => !!p);
  if (!jobs.length) return;
  evidenceStore.setState({ waiting: true });
  try {
    await Promise.race([Promise.all(jobs), new Promise((r) => setTimeout(r, SUBMIT_WAIT_MS))]);
  } finally {
    evidenceStore.setState({ waiting: false });
  }
}
