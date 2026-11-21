/**
 * 存档的整体操作：重置、导出、导入（PWA 的数据只在这个浏览器里，导出是唯一的备份手段）。
 */
import { bundleFileName } from '@host/core/save/bundle';
import { freshSave } from '@host/core/save/saveData';
import { dataRepo } from '../app';
import { game, resetHistoryCache } from '../game';
import { gameStore } from '../gameStore';
import { confirmBox, setUi, toast } from '../uiStore';
import { resetBind } from './bind';
import { clearChatState } from './chat';
import { go } from './nav';
import { cancelPlanJob } from './planJob';

export async function resetAll(): Promise<void> {
  const ok = await confirmBox({
    title: '重置存档？',
    body: '等级、晶核、主线、名牒、聊天记录、证据照片——\n[她记住的你，全部清空]。\n模型设置和告知同意会保留。',
    yes: '重置',
    no: '算了',
    danger: true,
  });
  if (!ok) return;
  cancelPlanJob();
  setUi({ sheet: null, show: null, briefing: null, chatOpen: false });
  await dataRepo.wipe();
  resetHistoryCache();
  clearChatState();
  gameStore.getState().hydrate(freshSave(Date.now()), 'none');
  resetBind();
  await go('onboard', { noHist: true });
  toast('存档已清空。她假装不认识你了。');
}

export async function exportSave(): Promise<void> {
  try {
    const text = await dataRepo.exportText(game());
    const blob = new Blob([text], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = bundleFileName(Date.now());
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
    toast('存档已导出。收好这份文件，换设备或清了浏览器数据就靠它。', 'ok');
  } catch (e) {
    console.error(e);
    toast('导出失败了。再试一次？', 'err');
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
    body: '会用这份文件整体覆盖当前的存档、聊天、流水、记忆和照片。\n导入前会先自动留一份当前数据的备份。\n模型设置不受影响。',
    yes: '导入',
    no: '算了',
    danger: true,
  });
  if (!ok) return;
  const res = await dataRepo.importBundle(parsed, game());
  if (!res.ok) {
    toast(res.reason, 'err');
    return;
  }
  toast('导入成功，马上重新载入。', 'ok');
  setTimeout(() => location.reload(), 700);
}
