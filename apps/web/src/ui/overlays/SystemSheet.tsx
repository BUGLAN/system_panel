/**
 * 系统设置抽屉（参考稿 #sheet）：账号、证据视觉校验、模型设置、告知与同意、
 * 导出 / 导入存档、添加到主屏幕、重置存档、退出登录。
 */
import { useEffect, useRef } from 'react';
import { exportSave, importSave, resetAll } from '../../store/actions/data';
import { logout } from '../../store/actions/auth';
import { useSync } from '../../store/game';
import { formOf, loadLlmSettings, saveLlmSettings, useServices } from '../../store/services';
import { setUi, toast, useUi } from '../../store/uiStore';
import { Tap } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

export function SystemSheet() {
  const open = useUi((s) => s.sheet === 'system');
  const llm = useServices((s) => s.llm);
  const me = useSync((s) => s.me);
  const online = useSync((s) => s.online);
  const file = useRef<HTMLInputElement>(null);
  const close = () => setUi({ sheet: null });
  useEffect(() => {
    if (open) void loadLlmSettings();
  }, [open]);
  const configured = llm
    ? llm.useOwn
      ? !!(llm.base && llm.hasOwnKey && llm.textModel)
      : llm.serverDefault.text
    : false;
  /** 写操作要联网：断网时点了只提示（在点击时判断，不在渲染时） */
  const netOk = (): boolean => {
    if (online) return true;
    toast('需要联网。连上网再试。', 'err');
    return false;
  };
  return (
    <Sheet open={open} onClose={close} title="系统设置">
      <div className="sheet-scroll">
        <Tap className="srow" onClick={() => netOk() && setUi({ sheet: 'account' })}>
          <span>
            账号<small>{me ? `${me.username} · 时区 ${me.tz} · 改密码` : '没登录'}</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap
          className="srow"
          onClick={() => {
            if (!netOk() || !llm) return;
            void saveLlmSettings({ ...formOf(llm), visionEnabled: !llm.visionEnabled }).then(
              () =>
                toast(
                  llm.visionEnabled
                    ? '证据视觉校验已关：照片一律按未校验收下。'
                    : '证据视觉校验已开。',
                ),
              (e: unknown) => toast(e instanceof Error ? e.message : '没改成。', 'err'),
            );
          }}
        >
          <span>
            证据视觉校验<small>照片发给视觉模型核对；关掉就一律按未校验收下</small>
          </span>
          <i className={`sw ${llm?.visionEnabled === false ? '' : 'on'}`} />
        </Tap>
        <Tap className="srow" onClick={() => netOk() && setUi({ sheet: 'llm' })}>
          <span>
            模型设置
            <small>
              {!llm
                ? '联网后可查看'
                : configured
                  ? llm.useOwn
                    ? `${llm.textModel} · 用我自己的`
                    : '用服务器默认'
                  : '还没配：拆解、校验都用不了'}
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
        <Tap className="srow" onClick={() => netOk() && void exportSave()}>
          <span>
            导出存档
            <small>服务器上的存档、流水、照片打包成一个 JSON 文件（不含 Key）</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap className="srow" onClick={() => netOk() && file.current?.click()}>
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
            添加到主屏幕<small>全屏运行，像 App 一样打开</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap
          className="srow danger"
          onClick={() => {
            if (!netOk()) return;
            close();
            void resetAll();
          }}
        >
          <span>
            重置存档<small>一切从「绑定系统」重新开始（账号保留）</small>
          </span>
          <span>›</span>
        </Tap>
        <Tap
          className="srow"
          onClick={() => {
            close();
            void logout();
          }}
        >
          <span>
            退出登录<small>清掉这台设备上的缓存；数据还在服务器上</small>
          </span>
          <span>›</span>
        </Tap>
      </div>
    </Sheet>
  );
}
