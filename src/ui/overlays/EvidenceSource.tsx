/**
 * 证据来源底板（B4）：【拍照】（推荐）/【相册】；开发环境另有「用演示截图」。
 * 拍照走 <input capture="environment">，相册是普通的图片选择。
 */
import { useRef } from 'react';
import { addDemoEvidence, addEvidenceFile } from '../../store/actions/evidence';
import { setUi, useUi } from '../../store/uiStore';
import { Tap } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

export function EvidenceSource() {
  const open = useUi((s) => s.sheet === 'evidence');
  const cam = useRef<HTMLInputElement>(null);
  const lib = useRef<HTMLInputElement>(null);
  const close = () => setUi({ sheet: null });
  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    close();
    if (f) void addEvidenceFile(f);
  };
  return (
    <>
      <input
        ref={cam}
        type="file"
        accept="image/*"
        capture="environment"
        hidden
        onChange={onPick}
      />
      <input ref={lib} type="file" accept="image/*" hidden onChange={onPick} />
      <Sheet open={open} onClose={close} title="上传快照记录">
        <Tap className="srow" onClick={() => cam.current?.click()}>
          <span>
            拍照 <em className="rec-tag">推荐</em>
            <small>现场拍，最像真的</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap className="srow" onClick={() => lib.current?.click()}>
          <span>
            相册<small>照片或 App 截图</small>
          </span>
          <span>›</span>
        </Tap>
        {import.meta.env.DEV && (
          <Tap
            className="srow"
            onClick={() => {
              close();
              void addDemoEvidence();
            }}
          >
            <span>
              ⚡ 用演示截图<small>仅开发环境：不送校验，按未校验收下</small>
            </span>
            <span>›</span>
          </Tap>
        )}
        <p className="sheet-note">
          照片会压缩到长边 1024 像素再存、再发给视觉模型。相机打不开就从相册选。
        </p>
      </Sheet>
    </>
  );
}
