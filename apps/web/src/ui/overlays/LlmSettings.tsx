/**
 * 模型设置（弹窗式面板，✕ 关闭）：端点 / API Key / 文本模型 / 视觉模型 / 温度 +【测试连接】。
 * 失败原因分开报：没填 / 网络 / CORS 被拦 / HTTP 4xx·5xx / 超时。Key 只存在本机。
 */
import { useState } from 'react';
import { LlmClient, failureText } from '../../agent/llmClient';
import { DEFAULT_TEMPERATURE, type LlmSettings as Settings } from '../../agent/settings';
import { sfx } from '../../audio/sfx';
import { hasConsent, setLlmSettings, useServices } from '../../store/services';
import { setUi, toast, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Panel } from '../kit/Sheet';

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

async function probe(s: Settings, model: string): Promise<Probe> {
  if (!model) return { state: 'err', text: '没填模型名。' };
  const c = new LlmClient({ base: s.base, apiKey: s.apiKey, model }, { consent: hasConsent });
  const t0 = performance.now();
  const r = await c.ping();
  if (!r.ok) return { state: 'err', text: failureText(r) };
  return {
    state: 'ok',
    text: `连上了 · ${r.model ?? model} · ${Math.round(performance.now() - t0)}ms`,
  };
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
      <LlmForm />
    </Panel>
  );
}

function LlmForm() {
  const saved = useServices((s) => s.llm);
  const [d, setD] = useState<Settings>(saved);
  const [showKey, setShowKey] = useState(false);
  const [pt, setPt] = useState<Probe>({ state: 'idle' });
  const [pv, setPv] = useState<Probe>({ state: 'idle' });
  const patch = (p: Partial<Settings>) => setD((x) => ({ ...x, ...p }));
  const save = async () => {
    await setLlmSettings({
      ...d,
      base: d.base.trim(),
      apiKey: d.apiKey.trim(),
      textModel: d.textModel.trim(),
      visionModel: d.visionModel.trim(),
    });
    sfx.play('success');
    toast('模型设置已保存（只存在这台设备上）。', 'ok');
    setUi({ sheet: null });
  };
  const test = async () => {
    setPt({ state: 'run' });
    setPv(d.visionModel ? { state: 'run' } : { state: 'idle' });
    const [a, b] = await Promise.all([
      probe(d, d.textModel.trim()),
      d.visionModel ? probe(d, d.visionModel.trim()) : null,
    ]);
    setPt(a);
    if (b) setPv(b);
    sfx.play(a.state === 'ok' ? 'success' : 'error');
  };
  return (
    <>
      <p className="panel-note">
        填一个 <b>OpenAI 兼容</b>{' '}
        的服务商。浏览器会直接连它，所以服务商得允许网页跨域调用（CORS），否则测试连接会报「跨域被拦」。
      </p>
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
          value={d.apiKey}
          autoComplete="off"
          spellCheck={false}
          placeholder="sk-…"
          onChange={(e) => patch({ apiKey: e.currentTarget.value })}
        />
        <small className="fld-h">只存在这台设备的浏览器里，导出存档也不会带上它</small>
      </label>
      <Field
        label="文本模型"
        value={d.textModel}
        onChange={(v) => patch({ textModel: v })}
        placeholder="拆解 / 聊天 / 台词用"
      />
      <Field
        label="视觉模型"
        value={d.visionModel}
        onChange={(v) => patch({ visionModel: v })}
        placeholder="证据校验用（要能看图）"
      />
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
          聊天和台词用（默认 {DEFAULT_TEMPERATURE}）；拆解、匹配、校验各自固定
        </small>
      </label>
      <ProbeLine p={pt} label="文本" />
      <ProbeLine p={pv} label="视觉" />
      {!hasConsent() && <div className="probe err">还没同意首启告知页，测试请求不会发出。</div>}
      <div className="panel-act">
        <Btn kind="ghost" sm disabled={pt.state === 'run'} onClick={() => void test()}>
          测试连接
        </Btn>
        <Btn kind="pri" sm onClick={() => void save()}>
          保存
        </Btn>
      </div>
    </>
  );
}
