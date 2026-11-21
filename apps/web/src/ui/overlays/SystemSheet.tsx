/**
 * 系统设置抽屉（参考稿 #sheet）：音效开关 + 音量、证据视觉校验、模型设置、告知与同意、
 * 导出 / 导入存档、添加到主屏幕、重置存档。
 */
import { useRef } from 'react';
import { sfx } from '../../audio/sfx';
import { exportSave, importSave, resetAll } from '../../store/actions/data';
import { setLlmSettings, setPrefs, useServices } from '../../store/services';
import { setUi, toast, useUi } from '../../store/uiStore';
import { Tap } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

export function SystemSheet() {
  const open = useUi((s) => s.sheet === 'system');
  const prefs = useServices((s) => s.prefs);
  const llm = useServices((s) => s.llm);
  const file = useRef<HTMLInputElement>(null);
  const close = () => setUi({ sheet: null });
  const configured = !!(llm.base && llm.apiKey && llm.textModel);
  return (
    <Sheet open={open} onClose={close} title="系统设置">
      <div className="sheet-scroll">
        <Tap
          className="srow"
          onClick={() => {
            void setPrefs({ muted: !prefs.muted });
            if (prefs.muted) sfx.play('success');
            toast(prefs.muted ? '音效已开启。' : '音效已关闭。她的毒舌不受影响。');
          }}
        >
          <span>
            音效<small>按下、结算、暴击、升级……关键提示都有画面反馈</small>
          </span>
          <i className={`sw ${prefs.muted ? '' : 'on'}`} />
        </Tap>
        <div className="srow vol">
          <span>
            音量<small>{Math.round(prefs.volume * 100)}%</small>
          </span>
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={prefs.volume}
            disabled={prefs.muted}
            aria-label="音量"
            onChange={(e) => void setPrefs({ volume: Number(e.currentTarget.value) })}
            onPointerUp={() => sfx.play('coin')}
          />
        </div>
        <Tap
          className="srow"
          onClick={() => {
            void setLlmSettings({ ...llm, visionEnabled: !llm.visionEnabled });
            toast(
              llm.visionEnabled ? '证据视觉校验已关：照片一律按未校验收下。' : '证据视觉校验已开。',
            );
          }}
        >
          <span>
            证据视觉校验<small>照片发给视觉模型核对；关掉就一律按未校验收下</small>
          </span>
          <i className={`sw ${llm.visionEnabled ? 'on' : ''}`} />
        </Tap>
        <Tap className="srow" onClick={() => setUi({ sheet: 'llm' })}>
          <span>
            模型设置
            <small>
              {configured ? `${llm.textModel} · 已配置` : '还没配：拆解、聊天、校验都用不了'}
            </small>
          </span>
          <span>›</span>
        </Tap>
        <Tap className="srow" onClick={() => setUi({ sheet: 'notice' })}>
          <span>
            告知与同意<small>哪些内容会发给模型服务商</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap className="srow" onClick={() => void exportSave()}>
          <span>
            导出存档<small>存档、聊天、流水、记忆、照片打包成一个 JSON 文件（不含 Key）</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap className="srow" onClick={() => file.current?.click()}>
          <span>
            导入存档<small>用导出的文件整体覆盖；导入前自动备份当前数据</small>
          </span>
          <span>›</span>
        </Tap>
        <input
          ref={file}
          type="file"
          accept="application/json,.json"
          hidden
          onChange={(e) => {
            const f = e.currentTarget.files?.[0];
            e.currentTarget.value = '';
            if (f) {
              close();
              void importSave(f);
            }
          }}
        />
        <Tap className="srow" onClick={() => setUi({ sheet: 'install' })}>
          <span>
            添加到主屏幕<small>全屏运行，也能减少浏览器清掉数据的可能</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap
          className="srow danger"
          onClick={() => {
            close();
            void resetAll();
          }}
        >
          <span>
            重置存档<small>一切从「绑定系统」重新开始</small>
          </span>
          <span>›</span>
        </Tap>
      </div>
    </Sheet>
  );
}
