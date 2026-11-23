/**
 * 存档的整体操作：重置、导出、导入（数据在服务器上；导出包与旧版格式一致，可以互相导）。
 */
import { bundleFileName } from '@host/core/save/bundle';
import { api } from '../api';
import { now, resetHistoryCache, syncStore } from '../game';
import { confirmBox, setUi, toast } from '../uiStore';
import { resetBind } from './bind';
import { go } from './nav';
import { cancelPlanJob } from './planJob';

export async function resetAll(): Promise<void> {
  const ok = await confirmBox({
    title: '重置存档？',
    body: '等级、连胜、主线、流水、证据照片——\n[她记住的你，全部清空]。\n账号、模型设置和告知同意会保留。',
    yes: '重置',
    no: '算了',
    danger: true,
  });
  if (!ok) return;
  try {
    await api('POST', '/api/data/reset', { baseVersion: syncStore.getState().version });
  } catch (e) {
    toast(e instanceof Error ? e.message : '重置没成功。', 'err');
    return;
  }
  cancelPlanJob();
  setUi({ sheet: null, show: null, briefing: null });
  resetHistoryCache();
  resetBind();
  await go('onboard', { noHist: true });
  toast('存档已清空。她假装不认识你了。');
}

export async function exportSave(): Promise<void> {
  try {
    const res = await fetch('/api/data/export', { credentials: 'same-origin' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = bundleFileName(now());
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
    toast('存档已导出。这是服务器上数据的一份离线备份（不含 Key）。', 'ok');
  } catch (e) {
    console.error(e);
    toast('导出失败了。联网后再试一次？', 'err');
  }
}

export async function importSave(file: File): Promise<void> {
  let text: string;
  try {
    text = await file.text();
  } catch {
    toast('文件读不出来。', 'err');
    return;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    toast('文件不是有效的 JSON，可能不完整或被改坏了。', 'err');
    return;
  }
  const ok = await confirmBox({
    title: '导入存档？',
    body: '会用这份文件整体覆盖服务器上你的存档、流水和照片。\n导入前会先自动留一份当前数据的备份。\n账号和模型设置不受影响。',
    yes: '导入',
    no: '算了',
    danger: true,
  });
  if (!ok) return;
  try {
    await api('POST', '/api/data/import', {
      baseVersion: syncStore.getState().version,
      bundle: parsed,
    });
  } catch (e) {
    toast(e instanceof Error ? e.message : '导入失败了。', 'err');
    return;
  }
  toast('导入成功，马上重新载入。', 'ok');
  setTimeout(() => location.reload(), 700);
}
