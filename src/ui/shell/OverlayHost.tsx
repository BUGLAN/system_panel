/** 叠层：底板 / 面板 / 加载卡 / 演出（结算、失败、升级）/ 简报 / 聊天 */
import { LlmSettingsPanel } from '../overlays/LlmSettings';
import { NoticeSheet } from '../overlays/NoticeSheet';
import { PlanLoading } from '../overlays/PlanLoading';
import { SystemSheet } from '../overlays/SystemSheet';
import { InstallSheet } from '../overlays/InstallSheet';
import { StageOverlays } from '../overlays/StageOverlays';

export function OverlayHost() {
  return (
    <>
      <StageOverlays />
      <SystemSheet />
      <NoticeSheet />
      <InstallSheet />
      <LlmSettingsPanel />
      <PlanLoading />
    </>
  );
}
