/* main.js — 启动、事件、演示控制台 */
'use strict';

(function main() {
  // 桌面：手机壳按窗口高度等比缩放（逻辑尺寸始终 390×844）
  const fit = () => {
    const ph = $('#phone');
    if (innerWidth < 600) { ph.style.transform = ''; ph.style.margin = ''; return; }
    const k = Math.min(1, (innerHeight - 36) / 844);
    ph.style.transform = k < 1 ? `scale(${k.toFixed(4)})` : '';
    ph.style.margin = k < 1 ? `${(-844 * (1 - k) / 2).toFixed(1)}px ${(-390 * (1 - k) / 2).toFixed(1)}px` : '';
  };
  fit(); addEventListener('resize', fit);
  try { Object.assign(App.settings, JSON.parse(localStorage.getItem('opus-v2/settings') || '{}')); } catch (e) { }
  if (App.settings.voice) Voice.mode = App.settings.voice;
  Sound.on = App.settings.sound;
  Store.load();
  App._roll = Store.rollDay();
  FX.init($('#fx'));
  Tap.init();
  Line.init();

  // 每帧：她的舞台（镜头/环/情绪）+ 嘴型包络 + DOM 钉到舞台
  let last = performance.now();
  const loop = now => {
    const dt = Math.min(.05, (now - last) / 1000); last = now;
    try { Stage._tick(dt); } catch (e) { console.warn('[stage]', e); }
    Voice.tick(dt); App.place();
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  setInterval(() => App.second(), 1000);

  const app = $('#app');
  // 手机屏不该被任何东西"滚动"（Tab 聚焦、软键盘、自动化点击都可能把隐藏层滚进来）
  const pin = () => { if (app.scrollTop || app.scrollLeft) { app.scrollTop = 0; app.scrollLeft = 0; } };
  app.addEventListener('scroll', pin); $('#phone').addEventListener('scroll', () => { $('#phone').scrollTop = 0; $('#phone').scrollLeft = 0; });
  const local = e => { const r = appRect(), k = app.offsetWidth / r.width; return { x: (e.clientX - r.left) * k, y: (e.clientY - r.top) * k }; };
  app.addEventListener('pointermove', e => { const p = local(e); Stage.pointer(p.x, p.y); });
  app.addEventListener('pointerdown', e => { App.lastAct = performance.now(); const p = local(e); Stage.pointer(p.x, p.y); if (App.dozing) App.undoze(); }, true);
  // 戳她（只在大厅里）
  $('#stage').addEventListener('pointerdown', e => {
    if (App.mode !== 'lobby' || App.busy) return;
    const p = local(e); if (Stage.hit(p.x, p.y)) App.poke();
  });

  $('#cta').onclick = () => {
    Sound.play('tap'); buzz(8);
    if (Store.S.active) return App.exec();
    App.dispatch();
  };
  $$('#dock .dk').forEach(b => b.onclick = () => {
    Sound.play('tap');
    const g = b.dataset.go;
    if (g === 'main') App.mainline(); else App.sheet(g);
  });
  $('#hudMenu').onclick = () => { Sound.play('tap'); App.sheet('system'); };
  $('#hudLv').onclick = () => { Sound.play('tap'); if (App.mode === 'lobby') App.sheet('archive'); };
  $('#shX').onclick = () => { Sound.play('tap'); App.closeSheet(); };
  $('#execPill').onclick = () => { Sound.play('tap'); App.exec(); };
  $('#ringTag').onclick = () => { Sound.play('tap'); App.mainline(); };

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { App.hiddenAt = Clock.now(); Store.save(); return; }
    if (!App.hiddenAt) return;
    const away = Clock.now() - App.hiddenAt; App.hiddenAt = 0;
    if (App.mode === 'exec' && away > 15000 && !App.busy) {
      Stage.look('user');
      Line.say(line('execAway', { dur: fmtDur(away) }), { emo: 'neutral', hold: 2400 }).then(() => { if (App.mode === 'exec') Line.hide(); });
    }
  });
  addEventListener('pagehide', () => Store.save());

  /* ── 演示控制台 ── */
  const dm = $('#demo');
  const S = () => Store.S;
  const ensureActive = () => {
    if (S().active) return true;
    const T = Store.head(); if (!T) return false;
    Store.accept(T); return true;
  };
  $('#dmCrit').textContent = S().forceCrit ? '开' : '关';
  dm.addEventListener('click', e => {
    const b = e.target.closest('[data-demo]'); if (!b) return;
    const k = b.dataset.demo;
    if (k === 'fresh') { Store.wipe(); location.reload(); return; }
    if (k === 'veteran') { Store.veteran(); location.reload(); return; }
    if (App.mode === 'boot') return;
    if (!S().bound && k !== 'fresh') { Banner.show('演示', '先走完绑定，或载入老宿主', '!'); return; }
    switch (k) {
      case 'dispatch': if (App.busy) return; Sheet.close(); MainV.hide(); App.dispatch(); break;
      case 'forceS': S().forceS = true; Store.save(); Banner.show('演示', '下一单必出 S', 'S'); break;
      case 'crit': S().forceCrit = !S().forceCrit; Store.save(); $('#dmCrit').textContent = S().forceCrit ? '开' : '关'; break;
      case 'settle': if (App.busy) return; if (ensureActive()) { Sheet.close(); App.submit(); } break;
      case 'fail': if (App.busy) return; if (ensureActive()) { Sheet.close(); App.fail('quit'); } break;
      case 'lvup': S().exp = need(S().lv) - 1; Store.save(); HUD.render(); Banner.show('演示', '再拿 1 点经验就升级', '↑'); break;
      case 'away': if (App.busy || !['lobby', 'exec'].includes(App.mode)) return;
        S().prevSeen = Clock.now() - 6 * 36e5 - 17 * 6e4; App.greet(); break;
      case 'day': {
        if (App.busy) return;
        const t = new Date(Clock.now()); t.setDate(t.getDate() + 1); t.setHours(8, 30, 0, 0);
        S().prevSeen = Clock.now();
        Clock.shift += t.getTime() - Clock.now();
        App._roll = Store.rollDay(); HUD.render();
        Sheet.close(); MainV.hide(); Exec.hide(); App.greet(); break;
      }
      case 'ff': if (S().active) { S().active.startAt -= 10 * 6e4; Store.save(); Exec.tick(); Dock.render(); } break;
    }
  });

  App.boot();
})();
