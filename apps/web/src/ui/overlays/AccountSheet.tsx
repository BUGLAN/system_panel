/** 账号底板：用户名 / 时区 / 修改密码（改完其他设备下线）。忘了密码找管理员命令行重置。 */
import { useState } from 'react';
import { changePassword } from '../../store/actions/auth';
import { useSync } from '../../store/game';
import { setUi, toast, useUi } from '../../store/uiStore';
import { Btn } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

export function AccountSheet() {
  const open = useUi((s) => s.sheet === 'account');
  const me = useSync((s) => s.me);
  const [old, setOld] = useState('');
  const [next, setNext] = useState('');
  const [busy, setBusy] = useState(false);
  const close = () => {
    setOld('');
    setNext('');
    setUi({ sheet: null });
  };
  const save = async () => {
    if (busy || !old || !next) return;
    setBusy(true);
    try {
      await changePassword(old, next);
      close();
    } catch (e) {
      toast(e instanceof Error ? e.message : '没改成。', 'err');
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={close} title="账号">
      <p className="sheet-note">
        {me ? `${me.username} · 时区 ${me.tz}` : ''}
        {me?.role === 'admin' ? ' · 管理员' : ''}
        <br />
        换日、连胜都按这个时区算；要改找管理员。
      </p>
      <label className="fld">
        <span className="fld-l">旧密码</span>
        <input
          className="lim-input"
          type="password"
          autoComplete="current-password"
          value={old}
          onChange={(e) => setOld(e.currentTarget.value)}
        />
      </label>
      <label className="fld">
        <span className="fld-l">新密码</span>
        <input
          className="lim-input"
          type="password"
          autoComplete="new-password"
          placeholder="至少 8 位"
          value={next}
          onChange={(e) => setNext(e.currentTarget.value)}
        />
        <small className="fld-h">改完之后，其他设备上的登录会失效。</small>
      </label>
      <div className="panel-act">
        <Btn kind="pri" sm disabled={busy || !old || next.length < 8} onClick={() => void save()}>
          修改密码
        </Btn>
      </div>
    </Sheet>
  );
}
