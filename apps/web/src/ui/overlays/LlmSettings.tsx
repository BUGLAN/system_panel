/**
 * 模型设置（弹窗式面板，✕ 关闭）：用服务器默认 / 用我自己的 + 端点 / API Key / 文本模型 / 视觉模型 / 温度 +【测试连接】。
 * 模型都由服务器代为调用：Key 加密存在服务器上，永远不会再回到浏览器（这里只显示末 4 位）。
 * 失败原因分开报：没填 / 网络 / HTTP 4xx·5xx / 超时 / 额度。
 */
import { useEffect, useState } from 'react';
import type { LlmSettingsForm, LlmSettingsView, UsageView } from '@host/core/api/types';
import {
  formOf,
  hasConsent,
  llmUsage,
  loadLlmSettings,
  saveLlmSettings,
  testLlm,
  useServices,
} from '../../store/services';
import { setUi, toast, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Panel } from '../kit/Sheet';

const DEFAULT_TEMPERATURE = 0.8;

type Probe =
  | { state: 'idle' }
  | { state: 'run' }
  | { state: 'ok'; text: string }
  | { state: 'err'; text: string };

function Field({
  label,
  hint,
  value,
  onChange,
  type = 'text',
  placeholder,
}: {
  label: string;
  hint?: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  placeholder?: string;
}) {
  return (
    <label className="fld">
      <span className="fld-l">{label}</span>
      <input
        className="lim-input"
        type={type}
        value={value}
        placeholder={placeholder}
        autoComplete="off"
        autoCapitalize="off"
        spellCheck={false}
        onChange={(e) => onChange(e.currentTarget.value)}
      />
      {hint && <small className="fld-h">{hint}</small>}
    </label>
  );
}

function ProbeLine({ p, label }: { p: Probe; label: string }) {
  if (p.state === 'idle') return null;
  return (
    <div className={`probe ${p.state}`}>
      <b>{label}</b> {p.state === 'run' ? '测试中……' : p.text}
    </div>
  );
}

export function LlmSettingsPanel() {
  const open = useUi((s) => s.sheet === 'llm');
  return (
    <Panel
      open={open}
      onClose={() => setUi({ sheet: null })}
      eyebrow="SETTINGS · 模型设置"
      title="接上她的脑子"
    >
      {open && <LlmLoader />}
    </Panel>
  );
}

function LlmLoader() {
  const saved = useServices((s) => s.llm);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    void loadLlmSettings().then((s) => setFailed(!s));
  }, []);
  if (!saved) {
    return <p className="panel-note">{failed ? '需要联网才能看和改模型设置。' : '读取中……'}</p>;
  }
  return <LlmForm saved={saved} />;
}

function usageText(u: UsageView | null): string {
  if (!u) return '';
  if (!u.limits) return `今天已用：文本 ${u.used.text} 次 · 验图 ${u.used.vision} 次（不限额）`;
  return `今天已用：文本 ${u.used.text}/${u.limits.text} 次 · 验图 ${u.used.vision}/${u.limits.vision} 次`;
}

function LlmForm({ saved }: { saved: LlmSettingsView }) {
  const [d, setD] = useState<LlmSettingsForm>(formOf(saved));
  /** 新填的 Key（空 = 不改已存的） */
  const [key, setKey] = useState('');
  const [clearKey, setClearKey] = useState(false);
  const [showKey, setShowKey] = useState(false);
  const [pt, setPt] = useState<Probe>({ state: 'idle' });
  const [pv, setPv] = useState<Probe>({ state: 'idle' });
  const [usage, setUsage] = useState<UsageView | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    void llmUsage().then(setUsage, () => setUsage(null));
  }, []);
  const patch = (p: Partial<LlmSettingsForm>) => setD((x) => ({ ...x, ...p }));
  const form = (): LlmSettingsForm => ({
    ...d,
    base: d.base.trim(),
    textModel: d.textModel.trim(),
    visionModel: d.visionModel.trim(),
    ...(key.trim() ? { apiKey: key.trim() } : clearKey ? { apiKey: '' } : {}),
  });
  const save = async () => {
    setBusy(true);
    try {
      await saveLlmSettings(form());
      toast('模型设置已保存。Key 加密存在服务器上，不会再回到浏览器。', 'ok');
      setUi({ sheet: null });
    } catch (e) {
      toast(e instanceof Error ? e.message : '没保存成功。', 'err');
    } finally {
      setBusy(false);
    }
  };
  const test = async () => {
    setPt({ state: 'run' });
    setPv({ state: 'run' });
    try {
      const r = await testLlm(form());
      setPt({ state: r.text.ok ? 'ok' : 'err', text: r.text.line });
      setPv({ state: r.vision.ok ? 'ok' : 'err', text: r.vision.line });
      void llmUsage().then(setUsage, () => undefined);
    } catch (e) {
      const text = e instanceof Error ? e.message : '测不了。';
      setPt({ state: 'err', text });
      setPv({ state: 'idle' });
    }
  };
  const def = saved.serverDefault;
  return (
    <>
      <p className="panel-note">
        模型都由<b>服务器</b>
        代为调用，浏览器不直连服务商。可以用服务器默认配的那一套，也可以填你自己的 OpenAI
        兼容服务商（端点、Key、模型整套换成你的）。
      </p>
      <div className="seg-pick">
        <Tap className={`seg-opt ${d.useOwn ? '' : 'on'}`} onClick={() => patch({ useOwn: false })}>
          用服务器默认
          <small>
            {def.text ? (def.vision ? '文本 + 视觉已配' : '只配了文本') : '服务器还没配'}
          </small>
        </Tap>
        <Tap className={`seg-opt ${d.useOwn ? 'on' : ''}`} onClick={() => patch({ useOwn: true })}>
          用我自己的
          <small>{saved.hasOwnKey ? `已存 Key ${saved.keyHint}` : '还没填 Key'}</small>
        </Tap>
      </div>
      {d.useOwn && (
        <>
          <Field
            label="端点"
            value={d.base}
            onChange={(v) => patch({ base: v })}
            placeholder="https://api.example.com/v1"
            hint="一般以 /v1 结尾"
          />
          <label className="fld">
            <span className="fld-l">
              API Key
              <Tap className="link" quiet onClick={() => setShowKey((v) => !v)}>
                {showKey ? '隐藏' : '显示'}
              </Tap>
            </span>
            <input
              className="lim-input"
              type={showKey ? 'text' : 'password'}
              value={key}
              autoComplete="off"
              spellCheck={false}
              placeholder={
                saved.hasOwnKey && !clearKey ? `已保存 ${saved.keyHint}（留空 = 不改）` : 'sk-…'
              }
              onChange={(e) => {
                setKey(e.currentTarget.value);
                setClearKey(false);
              }}
            />
            <small className="fld-h">
              加密存在服务器上，只用来替你调用模型；导出存档不会带上它。
              {saved.hasOwnKey && (
                <Tap className="link" quiet onClick={() => (setKey(''), setClearKey(true))}>
                  {clearKey ? '保存后清掉' : '清掉已存的 Key'}
                </Tap>
              )}
            </small>
          </label>
          <Field
            label="文本模型"
            value={d.textModel}
            onChange={(v) => patch({ textModel: v })}
            placeholder="拆解用"
          />
          <Field
            label="视觉模型"
            value={d.visionModel}
            onChange={(v) => patch({ visionModel: v })}
            placeholder="证据校验用（要能看图）"
          />
        </>
      )}
      <label className="fld">
        <span className="fld-l">
          温度 <b className="fld-v">{d.temperature.toFixed(1)}</b>
        </span>
        <input
          type="range"
          min={0}
          max={2}
          step={0.1}
          value={d.temperature}
          onChange={(e) => patch({ temperature: Number(e.currentTarget.value) })}
        />
        <small className="fld-h">
          暂时没有功能用到（默认 {DEFAULT_TEMPERATURE}）；拆解、匹配、校验各自固定
        </small>
      </label>
      {usage && <small className="fld-h">{usageText(usage)}</small>}
      <ProbeLine p={pt} label="文本" />
      <ProbeLine p={pv} label="视觉" />
      {!hasConsent() && <div className="probe err">还没同意首启告知页，测试请求不会发出。</div>}
      <div className="panel-act">
        <Btn kind="ghost" sm disabled={pt.state === 'run'} onClick={() => void test()}>
          测试连接
        </Btn>
        <Btn kind="pri" sm disabled={busy} onClick={() => void save()}>
          保存
        </Btn>
      </div>
    </>
  );
}
