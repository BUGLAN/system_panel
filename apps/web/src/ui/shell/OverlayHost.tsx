/** 叠层：底板 / 面板 / 加载卡 / 演出（结算、失败、升级）/ 简报 / 聊天 */
import { AccountSheet } from '../overlays/AccountSheet';
import { LlmSettingsPanel } from '../overlays/LlmSettings';
import { OfflineBar } from '../overlays/OfflineBar';
import { NoticeSheet } from '../overlays/NoticeSheet';
import { PlanLoading } from '../overlays/PlanLoading';
import { SystemSheet } from '../overlays/SystemSheet';
import { InstallSheet } from '../overlays/InstallSheet';
import { StageOverlays } from '../overlays/StageOverlays';
import { GoalSwap } from '../overlays/GoalSwap';

export function OverlayHost() {
  return (
    <>
      <StageOverlays />
      <OfflineBar />
      <SystemSheet />
      <AccountSheet />
      <NoticeSheet />
      <InstallSheet />
      <GoalSwap />
      <LlmSettingsPanel />
      <PlanLoading />
    </>
  );
}
