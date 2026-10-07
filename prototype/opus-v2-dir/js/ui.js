/* ui.js — 界面零件：字幕、回应、玻璃板、执行面板、结算卡、投影面板 */
'use strict';

const appRect = () => $('#app').getBoundingClientRect();
/* 元素相对 #app 的位置（桌面上手机壳可能被整体缩放，要除回去） */
const rel = el => {
  const a = appRect(), k = $('#app').offsetWidth / (a.width || 1), r = el.getBoundingClientRect();
  return { x: (r.left - a.left) * k, y: (r.top - a.top) * k, w: r.width * k, h: r.height * k, cx: (r.left - a.left + r.width / 2) * k, cy: (r.top - a.top + r.height / 2) * k };
};
const COIN_SVG = '<svg viewBox="0 0 16 16"><path d="M8 1l6 3.5v7L8 15l-6-3.5v-7z"/></svg>';

/* ── 点屏幕任意处：推进 / 跳过（按钮、输入框不算） ── */
const Tap = {
  waiters: [],
  init() {
    $('#app').addEventListener('pointerdown', e => {
      if (e.target.closest('button, input, label, form, .pl-print, .drawer, #sheet, #demo, .rl, .ringtag')) return;
      const ws = this.waiters; this.waiters = []; ws.forEach(f => f());
    }, true);
  },
  next() { return new Promise(r => this.waiters.push(r)); },
};
const wait = ms => Promise.race([sleep(ms), Tap.next()]);

/* ── HUD 与底栏 ── */
const HUD = {
  render() {
    const S = Store.S;
    $('#hudLvN').textContent = S.lv;
    $('#lvArc').style.strokeDashoffset = 125.66 * (1 - clamp(S.exp / need(S.lv), 0, 1));
    $('#hudName').textContent = S.name || '宿主';
    $('#hudTitle').textContent = '「' + Store.title + '」';
    $('#hudStreak').innerHTML = S.streak ? `连击 <b>${S.streak}</b> 天` : '连击 —';
    $('#hudCoin').textContent = S.coins;
    Dock.render();
  },
  coin(v) {
    const c = $('.hud-coin'); $('#hudCoin').textContent = v;
    c.classList.remove('bump'); void c.offsetWidth; c.classList.add('bump');
  },
};
const Dock = {
  render() {
    const S = Store.S, cta = $('#cta'); if (!S) return;
    cta.classList.remove('run', 'idle');
    if (S.active) {
      cta.classList.add('run');
      $('#ctaLabel').textContent = fmtClock(Clock.now() - S.active.startAt);
      $('#ctaSub').textContent = '执行中'; $('#ctaCap').textContent = '点开 · 继续';
    } else if (S.queue.length) {
      $('#ctaLabel').textContent = '委托'; $('#ctaSub').textContent = 'TASK'; $('#ctaN').textContent = S.queue.length;
      $('#ctaCap').textContent = `她手里有 ${S.queue.length} 单`;
    } else {
      cta.classList.add('idle');
      $('#ctaLabel').textContent = '今日已清'; $('#ctaSub').textContent = S.hint ? `明日 · ${S.hint.r} 级` : '';
      const left = endOfDay() - Clock.now();
      $('#ctaCap').textContent = '换日还有 ' + fmtClock(left).replace(/:\d\d$/, '');
    }
    const pill = $('#execPill');
    pill.classList.toggle('on', !!S.active && ['lobby', 'main', 'sheet'].includes(App.mode));
    if (S.active) $('#pillT').textContent = fmtClock(Clock.now() - S.active.startAt);
  },
};

/* ── 她的字幕（打字机 + 电子音节 + 嘴型） ── */
const Line = {
  token: 0,
  init() {
    this.el = $('#line'); this.txt = $('#lineTxt'); this.bars = $$('#line .wave i');
    Stage.onTick.push(() => {
      const m = Voice.mouth, t = performance.now() / 85;
      this.bars.forEach((b, i) => { b.style.transform = `scaleY(${clamp(.14 + m * (.55 + .45 * Math.sin(t + i * 1.7)), .12, 1).toFixed(3)})`; });
    });
  },
  at(y) { this.el.style.setProperty('--ly', Math.round(y) + 'px'); },
  hide() { this.token++; this.el.classList.remove('on', 'wait'); Voice.hush(); },
  async say(text, o = {}) {
    const tk = ++this.token;
    if (o.emo) Stage.emote(o.emo, o.look); else if (o.look) Stage.look(o.look);
    if (o.motion) Stage.motion(o.motion);
    const emo = o.emo || Stage.emo;
    $('#lineMood').textContent = MOOD_LABEL[emo] || '';
    this.el.classList.toggle('soft', !!o.soft);
    const chars = richChars(text);
    this.txt.innerHTML = chars.map(c => `<span class="c">${c.em ? '<em>' : ''}${esc(c.ch)}${c.em ? '</em>' : ''}</span>`).join('');
    this.el.classList.remove('wait'); this.el.classList.add('on');
    const spans = [...this.txt.children];
    const speed = o.speed || (o.soft ? 42 : 34);
    const tts = Voice.speak(text, emo);
    let skip = false; Tap.next().then(() => { skip = true; });
    for (let i = 0; i < spans.length; i++) {
      if (tk !== this.token) return;
      spans[i].classList.add('on');
      if (skip) continue;
      const ch = chars[i].ch;
      if (!tts) Voice.syllable(ch, emo, o.soft);
      let d = speed;
      if ('，、：'.includes(ch)) d += 120; else if ('。！？'.includes(ch)) d += 240; else if (ch === '…') d += 70; else if (ch === '—') d += 40;
      await sleep(d);
    }
    spans.forEach(s => s.classList.add('on'));
    if (!tts) Voice._target = 0;
    if (tk !== this.token) return;
    if (tts && !skip) { // 人声：等她说完（点一下可以打断）
      const cut = await Promise.race([tts.then(() => false), Tap.next().then(() => true)]);
      if (cut) Voice.hush();
      if (tk !== this.token) return;
      if (!o.wait && (o.hold ?? 0) < 5000) { await wait(Math.min(o.hold ?? 300, 300)); return; }
    }
    if (o.wait) { this.el.classList.add('wait'); await Tap.next(); this.el.classList.remove('wait'); }
    else await wait(o.hold ?? clamp(420 + plain(text).length * 42, 900, 2400));
  },
  async seq(arr, o = {}) { for (const s of arr) { await this.say(s, o); } },
};

/* ── 宿主的回应 ── */
function choose(opts) {
  return new Promise(res => {
    const box = $('#choices'); box.innerHTML = ''; let locked = false;
    opts.forEach((o, i) => {
      const b = el('button', 'ch' + (o.main ? ' main' : ''), `<span>${esc(o.t)}</span>`);
      box.appendChild(b);
      setTimeout(() => b.classList.add('on'), 80 + i * 90);
      b.onclick = () => {
        if (locked) return; locked = true;
        Sound.play('choose'); buzz(8);
        [...box.children].forEach(c => c.classList.add(c === b ? 'said' : 'gone'));
        setTimeout(() => { box.innerHTML = ''; res(o.v); }, 360);
      };
    });
  });
}
function askText({ ps = '宿主 ›', ph = '', presets = [], max = 24, def = '' } = {}) {
  return new Promise(res => {
    const f = $('#ask'), inp = $('#askIn');
    $('#askPs').textContent = ps; inp.placeholder = ph; inp.value = def; inp.maxLength = max;
    const pr = $('#askPresets'); pr.innerHTML = '';
    presets.forEach(p => {
      const b = el('button', '', esc(p)); b.type = 'button';
      b.onclick = () => { inp.value = p; Sound.play('tap'); };
      pr.appendChild(b);
    });
    f.classList.add('on');
    setTimeout(() => inp.focus({ preventScroll: true }), 350);
    f.onsubmit = e => {
      e.preventDefault();
      const v = inp.value.trim();
      if (!v && !def) { Sound.play('deny'); inp.focus(); return; }
      f.classList.remove('on'); inp.blur(); Sound.play('choose'); res(v || def);
    };
  });
}

/* ── 横幅（称号 / 道具 / 连击） ── */
const Banner = {
  q: Promise.resolve(),
  show(kick, text, glyph = '✦', ms = 2200) {
    this.q = this.q.then(async () => {
      const b = $('#banner');
      b.innerHTML = `<span class="glyph">${glyph}</span><span><small>${kick}</small><b>${esc(text)}</b></span>`;
      b.classList.add('on'); Sound.play('title');
      await sleep(ms); b.classList.remove('on'); await sleep(350);
    });
    return this.q;
  },
};

/* ── 指纹（接单用）：一组同心弧 ── */
const FP_PATHS = (() => {
  const out = [], cx = 31, cy = 38;
  const radii = [4, 8.5, 13, 17.5, 22, 26.5, 31];
  radii.forEach((r, i) => {
    const a0 = (196 + i * 7) * Math.PI / 180, a1 = (520 - i * 9) * Math.PI / 180;
    const p = (a) => [cx + r * Math.cos(a), cy + r * 1.12 * Math.sin(a)];
    const [x0, y0] = p(a0), [x1, y1] = p(a1);
    const large = (a1 - a0) > Math.PI ? 1 : 0;
    out.push(`M${x0.toFixed(1)} ${y0.toFixed(1)} A${r} ${(r * 1.12).toFixed(1)} 0 ${large} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`);
  });
  return out;
})();
const FP_SVG = `<svg viewBox="0 0 62 70"><g class="base">${FP_PATHS.map(d => `<path d="${d}"/>`).join('')}</g><g class="fill">${FP_PATHS.map(d => `<path d="${d}"/>`).join('')}</g></svg>`;

/* ═══ 玻璃板：她刻给你的那一单 ═══ */
const Plate = {
  T: null, fast: false,
  rewardHTML(T) {
    const R = RARITY[T.r], k = T.kind === 'remedy' ? .5 : 1;
    const at = Object.entries(T.attrs).map(([a, v]) => `${a}+${v}`).join(' ');
    return `<b>EXP ${Math.round(R.exp * k)}</b> · ◈ ${Math.round(R.coin * k)}<span class="at">${at}</span>`;
  },
  build(T) {
    this.T = T; this._wavered = false; const S = Store.S;
    const p = $('#plate');
    p.getAnimations({ subtree: true }).forEach(a => a.cancel());
    p.style.setProperty('--rk', RARITY.F.c);
    const kind = T.kind === 'main' ? `主线 · 第 ${T.ring + 1} 环 / ${S.rings.length}` : T.kind === 'remedy' ? '补救 · 24 小时内有效' : T.hinted ? '日常 · 她替你留的' : '日常委托';
    p.innerHTML = `
      <div class="pl">
        <div class="pl-glass"><div class="pl-sheen"></div><div class="pl-edge"></div>
          <div class="pl-in">
            <div class="pl-head"><span class="to" data-eng>TO · <b>${esc(S.name)}</b> · LV${S.lv}</span><span data-eng>№ ${String(T.serial).padStart(4, '0')}</span></div>
            <div class="pl-kind" data-eng>${kind}</div>
            <h2 class="pl-title" data-eng>${esc(T.name)}</h2>
            <p class="pl-why" data-eng>${esc(T.reason || '')}</p>
            <dl class="pl-spec">
              <div data-eng><dt>证明</dt><dd>${esc(T.proof)}</dd></div>
              <div data-eng><dt>时限</dt><dd>${fmtMin(T.min)}</dd></div>
              <div data-eng id="plReward"><dt>报酬</dt><dd>${this.rewardHTML(T)}</dd></div>
            </dl>
            <div class="pl-print" id="plPrint"><div class="fp">${FP_SVG}</div><div class="hint"><b id="fpTxt">按住 · 接下</b><small id="fpSub">HOLD TO ACCEPT</small></div></div>
          </div>
        </div>
        <div class="pl-rank"><div class="ring"><svg viewBox="0 0 80 80"><circle class="bgc" cx="40" cy="40" r="36"/><circle class="fgc" cx="40" cy="40" r="36"/></svg><b class="letter">F</b></div><div class="meter">${'<i></i>'.repeat(7)}</div></div>
        <i class="laser"></i>
      </div>`;
    $('#plPrint').style.opacity = .25;
    // 轻微 3D：跟手指倾斜，玻璃反光跟着走
    const pl = p.querySelector('.pl'), sheen = p.querySelector('.pl-sheen');
    p.onpointermove = e => {
      const r = p.getBoundingClientRect(), x = (e.clientX - r.left) / r.width - .5, y = (e.clientY - r.top) / r.height - .5;
      pl.style.setProperty('--ry', (x * 9).toFixed(2) + 'deg'); pl.style.setProperty('--rx', (-y * 7).toFixed(2) + 'deg');
      sheen.style.setProperty('--sx', (x * 60 - 10).toFixed(1) + '%');
    };
    p.onpointerleave = () => { pl.style.setProperty('--ry', '0deg'); pl.style.setProperty('--rx', '0deg'); };
  },
  async land() {
    const p = $('#plate'); p.classList.add('on'); p.style.opacity = '';
    const chest = Stage.toScreen(0, NY.chest), r = rel(p);
    const dx = chest.x - r.cx, dy = chest.y - r.y;
    Sound.play('whoosh');
    p.animate([
      { transform: `translate(${dx}px,${dy}px) scale(.16) rotateX(55deg)`, opacity: 0, filter: 'brightness(3)' },
      { opacity: 1, offset: .35 },
      { transform: 'translate(0,0) scale(1.035) rotateX(-5deg)', filter: 'brightness(1.5)', offset: .8 },
      { transform: 'none', opacity: 1, filter: 'none' },
    ], { duration: this.fast ? 420 : 560, easing: 'cubic-bezier(.2,.75,.25,1)', fill: 'forwards' });
    await sleep(this.fast ? 330 : 440);
    Sound.play('land'); FX.shake(3, 200); FX.flash('#9ff0ff', .1, 160); buzz(18);
    FX.ripple(r.cx, r.y + r.h, { r0: 40, r1: 260, flat: .12, col: '#38e1ff', ms: 700 });
    await sleep(150);
  },
  async rankRoll(r, from = 0, down = false) {
    const p = $('#plate'), L = p.querySelector('.letter'), M = $$('.meter i', p), fg = p.querySelector('.fgc');
    const target = RARITY[r].i;
    const set = i => {
      const rk = RANKS[i]; L.textContent = rk; p.style.setProperty('--rk', RARITY[rk].c);
      M.forEach((m, k) => m.classList.toggle('on', k <= i));
      fg.style.strokeDashoffset = 226 * (1 - (i + 1) / 7);
    };
    if (down) {
      for (let i = from; i >= target; i--) { set(i); Sound.play('rung', i); if (i > target) await sleep(140); }
    } else {
      for (let i = from; i <= target; i++) {
        set(i); Sound.play('rung', i);
        if (i < target) {
          let d = (60 + i * 26) * (this.fast ? .6 : 1);
          if (target === 6 && i === 5) d = 560; // S：在 A 停一拍
          await sleep(d);
        }
      }
    }
    L.classList.remove('lock'); void L.offsetWidth; L.classList.add('lock');
    Sound.play('rank', target);
    FX.flash(RARITY[r].c, target >= 4 ? .13 : .06, 280);
    if (target >= 5) { FX.shake(6, 320); buzz([20, 30, 50]); Stage.glitch(180, .6); }
    const lr = rel(L);
    FX.burst(lr.cx, lr.cy, { n: 8 + target * 9, cols: [RARITY[r].c, '#38e1ff', '#e9fbff'], min: 60, max: 150 + target * 55, life: .9, g: 60 });
  },
  async engrave() {
    const p = $('#plate'), laser = p.querySelector('.laser'), els = $$('[data-eng]', p);
    let skip = false; Tap.next().then(() => { skip = true; });
    const pr = rel(p);
    for (const e of els) {
      if (skip) break;
      const r = rel(e), dur = clamp((e.textContent || '').length * 17, 110, 460) * (this.fast ? .55 : 1);
      e.classList.add('hot'); laser.classList.add('on');
      const y = r.y - pr.y + r.h / 2, t0 = performance.now(); let lastS = 0;
      await new Promise(res => {
        const step = now => {
          const k = skip ? 1 : clamp((now - t0) / dur, 0, 1);
          e.style.clipPath = `inset(-20% ${((1 - k) * 100).toFixed(2)}% -20% 0)`;
          const x = r.x - pr.x + r.w * k;
          laser.style.left = x + 'px'; laser.style.top = y + 'px';
          if (now - lastS > 42) { lastS = now; FX.spark(pr.x + x, pr.y + y, 3); Sound.play('engrave'); }
          if (k < 1) requestAnimationFrame(step); else res();
        };
        requestAnimationFrame(step);
      });
      e.style.clipPath = ''; e.classList.add('done');
      setTimeout(() => e.classList.remove('hot'), 420);
    }
    laser.classList.remove('on');
    els.forEach(e => { e.style.clipPath = ''; if (!e.classList.contains('done')) { e.classList.add('done'); setTimeout(() => e.classList.remove('hot'), 300); } });
    $('#plPrint').style.transition = 'opacity .4s'; $('#plPrint').style.opacity = 1;
  },
  /* 按住指纹 0.9 秒 = 接下；松手会退回去 */
  hold() {
    return new Promise(res => {
      const pr = $('#plPrint'), fills = $$('#plPrint .fill path');
      const lens = fills.map(f => f.getTotalLength());
      fills.forEach((f, i) => { f.style.strokeDasharray = lens[i]; f.style.strokeDashoffset = lens[i]; });
      let p = 0, holding = false, raf = 0, drone = null, lastStep = -1, last = 0;
      const draw = () => {
        fills.forEach((f, i) => { const s = i / fills.length * .55, k = clamp((p - s) / .45, 0, 1); f.style.strokeDashoffset = lens[i] * (1 - k); });
        $('#fpTxt').textContent = p > 0 ? (p >= 1 ? '已接下' : '确认中') : '按住 · 接下';
        $('#fpSub').textContent = p > 0 ? `宿主认证 ${Math.round(p * 100)}%` : 'HOLD TO ACCEPT';
      };
      const step = now => {
        const dt = Math.min(.05, (now - last) / 1000); last = now;
        p = clamp(p + (holding ? dt / .9 : -dt / .35), 0, 1);
        draw();
        const st = Math.floor(p * 8);
        if (holding && st !== lastStep) { lastStep = st; Sound.play('hold', p); buzz(5); }
        if (p >= 1) { done('accept'); return; }
        raf = (holding || p > 0) ? requestAnimationFrame(step) : 0;
      };
      const down = e => {
        e.preventDefault(); holding = true; pr.classList.add('hold'); Stage.look({ x: Stage.W / 2, y: Stage.H * .82 });
        drone = Sound.drone(true, 900); last = performance.now();
        if (!raf) raf = requestAnimationFrame(step);
      };
      const up = () => {
        if (!holding) return; holding = false; pr.classList.remove('hold');
        drone && drone.stop(); drone = null;
        if (p < 1) { Sound.play('unhold'); if (p > .25 && !this._wavered) { this._wavered = true; Line.say(line('waver'), { emo: 'smug', hold: 1400 }); } }
        if (!raf) { last = performance.now(); raf = requestAnimationFrame(step); }
      };
      const done = v => {
        pr.removeEventListener('pointerdown', down); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up);
        cancelAnimationFrame(raf); drone && drone.stop(); this._cancel = null; res(v);
      };
      pr.addEventListener('pointerdown', down); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
      this._cancel = done;
    });
  },
  cancelHold(v) { this._cancel && this._cancel(v); },
  alt(opts, onPick) {
    const a = $('#plateAlt'); a.innerHTML = '';
    opts.forEach(o => { const b = el('button', '', esc(o.t)); b.onclick = () => { Sound.play('tap'); onPick(o.v); }; a.appendChild(b); });
    a.classList.add('on');
  },
  hideAlt() { $('#plateAlt').classList.remove('on'); },
  async seal(targetPt) {
    const p = $('#plate'), pl = p.querySelector('.pl'), r = rel(p);
    this.hideAlt();
    Sound.play('seal'); FX.flash('#bff6ff', .24, 280); FX.shake(4, 220); buzz([30, 40, 60]);
    FX.ripple(r.cx, r.cy, { r1: 300, flat: .38, col: '#bff6ff', w: 3, ms: 700 });
    await pl.animate([{ transform: 'none', filter: 'brightness(1)' }, { transform: 'scaleY(.012) scaleX(1.05)', filter: 'brightness(4)' }],
      { duration: 260, easing: 'cubic-bezier(.6,0,.9,.5)', fill: 'forwards' }).finished;
    p.style.opacity = 0;
    FX.streak(r.cx, r.cy, targetPt.x, targetPt.y, { ms: 440, w: 3 });
    await sleep(400);
    FX.burst(targetPt.x, targetPt.y, { n: 26, max: 280, life: .8 });
    this.clear();
  },
  async back() {
    const p = $('#plate'), r = rel(p), chest = Stage.toScreen(0, NY.chest);
    this.hideAlt(); Sound.play('whoosh');
    await p.animate([{ transform: 'none', opacity: 1 }, { transform: `translate(${chest.x - r.cx}px,${chest.y - r.y}px) scale(.14)`, opacity: 0 }],
      { duration: 440, easing: 'cubic-bezier(.5,0,.75,.35)', fill: 'forwards' }).finished;
    this.clear();
  },
  clear() {
    const p = $('#plate'); p.getAnimations({ subtree: true }).forEach(a => a.cancel());
    p.classList.remove('on'); p.style.opacity = ''; p.innerHTML = ''; this.hideAlt();
  },
  async reRank(T, fromR) { // 退缩：字母往下掉一档，报酬重刻
    await this.rankRoll(T.r, RARITY[fromR].i, true);
    const rw = $('#plReward'); rw.classList.remove('done'); rw.querySelector('dd').innerHTML = this.rewardHTML(T);
    rw.style.clipPath = ''; void rw.offsetWidth; rw.classList.add('done');
    rw.animate([{ filter: 'brightness(2.5)' }, { filter: 'none' }], { duration: 600 });
  },
};

/* ═══ 执行面板 ═══ */
const Exec = {
  iv: 0,
  show() {
    const S = Store.S, A = S.active, T = A.task;
    const ex = $('#exec'); ex.style.setProperty('--rk', RARITY[T.r].c);
    const kindTxt = T.kind === 'main' ? `RING ${T.ring + 1}/${S.rings.length}` : T.kind === 'remedy' ? 'REMEDY' : 'DAILY';
    ex.innerHTML = `
      <div class="ex-col">
        <div class="ex-k"><span class="rk">${T.r}</span><span class="kick">执行中 · ${kindTxt}</span></div>
        <h3 class="ex-name">${esc(T.name)}</h3>
        <div class="ex-t" id="exT">00:00</div>
        <div class="ex-lim"><div class="ex-bar"><i id="exBar"></i></div><small>/ ${fmtClock(T.min * 6e4)}</small></div>
        <div class="ex-watch"><i class="eye" id="exEye"></i>SYSTEM 正在看着你</div>
        <div class="ex-evi"><span class="kick">证据 · ${esc(T.proof)}</span><div class="row" id="exSlots"></div>
          <p class="ex-crit">暴击率<b id="exCrit">6%</b><span class="tags" id="exTags"></span></p></div>
      </div>
      <div class="drawer" id="exDrawer"></div>
      <div class="ex-act"><button class="btn ghost" id="exItem">道具 <em id="exItemN"></em></button><button class="btn main" id="exGo">提交 · 让她验收</button></div>
      <div class="ex-low"><button class="quit" id="exQuit"><i></i><span>按住 · 认输</span></button><button class="mini" id="exMin">收起 ▾</button></div>`;
    ex.classList.add('on');
    this.slots(); this.crit();
    $('#exItem').onclick = () => { Sound.play('tap'); this.drawer(); };
    $('#exGo').onclick = () => { Sound.play('tap'); App.submit(); };
    $('#exMin').onclick = () => { Sound.play('tap'); App.lobby(); };
    this.quitHold($('#exQuit'));
    clearInterval(this.iv); this.iv = setInterval(() => this.tick(), 250); this.tick();
  },
  hide() { clearInterval(this.iv); const ex = $('#exec'); ex.classList.remove('on'); setTimeout(() => { if (!ex.classList.contains('on')) ex.innerHTML = ''; }, 500); },
  tick() {
    const A = Store.S.active; if (!A || !$('#exT')) return;
    const e = Clock.now() - A.startAt, lim = A.task.min * 6e4;
    $('#exT').textContent = fmtClock(e);
    $('#exBar').style.width = clamp(e / lim * 100, 0, 100) + '%';
    $('#exT').classList.toggle('warn', e > lim * .85);
    if (e >= lim && !this._timeout && !App.busy) { this._timeout = true; App.fail('timeout'); }
  },
  slots() {
    const A = Store.S.active, box = $('#exSlots'); if (!box) return;
    box.innerHTML = '';
    for (let i = 0; i < 3; i++) {
      const ph = A.photos[i];
      const s = el('button', 'slot' + (ph ? ' full' : i === A.photos.length ? ' add' : ''));
      if (ph) s.style.backgroundImage = `url(${ph})`;
      if (!ph && i === A.photos.length) s.onclick = () => { Sound.play('tap'); App.snap(); };
      box.appendChild(s);
    }
    const n = Object.keys(ITEMS).filter(k => ITEMS[k].use === 'exec').reduce((s, k) => s + Store.S.items[k], 0);
    $('#exItemN').textContent = n || '';
  },
  crit() {
    const A = Store.S.active; if (!A || !$('#exCrit')) return;
    $('#exCrit').textContent = Math.round(Store.critChance() * 100) + '%';
    $('#exTags').innerHTML = ['dbl', 'crit', 'shield'].filter(k => A[k]).map(k => `<i>${ITEMS[k].glyph} ${ITEMS[k].name}</i>`).join('');
  },
  drawer() {
    const d = $('#exDrawer'), S = Store.S, A = S.active;
    if (d.classList.contains('on')) { d.classList.remove('on'); return; }
    d.innerHTML = ['dbl', 'crit', 'shield'].map(k => {
      const it = ITEMS[k], used = A[k], n = S.items[k];
      return `<button class="it${used ? ' used' : ''}" data-k="${k}" ${!n && !used ? 'disabled' : ''}><span class="glyph">${it.glyph}</span><span><b>${it.name}</b><small>${used ? '已生效' : '持有 ×' + n}</small></span></button>`;
    }).join('') + `<button class="it" data-k="shop"><span class="glyph">◈</span><span><b>去补给</b><small>金币 ${S.coins}</small></span></button>`;
    d.classList.add('on');
    d.onclick = e => {
      const b = e.target.closest('.it'); if (!b || b.disabled) return;
      const k = b.dataset.k; d.classList.remove('on');
      if (k === 'shop') { App.sheet('supply'); return; }
      if (A[k]) return;
      if (Store.useItem(k)) {
        Sound.play('seal'); FX.flash('#38e1ff', .1, 200); this.crit(); this.slots();
        Line.say(line({ dbl: 'itemDbl', crit: 'itemCrit', shield: 'itemShield' }[k]), { emo: k === 'shield' ? 'smug' : 'neutral', hold: 1800 });
      }
    };
  },
  quitHold(btn) {
    let p = 0, holding = false, raf = 0, drone = null, last = 0;
    const fill = btn.querySelector('i'), label = btn.querySelector('span');
    const step = now => {
      const dt = Math.min(.05, (now - last) / 1000); last = now;
      p = clamp(p + (holding ? dt / 1.2 : -dt / .3), 0, 1);
      fill.style.width = p * 100 + '%';
      $('#veil').style.transition = 'none'; $('#veil').style.opacity = p * .75;
      Sound.ctx && Sound.lp.frequency.setTargetAtTime(18000 - p * 16500, Sound.ctx.currentTime, .05);
      label.textContent = p > 0 ? '松手还来得及' : '按住 · 认输';
      if (p >= 1) { holding = false; drone && drone.stop(); $('#veil').style.transition = ''; App.fail('quit'); return; }
      if (holding || p > 0) raf = requestAnimationFrame(step); else { raf = 0; $('#veil').style.transition = ''; $('#veil').style.opacity = 0; }
    };
    btn.onpointerdown = e => { e.preventDefault(); holding = true; drone = Sound.drone(false, 1200); last = performance.now(); if (!raf) raf = requestAnimationFrame(step); };
    const up = () => { if (!holding) return; holding = false; drone && drone.stop(); if (!raf) { last = performance.now(); raf = requestAnimationFrame(step); } };
    btn.onpointerup = btn.onpointerleave = btn.onpointercancel = up;
  },
};

/* ═══ 结算卡（DOM 部分；编排在 flows.js） ═══ */
const ResultUI = {
  build(res) {
    const T = res.task, r = $('#result');
    r.style.setProperty('--rk', RARITY[T.r].c);
    r.innerHTML = `
      <button class="rs-save" id="rsSave">${'<svg viewBox="0 0 16 16"><path d="M8 2v8M4.5 6.5L8 10l3.5-3.5M2.5 13.5h11"/></svg>'}保存战报</button>
      <div class="rs-stack">
      <div class="rs-glyph" id="rsGlyph"><i class="halo2"></i><i class="halo"></i><b>${T.r}</b></div>
      <div class="rs-head" id="rsHead"><span class="kick">CLEAR · ${T.kind === 'main' ? '主线第 ' + (T.ring + 1) + ' 环' : T.kind === 'remedy' ? '补救' : '日常'}</span><h3>${esc(T.name)}</h3></div>
      <div class="rs-card" id="rsCard">
        <div class="rs-exp"><span class="kick">EXP</span><b id="rsExp">0</b><span class="rs-tags" id="rsTags"></span></div>
        <div class="rs-bar" id="rsBar"><i id="rsBarI"></i></div>
        <div class="rs-lv"><span>LV <b id="rsLv">${res.before.lv}</b></span><span id="rsNeed">${res.before.exp} / ${res.before.need}</span></div>
        <div class="rs-gain" id="rsGain"></div>
        <p class="rs-near" id="rsNear"></p>
      </div></div>`;
    $('#rsBarI').style.width = (res.before.exp / res.before.need * 100) + '%';
    r.classList.add('on');
  },
  chip(html, cls = '') {
    const c = el('span', 'chip ' + cls, html); $('#rsGain').appendChild(c);
    requestAnimationFrame(() => requestAnimationFrame(() => c.classList.add('on')));
    return c;
  },
  hide() { const r = $('#result'); r.classList.remove('on'); setTimeout(() => { if (!r.classList.contains('on')) r.innerHTML = ''; }, 400); },
};

/* ═══ 主线全景 ═══ */
const MainV = {
  show() {
    const S = Store.S, v = $('#mainv');
    const done = S.rings.filter(g => g.state === 'done').length;
    v.innerHTML = `
      <div class="mv-top"><div><span class="kick">MAINLINE · 主线</span><h3>${esc(S.goal.text)}</h3><p><b>${done}</b> / ${S.rings.length} 环 · 起于 ${new Date(S.goal.at).getMonth() + 1} 月 ${new Date(S.goal.at).getDate()} 日</p></div><button class="xbtn" id="mvX">×</button></div>
      <div class="mv-detail" id="mvDetail"></div>
      <div class="mv-low"><button class="btn main" id="mvGo">让她派这一环</button><button class="btn ghost" id="mvNew">换目标</button></div>`;
    v.classList.add('on');
    const lab = $('#ringLabels'); lab.innerHTML = '';
    S.rings.forEach((g, i) => {
      const b = el('button', `rl ${g.state}${g.final ? ' final' : ''}`, `<i></i><b>${g.final ? '★' : 'R' + (i + 1)}</b><span>${esc(g.final ? S.goal.short : g.n)}</span>`);
      b.onclick = () => { Sound.play('tap'); this.detail(i); };
      lab.appendChild(b);
    });
    lab.classList.add('on');
    const cur = Store.curRing(), canGo = !S.active && cur >= 0 && S.queue.some(t => t.kind === 'main');
    $('#mvGo').style.display = canGo ? '' : 'none';
    $('#mvGo').onclick = () => { Sound.play('tap'); this.hide(); App.dispatch(); };
    $('#mvNew').onclick = () => { Sound.play('tap'); App.newGoal(); };
    $('#mvX').onclick = () => { Sound.play('tap'); this.hide(); App.lobby(); };
  },
  detail(i) {
    const S = Store.S, g = S.rings[i], d = $('#mvDetail');
    const st = g.state === 'done' ? `已完成 · ${new Date(g.doneAt).getMonth() + 1}/${new Date(g.doneAt).getDate()} · 用时 <b>${fmtDur(g.held || 0)}</b>` : g.state === 'cur' ? '<b>你在这一环</b>' : '未解锁';
    d.innerHTML = `<span class="kick">${g.final ? '终点 · 我头顶那一环' : 'RING ' + (i + 1)} · ${g.r} 级</span><h4>${esc(g.t)}</h4><p>${st}<br>证明：${esc(g.p)} · 时限 ${fmtMin(g.m)}</p>`;
    d.classList.add('on');
  },
  hide() {
    $('#mainv').classList.remove('on'); $('#ringLabels').classList.remove('on');
    setTimeout(() => { if (!$('#mainv').classList.contains('on')) { $('#mainv').innerHTML = ''; $('#ringLabels').innerHTML = ''; } }, 450);
  },
  place() { // 每帧：标签挂在每一环的右端
    const lab = $('#ringLabels'); if (!lab.classList.contains('on')) return;
    [...lab.children].forEach((b, i) => {
      const p = Stage.ringPoint(i, 1); if (!p) return;
      b.style.left = (p.x + 4) + 'px'; b.style.top = p.y + 'px';
    });
  },
};

/* ═══ 投影面板 ═══ */
const Sheet = {
  kind: null,
  open(kind) {
    this.kind = kind;
    const S = Store.S, body = $('#shBody');
    const T = { archive: ['ARCHIVE · 宿主档案', '档案'], supply: ['SUPPLY · 补给', '补给'], system: ['SYSTEM · 设置', '系统'] }[kind];
    $('#shK').textContent = T[0]; $('#shT').textContent = T[1];
    body.innerHTML = this[kind]();
    body.scrollTop = 0;
    $('#sheet').classList.add('on'); $('#beam').classList.add('on');
    this.wire(kind);
  },
  close() { $('#sheet').classList.remove('on'); $('#beam').classList.remove('on'); this.kind = null; },
  refresh() { if (this.kind) { const st = $('#shBody').scrollTop; $('#shBody').innerHTML = this[this.kind](); this.wire(this.kind); $('#shBody').scrollTop = st; } },

  radar(attrs) {
    const R = 92, cx = 150, cy = 120, ks = ATTRS.map(a => a.k);
    const max = Math.max(10, ...ks.map(k => attrs[k]));
    const pt = (i, r) => { const a = -Math.PI / 2 + i * Math.PI / 3; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; };
    const poly = r => ks.map((_, i) => pt(i, r).map(v => v.toFixed(1)).join(',')).join(' ');
    const weak = Store.weakest().k;
    let s = `<svg class="radar" viewBox="0 0 300 245">`;
    [.25, .5, .75, 1].forEach(f => { s += `<polygon class="gridp" points="${poly(R * f)}"/>`; });
    ks.forEach((_, i) => { const [x, y] = pt(i, R); s += `<line class="axis" x1="${cx}" y1="${cy}" x2="${x}" y2="${y}"/>`; });
    const vals = ks.map((k, i) => pt(i, R * Math.sqrt(attrs[k] / max)));
    s += `<polygon class="shape" points="${vals.map(p => p.map(v => v.toFixed(1)).join(',')).join(' ')}"/>`;
    ks.forEach((k, i) => {
      const [x, y] = pt(i, R + 22), [vx, vy] = vals[i];
      s += `<circle class="vx" cx="${vx}" cy="${vy}" r="2.2"/>`;
      s += `<text x="${x}" y="${y - 7}" class="${k === weak ? 'weak' : ''}">${ATTR_NAME[k]}</text><text x="${x}" y="${y + 9}" class="v">${attrs[k]}</text>`;
    });
    return s + '</svg>';
  },
  archive() {
    const S = Store.S, st = S.stats;
    return `
      <div class="ar-top"><div class="ar-lv"><small>LV</small>${S.lv}</div>
        <div class="ar-exp"><p><span>EXP</span><span><b>${S.exp}</b> / ${need(S.lv)}</span></p><div class="rs-bar"><i style="width:${S.exp / need(S.lv) * 100}%"></i></div>
        <p style="margin-top:8px"><span>称号</span><span style="color:var(--blue);font-family:var(--f-cn);letter-spacing:0">「${esc(Store.title)}」</span></p></div></div>
      <div class="sec"><span class="kick">六维 · 平方根刻度</span>${this.radar(S.attrs)}</div>
      <div class="sec"><span class="kick">战绩</span><div class="stats">
        <div><b>${st.done}</b><small>完成</small></div><div><b>${st.crit}</b><small>暴击</small></div>
        <div><b>${st.fail}</b><small>认输</small></div><div><b>${S.bestStreak}</b><small>最长连击</small></div></div></div>
      <div class="sec"><span class="kick">称号 · 点一下挂上</span><div class="titles">${TITLES.map(t => {
        const has = S.titles.includes(t.id);
        return `<button data-t="${t.id}" class="${has ? (S.title === t.id ? 'eq' : '') : 'lock'}${t.shame && has ? ' shame' : ''}">${has ? esc(t.name) : '？？？ · ' + esc(t.hint)}</button>`;
      }).join('')}</div></div>
      <div class="sec"><span class="kick">道具</span><div class="inv">${Object.entries(ITEMS).map(([k, it]) => `<div><span class="glyph">${it.glyph}</span><span><b>${it.name}</b><small>×${S.items[k]}</small></span></div>`).join('')}</div></div>`;
  },
  supply() {
    const S = Store.S;
    return `<div class="sec" style="margin-top:6px"><span class="kick">金币 ◈ ${S.coins} · 只能花在这</span><div class="shop">${Object.entries(ITEMS).map(([k, it]) => `
      <div class="row"><span class="glyph">${it.glyph}</span><div><b>${it.name}<em>持有 ×${S.items[k]}</em></b><p>${esc(it.desc)}</p></div>
      <button class="buy" data-buy="${k}" ${S.coins < it.price ? 'disabled' : ''}>${COIN_SVG}${it.price}</button></div>`).join('')}</div></div>`;
  },
  system() {
    const seg = (key, opts, cur) => `<div class="seg" data-seg="${key}">${opts.map(([v, t]) => `<button data-v="${v}" class="${v === cur ? 'on' : ''}">${t}</button>`).join('')}</div>`;
    const ST = App.settings;
    return `<div class="set">
      <div class="row"><span>音效<small>全部现场合成，没有音频文件</small></span>${seg('sound', [['1', '开'], ['0', '关']], ST.sound ? '1' : '0')}</div>
      <div class="row"><span>她的声音<small>人声用浏览器自带中文语音，效果看设备</small></span>${seg('voice', [['blip', '电子音'], ['tts', '人声'], ['mute', '静音']], Voice.mode)}</div>
      <div class="row"><span>震动<small>仅安卓浏览器有效</small></span>${seg('haptic', [['1', '开'], ['0', '关']], ST.haptic ? '1' : '0')}</div>
      <div class="row"><span>全息描边<small>她身上的电光轮廓；低端机可关</small></span>${seg('holo', [['1', '开'], ['0', '关']], ST.holo ? '1' : '0')}</div>
      <div class="row"><span>重置存档<small>一切从绑定重新开始</small></span><button class="danger" id="wipe"><i></i><span>按住 2 秒</span></button></div>
    </div><p class="about">SYSTEM · opus-v2-dir<br>她派任务，你去现实里做，拍下证据，她结算。<br>存档只在这台设备的浏览器里。</p>`;
  },
  wire(kind) {
    const body = $('#shBody');
    if (kind === 'archive') body.querySelectorAll('.titles button').forEach(b => b.onclick = () => {
      if (Store.equip(b.dataset.t)) { Sound.play('choose'); HUD.render(); this.refresh(); Line.say(line('equip'), { emo: 'smug', hold: 1400 }); }
      else { Sound.play('deny'); if (Store.S.title === 'mouth') Line.say('「口头巨人」摘不掉。完成一单再说。', { emo: 'smug', hold: 1800 }); }
    });
    if (kind === 'supply') body.querySelectorAll('[data-buy]').forEach(b => b.onclick = () => {
      const k = b.dataset.buy;
      if (Store.buy(k)) {
        Sound.play('coin'); FX.burst(rel(b).cx, rel(b).cy, { n: 18, max: 200, life: .6 }); HUD.coin(Store.S.coins); this.refresh();
        Line.say(line('bought'), { emo: 'smug', hold: 1300 });
        if ($('#exec').classList.contains('on')) Exec.slots();
      } else { Sound.play('deny'); Line.say(line('poor'), { emo: 'cold', hold: 1600 }); }
    });
    if (kind === 'system') {
      body.querySelectorAll('[data-seg]').forEach(s => s.onclick = e => {
        const b = e.target.closest('button'); if (!b) return;
        App.setSetting(s.dataset.seg, b.dataset.v); Sound.play('tap'); this.refresh();
      });
      const w = $('#wipe'); let p = 0, h = false, raf = 0, last = 0;
      const step = now => {
        const dt = (now - last) / 1000; last = now; p = clamp(p + (h ? dt / 2 : -dt), 0, 1);
        w.querySelector('i').style.width = p * 100 + '%';
        if (p >= 1) { Store.wipe(); location.reload(); return; }
        raf = (h || p > 0) ? requestAnimationFrame(step) : 0;
      };
      w.onpointerdown = e => { e.preventDefault(); h = true; last = performance.now(); if (!raf) raf = requestAnimationFrame(step); };
      w.onpointerup = w.onpointerleave = () => { h = false; };
    }
  },
};

/* 投影光束：从她胸口打到面板上沿 */
const Beam = {
  place() {
    if (!$('#beam').classList.contains('on')) return;
    const c = Stage.toScreen(0, NY.chest + .02), s = rel($('#sheet'));
    const l = s.x + 10, r = s.x + s.w - 10, y = s.y;
    $('#beamPoly').setAttribute('points', `${c.x},${c.y} ${r},${y} ${l},${y}`);
    const L = $('#beamL'), R = $('#beamR');
    L.setAttribute('x1', c.x); L.setAttribute('y1', c.y); L.setAttribute('x2', l); L.setAttribute('y2', y);
    R.setAttribute('x1', c.x); R.setAttribute('y1', c.y); R.setAttribute('x2', r); R.setAttribute('y2', y);
  },
};
