/**
 * 登录 / 注册（参考稿没有这一页，按告知页的版式与令牌做）。
 * 注册要邀请码（找管理员要）；时区自动取这台设备的。忘了密码找管理员重置。
 */
import { useRef, useState } from 'react';
import { ApiError } from '../../store/api';
import { login, register } from '../../store/actions/auth';
import { useSync } from '../../store/game';
import { Btn, Tap } from '../kit/Btn';
import { Typewriter } from '../kit/Typewriter';
import { useReveal } from '../hooks/useReveal';

type Mode = 'login' | 'register';

const HELLO: Record<Mode, string> = {
  login: '报上名来。认不出你，我可不干活。',
  register: '新来的？拿[邀请码]来。没有就去找给你链接的那个人。',
};

function Input({
  label,
  value,
  onChange,
  type = 'text',
  placeholder,
  autoComplete,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  placeholder?: string;
  autoComplete: string;
}) {
  return (
    <label className="fld">
      <span className="fld-l">{label}</span>
      <input
        className="lim-input"
        type={type}
        value={value}
        placeholder={placeholder}
        autoComplete={autoComplete}
        autoCapitalize="off"
        spellCheck={false}
        onChange={(e) => onChange(e.currentTarget.value)}
      />
    </label>
  );
}

export function Auth() {
  const ref = useRef<HTMLElement>(null);
  useReveal(ref);
  const online = useSync((s) => s.online);
  const [mode, setMode] = useState<Mode>('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [invite, setInvite] = useState('');
  const [line, setLine] = useState(HELLO.login);
  const [busy, setBusy] = useState(false);
  const ready =
    !!username.trim() && password.length > 0 && (mode === 'login' || !!invite.trim()) && !busy;

  const submit = async () => {
    if (!ready) return;
    setBusy(true);
    try {
      if (mode === 'login') await login(username.trim(), password);
      else await register(username.trim(), password, invite.trim());
    } catch (e) {
      setLine(
        e instanceof ApiError && e.offline
          ? '连不上服务器。网络通了再来。'
          : e instanceof Error
            ? e.message
            : String(e),
      );
    } finally {
      setBusy(false);
    }
  };

  const flip = () => {
    const next: Mode = mode === 'login' ? 'register' : 'login';
    setMode(next);
    setLine(HELLO[next]);
  };

  return (
    <section className="scene nohud on consent auth" ref={ref}>
      <div className="eyebrow rv">{mode === 'login' ? 'SIGN IN · 登录' : 'SIGN UP · 注册'}</div>
      <h1 className="h1 rv">
        {mode === 'login' ? '宿主，' : '绑定之前，'}
        <br />
        {mode === 'login' ? '先报上名来。' : '先登记在册。'}
      </h1>
      <div className="bubble rv consent-bubble">
        <span className="who2">SYSTEM · 她说</span>
        <Typewriter text={line} />
      </div>
      <form
        className="auth-form rv"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <Input
          label="用户名"
          value={username}
          onChange={setUsername}
          placeholder="3–20 个字：字母、数字、下划线或汉字"
          autoComplete="username"
        />
        <Input
          label="密码"
          type="password"
          value={password}
          onChange={setPassword}
          placeholder={mode === 'register' ? '至少 8 位' : ''}
          autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
        />
        {mode === 'register' && (
          <Input
            label="邀请码"
            value={invite}
            onChange={setInvite}
            placeholder="XXXX-XXXX-XXXX-XXXX"
            autoComplete="off"
          />
        )}
        <button type="submit" hidden />
      </form>
      <div className="ex-sp" />
      <div className="consent-act kb-dock rv">
        <Btn kind="pri" disabled={!ready} onClick={() => void submit()}>
          {busy ? '她在核对……' : mode === 'login' ? '登录' : '注册并登录'}
        </Btn>
        <Tap className="auth-flip" quiet onClick={flip}>
          {mode === 'login' ? '有邀请码？注册一个 ›' : '已经有账号了？去登录 ›'}
        </Tap>
        <small className="auth-hint">
          {online ? '忘了密码：找管理员重置。' : '现在没联网：登录要连得上服务器。'}
        </small>
      </div>
    </section>
  );
}
