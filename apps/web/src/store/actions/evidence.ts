/**
 * 证据：选图 → 本机压缩（长边 ≤1024、JPEG）→ 上传，服务端马上入槽（未校验）并在后台校验（C7）。
 *  - 结论经 SSE 推回：判定不符 → 图撤出槽，她说明原因，槽下保留「上一张被拒：{原因}」直到下一张入槽（E2.1）
 *  - 交单时还有在途校验：服务端最多等 20 秒，这期间主键显示「她在验证据…」
 *  - 交单那一刻证据封存，之后迟到的结论一律丢弃（服务端保证，推来的是 gone）
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import type { VerdictEvent } from '@host/core/api/types';
import { MAX_EVIDENCE } from '@host/core/flow/questFlow';
import { sfx } from '../../audio/sfx';
import { game, intent } from '../game';
import { onStream } from '../stream';
import { sayWatch, toast } from '../uiStore';
import { compressImage, demoShot } from '../media';

export interface EvidenceUiState {
  /** 正在后台校验的证据 id */
  checking: string[];
  /** 选图 / 压缩 / 上传中（防连点） */
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

/** 缩略图地址：只有登录的主人能读（会话 Cookie） */
export async function evidenceUrl(id: string): Promise<string | null> {
  return `/api/evidence/${encodeURIComponent(id)}`;
}

/** 换一单时清掉拒收留痕 */
export function resetEvidenceUi(): void {
  evidenceStore.setState({ checking: [], picking: false, rejectNote: '', waiting: false });
}

const doneChecking = (id: string) =>
  evidenceStore.setState((s) => ({ checking: s.checking.filter((x) => x !== id) }));

/** 后台校验的结论（SSE） */
function onVerdict(v: VerdictEvent): void {
  if (!evidenceStore.getState().checking.includes(v.id)) return;
  doneChecking(v.id);
  if (v.result === 'rejected') {
    sfx.play('error');
    evidenceStore.setState({ rejectNote: v.note });
    toast(`这张不收：${v.note}。重拍一张。`, 'err');
    sayWatch(`[不符]：${v.note}。重传。`);
  } else if (v.result === 'kept') {
    sayWatch(
      v.status === 'verified' ? `核过了：${v.note || '可信'}。` : `先收下：${v.note || '没核上'}。`,
    );
  }
}
onStream({ verdict: onVerdict });

async function upload(blob: Blob, demo: boolean): Promise<void> {
  const a = game().active;
  if (!a || a.sealed) return;
  if (a.evidence.length >= MAX_EVIDENCE) {
    toast(`最多 ${MAX_EVIDENCE} 张。先撤一张。`, 'err');
    return;
  }
  const fd = new FormData();
  fd.set('file', blob, 'evidence.jpg');
  fd.set('serial', String(a.task.serial));
  if (demo) fd.set('demo', '1');
  const r = await intent<{ shotId: string; checking: boolean }>('/api/evidence', fd);
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    return;
  }
  evidenceStore.setState({ rejectNote: '' });
  sfx.play('success');
  if (demo) {
    sayWatch('收下了。她会盯着看。');
    return;
  }
  if (!r.r.checking) {
    sayWatch('收下了。没开视觉校验，按[未校验]算。');
    return;
  }
  sayWatch('校验中……她在看。');
  const id = r.r.shotId;
  evidenceStore.setState((s) => ({ checking: [...s.checking, id] }));
  // SSE 断了也不让角标一直闪：40 秒后（校验 30 秒超时）按状态里的结论收尾
  setTimeout(() => doneChecking(id), 40_000);
}

/** 选好图：压缩 → 上传 → 后台校验 */
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
    await upload(blob, false);
  } catch (e) {
    console.error(e);
    sfx.play('error');
    toast('图片读不出来。换一张？', 'err');
  } finally {
    evidenceStore.setState({ picking: false });
  }
}

/** 开发环境的演示截图：入槽后不送校验，按未校验照收（服务端只在非生产环境认这个标记） */
export async function addDemoEvidence(): Promise<void> {
  const a = game().active;
  if (!a) return;
  await upload(await demoShot(a.task.name, a.task.proof), true);
}

export async function removeEvidence(id: string): Promise<void> {
  const r = await intent(`/api/evidence/${encodeURIComponent(id)}`, undefined, 'DELETE');
  if (r.ok) sfx.play('soft');
  else toast(r.err.message, 'err');
}
