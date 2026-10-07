/* ═══════════════════════════════════════════════════════════
   flows.js — 导演：每一个时刻的编排
   开机 → 绑定 → 回来的招呼 → 大厅 → 派单 → 执行 → 结算 / 认输 → 主线 / 面板
   ═══════════════════════════════════════════════════════════ */
'use strict';

const App = {
  mode: 'boot', busy: false, settings: { sound: true, haptic: true, holo: true },
  lastAct: 0, nextIdle: 0, hiddenAt: 0,

  setMode(m) {
    this.mode = m;
    if (this.dozing && m !== 'lobby') { this.dozing = false; Stage.holoTo({ bright: 1 }); Sound.ambient(1, 1); }
    const a = $('#app');
    const cls = { boot: ['booting'], onboard: ['focus'], lobby: [], dispatch: ['focus', 'dim'], exec: ['panel'], result: ['focus', 'dim'], fail: ['focus', 'fail'], main: ['focus'], sheet: ['focus'] }[m] || [];
    ['booting', 'focus', 'dim', 'panel', 'fail'].forEach(c => a.classList.toggle(c, cls.includes(c)));
    $('#ringTag').classList.toggle('on', m === 'lobby' && Store.curRing() >= 0);
    Stage.ringAT = { exec: .3, sheet: .45, result: .8 }[m] ?? 1;
    Dock.render();
  },
  lineAt(m) {
    const H = Stage.H;
    const y = { lobby: H * .6, onboard: H * .55, dispatch: H < 740 ? H - 390 - 100 : H - 448 - 120, exec: H * .615, result: H - 230, fail: H * .47, main: H - 192, sheet: H * .38 - 104 }[m] ?? H * .6;
    Line.at(y);
  },
  async run(fn) {
    if (this.busy) return; this.busy = true;
    try { await fn(); } catch (e) { console.error(e); } finally { this.busy = false; }
  },

  /* ═══ 开机：先是一个待机中的她，触碰后醒来 ═══ */
  async boot() {
    this.setMode('boot');
    const log = $('#btLog'), bar = $('#btBar');
    const add = (t) => { const d = el('div', '', '› ' + t.replace(/✓/g, '<b>✓</b>')); log.appendChild(d); while (log.children.length > 5) log.firstChild.remove(); };
    const clk = setInterval(() => { $('#btClock').textContent = new Date(Clock.now()).toTimeString().slice(0, 8); }, 500);
    let tip = 0; const tips = () => { $('#btTip').textContent = LINES.tips[tip++ % LINES.tips.length]; };
    tips(); const tipIv = setInterval(tips, 3200);
    const S = Store.S;
    const fonts = Promise.all(['16px FangYuan', '16px ShuHei', '16px Tektur', '16px KodeMono'].map(f => document.fonts.load(f, '宿主系统SYSTEM0123'))).catch(() => { });
    add('SYS//BOOT · 链路建立'); bar.style.width = '8%';
    await fonts; add('字形载入 ✓'); bar.style.width = '18%';
    let ok = true;
    try {
      await Stage.init($('#stage'), (p, t) => { bar.style.width = (18 + p * 70) + '%'; if (t) add(t); });
    } catch (e) {
      ok = false; console.warn(e); add('模型未找到 · 以无形态运行');
    }
    this.stageOK = ok;
    add(LINES.bootLog[0]); await sleep(160);
    add(LINES.bootLog[2]); await sleep(160);
    add(tpl(LINES.bootLog[3], { host: S.bound ? `${S.name} · LV${S.lv}` : '未找到 · 新宿主' }));
    bar.style.width = '100%';
    if (ok) {
      Stage.emote('sleep'); Stage.look('down');
      Stage.holoTo({ sat: .12, bright: .34, rim: .32, scan: .65, lift: 1 }); Object.assign(Stage.fx, Stage.fxT);
      Stage.scanT = 1;
      if (S.bound) Stage.setRings(S.rings), Stage.hideRings();
      $('#stageCv').style.opacity = 0; $('#stageCv').style.transition = 'opacity 1.6s';
      requestAnimationFrame(() => { $('#stageCv').style.opacity = 1; });
    }
    this.setWord('SYSTEM', true);
    await sleep(500); add(LINES.bootLog[4]);
    $('#boot').classList.add('ready');
    await new Promise(r => $('#boot').addEventListener('pointerdown', r, { once: true }));
    clearInterval(tipIv); clearInterval(clk);
    await this.wake();
  },

  async wake() {
    Sound.init(); Sound.setOn(this.settings.sound); Sound.play('boot');
    setTimeout(() => Sound.ambient(1, 3), 600);
    buzz([10, 60, 20]);
    FX.flash('#9ff0ff', .26, 520);
    $('#boot').classList.add('gone');
    Stage.scanT = 0; Stage.scan = 0;
    Stage.glitch(420, 1);
    Stage.holoTo({ sat: 1, bright: 1, rim: this.settings.holo ? .55 : 0, scan: this.settings.holo ? .2 : 0, lift: .5 });
    const S = Store.S;
    // 睁眼：先抬头，眼皮颤两下再睁开
    Stage.faceT.ay = 0; Stage.faceT.az = 0; Stage.faceT.cheek = -.3;
    await sleep(450);
    Stage.faceT.lid = .35; await sleep(140); Stage.faceT.lid = .05; await sleep(120);
    Stage.emote('neutral'); Stage.look('user');
    Stage.setCam(S.bound ? 'lobby' : 'talk');
    if (S.bound) {
      this.setWord(S.goal?.short || 'SYSTEM');
      for (let i = 0; i < S.rings.length; i++) {
        const g = S.rings[i];
        Stage.showRing(i);
        if (g.state !== 'lock') { Stage.igniteRing(i); Sound.play('ignite', i); }
        await sleep(g.state === 'lock' ? 50 : 140);
      }
    } else this.setWord('', false);
    await sleep(500);
    if (!S.bound) return this.onboard();
    HUD.render();
    return this.greet(true);
  },

  /* ═══ 首次绑定 ═══ */
  async onboard() {
    this.setMode('onboard'); this.lineAt('onboard');
    await Line.say(line('wake0'), { emo: 'neutral', speed: 260, hold: 300 });
    await Line.say(line('wake1'), { emo: 'focus' });
    Stage.look({ x: Stage.W / 2, y: Stage.H * 1.1 }); await sleep(650); Stage.look({ x: Stage.W / 2, y: -40 }); await sleep(420); Stage.look('user');
    await Line.say(line('wake2'), { emo: 'smug' });
    const a = await choose([{ t: '就我。', v: 'me' }, { t: '你是谁？', v: 'who' }]);
    if (a === 'me') await Line.say(line('wakeYes'), { emo: 'smug' });
    else {
      await Line.say(line('wakeWho'), { emo: 'focus' });
      const b = await choose([{ t: '……统子？', v: 'tz' }, { t: '好的，系统。', v: 'ok' }]);
      if (b === 'tz') {
        Store.S.tongzi++;
        Stage.motion('fluster');
        await Line.say(LINES.tongzi[0], { emo: 'tsun' });
        await Line.say(LINES.tongzi[1], { emo: 'annoyed' });
      } else await Line.say(line('tongziOk'), { emo: 'smug' });
    }
    await Line.say(line('askName'), { emo: 'neutral', hold: 300 });
    const name = (await askText({ ps: '名字 ›', ph: '怎么称呼你', def: '' })).slice(0, 12) || '宿主';
    await Line.say(line('gotName', { name }), { emo: 'smug' });
    let plan;
    for (let tries = 0; ; tries++) {
      await Line.say(tries ? line('newGoal') : line('askGoal'), { emo: 'focus', hold: 300 });
      const goal = await askText({ ps: '目标 ›', ph: '比如：三个月跑完半马', presets: ['三个月跑完半马', '一个月早睡早起', '考研上岸', '半年减重 10 斤', '学会画画', '变优秀'] });
      plan = Store.makeGoal(goal);
      if (!plan.vague) break;
      Stage.motion('poke');
      await Line.say(line('vague', { goal }), { emo: 'annoyed' });
    }
    await Line.say(line('decomp'), { emo: 'focus', motion: 'think', hold: 500 });
    await this.assemble(plan);
    await Line.say(line('ringsDone', { n: plan.rings.length }), { emo: 'smug', look: 'up' });
    Stage.look('user');
    const c = await choose([{ t: '够得着。', v: 'y' }, { t: '……试试吧。', v: 't' }]);
    await Line.say(line(c === 'y' ? 'ringsBrave' : 'ringsTry'), { emo: c === 'y' ? 'pleased' : 'smug' });
    Store.bind(name, plan);
    HUD.render();
    Stage.setCam('lobby'); this.setMode('lobby'); this.lineAt('lobby');
    $('#app').classList.add('panel');
    Banner.show('见面礼', '双倍卡 ×1', '×2');
    await Line.say(line('gift'), { emo: 'tsun' });
    await Line.say(line('firstGo'), { emo: 'focus', hold: 600 });
    return this.dispatch(true);
  },
  /* 目标拆成环：环一圈一圈从脚下挂到头顶 */
  async assemble(plan) {
    Line.hide();
    Stage.setCam('full'); Stage.setRings(plan.rings); Stage.hideRings();
    this.setWord(plan.goal.short, true);
    await sleep(700);
    const tags = this._asm = [];
    for (let i = 0; i < plan.rings.length; i++) {
      Stage.showRing(i); Stage.igniteRing(i); Sound.play('ignite', i); buzz(6);
      const g = plan.rings[i];
      const t = el('div', 'assemble-tag', `<b>${g.final ? '★' : 'R' + (i + 1)}</b>${esc(g.final ? plan.goal.short : g.n)}`);
      $('#ui').appendChild(t); tags.push({ el: t, i });
      await sleep(g.final ? 200 : 260);
    }
    const halo = Stage.ringPoint(plan.rings.length - 1, 0);
    FX.burst(halo.x, halo.y, { n: 40, max: 320, life: 1 }); FX.flash('#9ff0ff', .12, 300);
    this.lineAt('main');
    await sleep(900);
    tags.forEach(t => { t.el.style.transition = 'opacity .5s'; t.el.style.opacity = 0; });
    setTimeout(() => { tags.forEach(t => t.el.remove()); if (this._asm === tags) this._asm = null; }, 600);
  },

  /* ═══ 回来：她记得你走了多久 ═══ */
  async greet(fromBoot) {
    if (this.busy) return;
    this.busy = true;
    try { return await this._greet(fromBoot); } finally { this.busy = false; }
  },
  async _greet(fromBoot) {
    const S = Store.S;
    Plate.clear(); Exec.hide(); ResultUI.hide(); MainV.hide(); Sheet.close();
    this.setMode('lobby'); this.lineAt('lobby'); Stage.setCam('lobby'); Stage.look('user');
    $('#app').classList.add('panel');
    const mood = Store.mood(); Stage.setIdle(mood);
    const away = Clock.now() - (S.prevSeen || Clock.now());
    S.prevSeen = Clock.now();
    const say = (t, o) => Line.say(t, o);
    const roll = this._roll;
    this._roll = null;
    if (fromBoot || away > 6e4) {
      let k = 'back10m';
      if (away > 48 * 36e5) k = 'backLong'; else if (away > 20 * 36e5) k = 'back36h'; else if (away > 2 * 36e5) k = 'back12h'; else if (away > 10 * 6e4) k = 'back2h';
      await say(line(k, { dur: fmtDur(away), days: Math.round(away / 864e5) }), { emo: mood === 'cold' ? 'cold' : k === 'back10m' ? 'smug' : 'neutral' });
    }
    if (roll && roll.broke) await say(line('streakBroken', { was: roll.broke }), { emo: 'sad' });
    else if (mood === 'cold') await say(line('coldGreet'), { emo: 'cold' });
    else if (S.streak > 0 && S.lastDoneDay !== dayKey() && new Date(Clock.now()).getHours() >= 18) await say(line('streakRisk', { streak: S.streak }), { emo: 'focus' });
    if (S.active) {
      await say('计时没停。[[' + esc(S.active.task.name) + ']]——还在等你。', { emo: 'focus' });
      return this.exec();
    }
    if (S.remedyOffer) await say(`补救还开着：[[${esc(S.remedyOffer.name)}]]。`, { emo: 'neutral' });
    if (S.queue.length) {
      await say(line('holding', { n: S.queue.length }), { emo: mood === 'pleased' ? 'pleased' : 'smug' });
      const v = await choose([{ t: '有单吗？给我。', v: 'go', main: true }, { t: '……就看看你。', v: 'look' }]);
      if (v === 'go') return this.dispatch(true);
      Stage.motion('fluster');
      await say(line('justLook'), { emo: 'tsun' });
    } else if (S.hint) await say(line('hintTomorrow', { r: S.hint.r }), { emo: 'smug' });
    Line.hide();
    return this.lobby();
  },

  /* ═══ 大厅 ═══ */
  lobby() {
    const S = Store.S;
    Plate.clear(); Exec.hide(); ResultUI.hide(); MainV.hide(); Sheet.close();
    $('#failv').classList.remove('on'); $('#veil').style.opacity = 0;
    this.setMode('lobby'); this.lineAt('lobby');
    Stage.setCam('lobby'); Stage.look('pointer');
    const mood = Store.mood(); Stage.setIdle(mood);
    Stage.emote({ cold: 'cold', pleased: 'pleased' }[mood] || 'neutral');
    if (S.rings.length) Stage.setRings(S.rings);
    const ci = Store.curRing();
    if (ci >= 0) { $('#rtNum').innerHTML = `R${ci + 1}<small>/${S.rings.length}</small>`; $('#rtName').textContent = S.rings[ci].final ? S.goal.short : S.rings[ci].n; }
    HUD.render();
    this.nextIdle = performance.now() + rand(16000, 26000);
  },

  /* ═══ 派单：她把这一单刻给你 ═══ */
  async dispatch(inFlow) {
    const go = async () => {
      const S = Store.S;
      if (S.active) { await Line.say(line('busy'), { emo: 'smug' }); return this.exec(); }
      const T = Store.head();
      if (!T) { await Line.say(line('empty'), { emo: 'smug' }); return this.lobby(); }
      Line.hide(); Sheet.close(); MainV.hide();
      this.setMode('dispatch'); this.lineAt('dispatch');
      Stage.setCam('talk'); Stage.emote('focus'); Stage.look('user'); Stage.motion('present');
      Plate.fast = S.stats.dispatched >= 3;
      Sound.play('ding'); buzz(12);
      await Line.say(line('ding'), { emo: 'focus', speed: 80, hold: 260 });
      Plate.build(T);
      await Plate.land();
      Line.say(T.kind === 'main' ? line('forYouMain', { i: T.ring + 1 }) : T.kind === 'remedy' ? line('forYouRemedy') : line('callName', { name: S.name }), { emo: 'focus', hold: 200 });
      await Plate.rankRoll(T.r);
      const ri = RARITY[T.r].i;
      if (ri >= 5) { Stage.motion('surprise'); Stage.emote('surprised'); setTimeout(() => Stage.emote('focus'), 900); }
      await Promise.all([
        Plate.engrave(),
        (async () => { await sleep(250); await Line.say(line('rank.' + T.r), { emo: ri <= 1 ? 'smug' : ri >= 6 ? 'proud' : 'focus', hold: 400 }); })(),
      ]);
      // 宿主回应：按住指纹 = 接下；别的选择都要对她说出口
      for (; ;) {
        Line.say(line('ask'), { emo: 'focus', hold: 99999 });
        const alts = [{ t: '换一个', v: 'retreat' }, { t: '等会儿', v: 'later' }];
        if (S.items.swap > 0 && T.kind === 'daily') alts.unshift({ t: `用换单券（×${S.items.swap}）`, v: 'swap' });
        Plate.alt(alts, v => Plate.cancelHold(v));
        const v = await Plate.hold();
        Plate.hideAlt();
        if (v === 'accept') {
          Store.accept(T);
          const ci = Store.curRing();
          const pt = T.kind === 'main' && ci >= 0 ? Stage.ringPoint(ci, 1) : Stage.toScreen(0, NY.chest);
          Line.hide();
          await Plate.seal(pt);
          if (T.kind === 'main' && ci >= 0) { Stage.igniteRing(ci); Sound.play('ignite', ci); }
          await Line.say(line('accept'), { emo: 'smug', motion: 'nod', hold: 900 });
          return this.exec();
        }
        if (v === 'later') {
          Store.later();
          await Plate.back();
          await Line.say(line('later'), { emo: 'cold', hold: 1500 });
          Line.hide();
          return this.lobby();
        }
        if (v === 'swap') {
          const nt = Store.swap(T);
          await Line.say(line('swapUsed'), { emo: 'smug', hold: 900 });
          nt.reason = Store.reasonFor(nt);
          Plate.build(nt); $('#plate').classList.add('on'); $('#plate').style.opacity = 1;
          await Plate.rankRoll(nt.r); await Plate.engrave();
          return this._dispatchLoop(nt);
        }
        if (v === 'retreat') {
          const from = T.r;
          const info = Store.retreat(T);
          const k = info.n >= 3 ? 'retreat3' : info.n === 2 ? 'retreat2' : 'retreat1';
          Stage.motion(info.n >= 2 ? 'down' : 'poke');
          const sayP = Line.say(line(k, { n: info.n }), { emo: info.n >= 2 ? 'cold' : 'annoyed', hold: 700 });
          if (Store.S.queue[0] !== T) { // F 级还退：直接换一张
            const nt = Store.S.queue[0]; nt.reason = Store.reasonFor(nt);
            await sayP; Plate.build(nt); $('#plate').classList.add('on'); $('#plate').style.opacity = 1;
            await Plate.rankRoll(nt.r); await Plate.engrave();
            if (info.shame) await this.shame();
            return this._dispatchLoop(nt);
          }
          await Promise.all([sayP, Plate.reRank(T, from)]);
          if (info.shame) await this.shame();
          continue;
        }
      }
    };
    if (inFlow === true) { this.busy = true; try { await go(); } finally { this.busy = false; } }
    else await this.run(go);
  },
  async _dispatchLoop(T) { // 换过单之后的回应循环（同上，少一层）
    for (; ;) {
      Line.say(line('ask'), { emo: 'focus', hold: 99999 });
      Plate.alt([{ t: '换一个', v: 'retreat' }, { t: '等会儿', v: 'later' }], v => Plate.cancelHold(v));
      const v = await Plate.hold(); Plate.hideAlt();
      if (v === 'accept') {
        Store.accept(T); Line.hide();
        await Plate.seal(Stage.toScreen(0, NY.chest));
        await Line.say(line('accept'), { emo: 'smug', motion: 'nod', hold: 900 });
        return this.exec();
      }
      if (v === 'later') { await Plate.back(); await Line.say(line('later'), { emo: 'cold', hold: 1500 }); Line.hide(); return this.lobby(); }
      const from = T.r, info = Store.retreat(T);
      await Promise.all([Line.say(line(info.n >= 3 ? 'retreat3' : info.n === 2 ? 'retreat2' : 'retreat1', { n: info.n }), { emo: 'cold', hold: 700 }),
        Store.S.queue[0] === T ? Plate.reRank(T, from) : Promise.resolve()]);
      if (Store.S.queue[0] !== T) { T = Store.S.queue[0]; T.reason = Store.reasonFor(T); Plate.build(T); $('#plate').classList.add('on'); $('#plate').style.opacity = 1; await Plate.rankRoll(T.r); await Plate.engrave(); }
      if (info.shame) await this.shame();
    }
  },
  async shame() {
    HUD.render();
    await Banner.show('称号 · 强制佩戴', '口头巨人', '!');
    await Line.say(line('titleShame', { t: '口头巨人' }), { emo: 'smug', hold: 1200 });
  },

  /* ═══ 执行：她盯着你 ═══ */
  exec() {
    const S = Store.S; if (!S.active) return this.lobby();
    Line.hide(); Plate.clear(); MainV.hide(); Sheet.close();
    this.setMode('exec'); this.lineAt('exec');
    Stage.setCam('exec'); Stage.emote('focus'); Stage.look({ x: Stage.W * .26, y: Stage.H * .22 });
    Stage.setIdle('neutral');
    Exec._timeout = false;
    Exec.show();
    HUD.render();
    this.nextComment = performance.now() + rand(22000, 34000);
  },
  async snap() {
    const S = Store.S, A = S.active; if (!A || A.photos.length >= 3) return;
    const inp = $('#filePick'); inp.value = '';
    const file = await new Promise(r => { inp.onchange = () => r(inp.files[0]); inp.click(); });
    if (!file) return;
    const url = await new Promise(r => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(file); });
    const img = await new Promise(r => { const i = new Image(); i.onload = () => r(i); i.onerror = () => r(null); i.src = url; });
    let data = url;
    if (img) {
      const k = Math.min(1, 520 / Math.max(img.width, img.height)), c = document.createElement('canvas');
      c.width = Math.round(img.width * k); c.height = Math.round(img.height * k); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      data = c.toDataURL('image/jpeg', .7);
    }
    A.photos.push(data); Store.save();
    Sound.play('shutter'); buzz(10);
    Exec.slots(); Exec.crit();
    const s = $$('#exSlots .slot')[A.photos.length - 1];
    if (s) { const r = rel(s); FX.burst(r.cx, r.cy, { n: 16, max: 160, life: .5 }); }
    Stage.look('read'); setTimeout(() => this.mode === 'exec' && Stage.look({ x: Stage.W * .26, y: Stage.H * .22 }), 900);
    Line.say(line('photo', { p: Math.round(Store.critChance() * 100) }), { emo: 'neutral', hold: 1500 });
  },
  submit() { return this.run(() => this.settle()); },

  /* ═══ 结算：一秒钟的"给" ═══ */
  async settle() {
    const S = Store.S; if (!S.active) return;
    const slotPts = $$('#exSlots .slot.full').map(rel);
    const res = Store.settle();
    const T = res.task, R = RARITY[T.r], ri = R.i;
    Exec.hide(); Line.hide();
    this.setMode('result'); this.lineAt('result');
    Stage.setCam('result'); Stage.emote('focus'); Stage.look('read');
    const hurry = { on: false }; Tap.next().then(() => { hurry.on = true; });
    const w = async ms => { const t0 = performance.now(); while (performance.now() - t0 < ms && !hurry.on) await sleep(25); };
    // ① 验收：证据飞进她手里，她扫一眼
    Sound.play('scan');
    const chest = Stage.toScreen(0, NY.chest);
    slotPts.forEach((p, i) => setTimeout(() => FX.streak(p.cx, p.cy, chest.x, chest.y, { ms: 420, w: 2 }), i * 90));
    const scan = el('div', '', ''); scan.style.cssText = 'position:absolute;left:0;right:0;height:2px;top:8%;background:linear-gradient(90deg,transparent,#9ff0ff,transparent);box-shadow:0 0 18px #38e1ff;pointer-events:none;z-index:3';
    $('#ui').appendChild(scan);
    scan.animate([{ top: '6%', opacity: 0 }, { opacity: 1, offset: .15 }, { top: '58%', opacity: 0 }], { duration: 780, easing: 'cubic-bezier(.4,0,.2,1)' });
    setTimeout(() => scan.remove(), 800);
    await w(820);
    // ② 落定：稀有度砸下来
    ResultUI.build(res);
    $('#rsGlyph').classList.add('on');
    Sound.play('impact'); FX.flash('#ffffff', .16, 180); FX.shake(ri >= 4 ? 7 : 4, 280); buzz(ri >= 4 ? [40, 30, 60] : 30);
    Stage.shock(ri >= 3 ? parseInt(R.c.slice(1), 16) : 0x38e1ff, NY.waist, 1);
    setTimeout(() => Stage.shock(0x38e1ff, NY.chest, .7), 120);
    if (ri >= 4) { Stage.rim('#bff6ff'); Stage.holoTo({ rim: .95 }); setTimeout(() => { Stage.rim('#38e1ff'); Stage.holoTo({ rim: this.settings.holo ? .55 : 0 }); }, 1800); }
    Stage.glitch(160, .5);
    const g = rel($('#rsGlyph'));
    FX.burst(g.cx, g.cy, { n: 36 + ri * 16, cols: [R.c, '#38e1ff', '#e9fbff', '#38e1ff', '#7fdcff'], max: 300 + ri * 70, life: 1.2 + ri * .08 });
    Stage.emote(ri >= 5 ? 'surprised' : 'focus'); Stage.look('user');
    if (ri >= 5) Stage.motion('surprise');
    await w(380);
    $('#rsHead').classList.add('on'); await w(180);
    $('#rsCard').classList.add('on'); await w(160);
    // ③ 数字往上跳
    const exp = $('#rsExp');
    const count = async (from, to, ms) => {
      if (hurry.on) { exp.textContent = to; return; }
      let lastTick = 0;
      await tween(ms, k => { const v = Math.round(lerp(from, to, k)); exp.textContent = v; const n = performance.now(); if (n - lastTick > 55) { lastTick = n; Sound.play('count'); } });
      exp.textContent = to;
    };
    await count(0, res.baseExp, 800);
    let cur = res.baseExp;
    if (res.crit) {
      await w(200);
      $('#rsTags').appendChild(el('span', 'stamp', 'CRIT ×2'));
      Sound.play('crit'); FX.flash('#e9fbff', .14, 200); FX.shake(5, 220); buzz([20, 20, 40]);
      Stage.motion('surprise');
      await count(cur, cur * 2, 520); cur *= 2;
    }
    if (res.dbl) {
      await w(160);
      $('#rsTags').appendChild(el('span', 'stamp dbl', '双倍卡 ×2'));
      Sound.play('crit');
      await count(cur, res.exp, 480);
    }
    // ④ 经验条：跨级 = 涨满 → 白闪 → 归零再涨
    await this.expBar(res, hurry);
    // ⑤ 金币 / 属性 / 连击
    await w(120);
    ResultUI.chip(`${COIN_SVG}<b>+${res.coin}</b>`, 'coin'); Sound.play('coin'); HUD.coin(Store.S.coins);
    for (const [k, v] of Object.entries(res.attrs)) { await w(110); ResultUI.chip(`${ATTR_NAME[k]} <b>+${v}</b>`); Sound.play('count'); }
    if (res.streakUp) { await w(110); ResultUI.chip(`连击 <b>${res.streak}</b> 天`); }
    if (res.near) $('#rsNear').innerHTML = `暴击判定：差 <b>${res.near}%</b>。下次多拍一张证据。`, $('#rsNear').classList.add('on');
    else if (!res.crit && !res.photos) $('#rsNear').innerHTML = '本单 0 份证据 · 暴击率只有 <b>' + Math.round(res.chance * 100) + '%</b>', $('#rsNear').classList.add('on');
    HUD.render();
    // ⑥ 主线：这一环亮起来
    if (res.ringClear >= 0) {
      Stage.setRings(Store.S.rings);
      Stage.igniteRing(res.ringClear); Sound.play('ignite', res.ringClear);
      const nx = res.ringClear + 1;
      if (nx < Store.S.rings.length) setTimeout(() => Stage.igniteRing(nx), 420);
    }
    $('#rsSave').classList.add('on');
    $('#rsSave').onclick = () => { Sound.play('tap'); this.shareCard(res, this._lastLine || ''); };
    // ⑦ 她开口
    const tier = ri <= 1 ? 'low' : ri <= 3 ? 'mid' : ri <= 5 ? 'high' : 'top';
    const emo = { low: 'smug', mid: 'pleased', high: 'tsun', top: 'tsun' }[tier];
    if (tier === 'high' || tier === 'top' || res.crit) Stage.motion(tier === 'top' ? 'cheer' : 'happy');
    let first = res.tooFast ? line('tooFast', { s: Math.max(1, Math.round(res.held / 1000)) }) : res.crit ? line('crit') : line('settle.' + tier);
    this._lastLine = plain(first);
    await Line.say(first, { emo: res.tooFast ? 'smug' : res.crit ? 'proud' : emo, hold: 1300 });
    if (res.crit && !res.tooFast) await Line.say(line('settle.' + tier), { emo, hold: 1200 });
    if (!res.photos && !res.tooFast && !res.crit) await Line.say(line('noPhoto'), { emo: 'smug', hold: 1100 });
    if (res.ringClear >= 0 && !res.finale) await Line.say(line('ringClear', { i: res.ringClear + 1 }), { emo: 'pleased', look: 'up', hold: 1200 });
    if (res.redeemed) await Line.say(line('redeemed'), { emo: 'pleased' });
    if (res.unshamed) await Line.say('「口头巨人」，摘了。别让我再给你挂上。', { emo: 'smug' });
    if (!res.finale) for (const t of res.titles) { Banner.show('称号解锁', TITLE_BY[t].name, '✦'); }
    if (res.titles.length) await Line.say(line('title', { t: TITLE_BY[res.titles[res.titles.length - 1]].name }), { emo: 'smug', hold: 1300 });
    if (res.finale) return this.finale();
    if (res.empty) {
      await Line.say(line('clearAll'), { emo: 'pleased', hold: 900 });
      if (res.hint) await Line.say(line('hintTomorrow', { r: res.hint.r }), { emo: 'smug' });
    }
    Stage.emote(Store.mood() === 'pleased' ? 'pleased' : 'smug');
    const more = Store.S.queue.length > 0;
    const v = await choose(more ? [{ t: '再来一单。', v: 'next', main: true }, { t: '先歇会儿。', v: 'rest' }] : [{ t: '收工。', v: 'rest', main: true }]);
    ResultUI.hide(); Line.hide();
    if (v === 'next') { this.busy = false; return this.dispatch(); }
    return this.lobby();
  },
  async expBar(res, hurry) {
    const bar = $('#rsBarI'), wrap = $('#rsBar'), lv = $('#rsLv'), nd = $('#rsNeed');
    const to = (pct, ms) => new Promise(r => {
      if (hurry.on) { bar.style.transition = 'none'; bar.style.width = pct + '%'; return r(); }
      bar.style.transition = `width ${ms}ms cubic-bezier(.16,1,.3,1)`; bar.style.width = pct + '%'; setTimeout(r, ms);
    });
    let L = res.before.lv;
    for (const up of res.ups) {
      await to(100, 360);
      wrap.classList.add('flash'); setTimeout(() => wrap.classList.remove('flash'), 220);
      L = up; lv.textContent = L; lv.parentElement.classList.add('up');
      if (up === res.ups[0]) await this.levelUp(up);
      bar.style.transition = 'none'; bar.style.width = '0%'; void bar.offsetWidth;
    }
    nd.textContent = `${res.after.exp} / ${res.after.need}`;
    await to(res.after.exp / res.after.need * 100, res.ups.length ? 420 : 520);
  },
  async levelUp(lv) {
    Sound.play('levelup'); FX.flash('#e9fbff', .2, 260); buzz([30, 50, 30, 50]);
    const o = el('div', 'lvup', `<small>LEVEL UP</small><b>${lv}</b><p>日委托上限 +1 · 难度也跟着涨</p>`);
    const gl = $('#rsGlyph');
    if (gl) { const r = rel(gl); o.style.top = (r.y - 6) + 'px'; gl.style.transition = 'opacity .25s'; gl.style.opacity = .06; }
    $('#ui').appendChild(o);
    const n = Store.S.rings.length; if (n) Stage.igniteRing(n - 1);
    Stage.motion('cheer'); Stage.emote('joy');
    FX.burst(Stage.W / 2, Stage.H * .3, { n: 70, max: 520, life: 1.4 });
    await sleep(1300);
    o.style.transition = 'opacity .4s'; o.style.opacity = 0; setTimeout(() => o.remove(), 450);
    if (gl) gl.style.opacity = 1;
    Stage.emote('pleased');
    Line.say(line('lvUp', { lv }), { emo: 'smug', hold: 900 });
  },
  async finale() {
    const S = Store.S;
    ResultUI.hide(); Line.hide();
    this.setMode('main'); this.lineAt('main');
    const days = Math.max(1, Math.round((Clock.now() - S.goal.at) / 864e5));
    const fin = el('div', 'finale', `<span class="kick">MAINLINE COMPLETE · 主线达成</span><h2>${esc(S.goal.text)}</h2><p><b>${S.rings.length}</b> / ${S.rings.length} 环 · 用了 <b>${days}</b> 天</p>`);
    $('#ui').appendChild(fin);
    Stage.setCam('full');
    for (let i = 0; i < S.rings.length; i++) { Stage.igniteRing(i); Sound.play('ignite', i); await sleep(150); }
    const h = Stage.ringPoint(S.rings.length - 1, 0);
    FX.burst(h.x, h.y, { n: 120, max: 600, life: 1.8 }); FX.flash('#ffffff', .25, 400);
    Stage.motion('cheer'); Stage.emote('joy');
    await Line.seq(lines('finale', { goal: S.goal.text }), { emo: 'joy' });
    Stage.emote('tsun');
    const v = await choose([{ t: '立新目标。', v: 'new', main: true }, { t: '先享受一下。', v: 'rest' }]);
    fin.style.transition = 'opacity .5s'; fin.style.opacity = 0; setTimeout(() => fin.remove(), 600);
    Line.hide();
    if (v === 'new') { this.busy = false; return this.newGoal(true); }
    return this.lobby();
  },

  /* ═══ 认输：更暗、更安静、更短 ═══ */
  fail(how = 'quit') { return this.run(() => this._fail(how)); },
  async _fail(how) {
    const S = Store.S; if (!S.active) return;
    const info = Store.fail(how);
    Exec.hide(); Line.hide(); Plate.clear();
    this.setMode('fail'); this.lineAt('fail');
    Sound.muffle(true, .5); Sound.ambient(0, 1.4); Sound.play('fail'); buzz(60);
    $('#veil').style.transition = 'opacity .9s'; $('#veil').style.opacity = .6;
    Stage.setCam('fail'); Stage.emote('sad'); Stage.motion('down');
    Stage.holoTo({ sat: .3, bright: .6, rim: .18, scan: .45 });
    const ci = Store.curRing();
    if (info.task.kind === 'main' && ci >= 0) { Stage.dimRing(ci, .2); setTimeout(() => Stage.dimRing(ci, .6), 90); setTimeout(() => Stage.dimRing(ci, .15), 200); }
    const fv = $('#failv');
    fv.innerHTML = `<p class="fv-rec">${how === 'timeout' ? '超时' : '认输'} · 已记录 <b>${hhmm(Clock.now())}</b></p><div class="fv-remedy" id="fvRem"></div>`;
    fv.classList.add('on');
    await sleep(700);
    const v = { plan: fmtMin(info.task.min), held: fmtDur(info.held), wk: info.wk, last: info.last || '前几天', n: info.failStreak, name: info.task.name };
    let L;
    if (info.shield) L = lines('failShield', v);
    else if (info.tier >= 3) L = lines('failT3', v);
    else if (info.tier === 2 && info.last) L = lines('failT2', v);
    else if (how === 'timeout') L = lines('failTimeout', v);
    else L = info.held < 6e4 ? lines('failT1b', v) : lines('failT1', v);
    for (let i = 0; i < L.length; i++) await Line.say(L[i], { emo: i === L.length - 1 ? 'cold' : 'sad', speed: 52, soft: true, hold: i === L.length - 1 ? 900 : 500 });
    if (info.remedy) {
      const dl = new Date(info.remedy.deadline);
      const dls = `明天 ${hhmm(dl)} `;
      $('#fvRem').innerHTML = `<span class="kick">补救 · REMEDY</span><b>${esc(info.task.name)}</b>（做一半）· ${fmtMin(info.remedy.min)}<br>截止 ${dls}· ${info.remedy.r} 级 · 做到了，这一笔划掉`;
      $('#fvRem').classList.add('on');
      await Line.say(line('remedy', { dl: dls, half: fmtMin(info.remedy.min) }), { emo: 'neutral', speed: 44, soft: true, hold: 400 });
      const c = await choose([{ t: '……接。', v: 'y', main: true }, { t: '今天算了。', v: 'n' }]);
      Store.takeRemedy(c === 'y');
      this.restore(ci);
      if (c === 'y') {
        await Line.say(line('remedyYes'), { emo: 'neutral', hold: 900 });
        this.busy = false; return this.dispatch();
      }
      await Line.say(line('remedyNo'), { emo: 'cold', soft: true, hold: 1200 });
    } else {
      await sleep(600); this.restore(ci);
    }
    Line.hide(); return this.lobby();
  },
  restore(ci) {
    Sound.muffle(false, 1.2); Sound.ambient(1, 2);
    $('#veil').style.opacity = 0; $('#failv').classList.remove('on');
    Stage.holoTo({ sat: 1, bright: 1, rim: this.settings.holo ? .55 : 0, scan: this.settings.holo ? .2 : 0 });
    if (ci >= 0) Stage.dimRing(ci, 1);
    $('#app').classList.remove('fail');
  },

  /* ═══ 主线全景 / 面板 ═══ */
  mainline() {
    return this.run(async () => {
      const S = Store.S; if (!S.goal) return;
      this.setMode('main'); this.lineAt('main');
      Stage.setCam('full'); Stage.look('up'); Stage.emote('neutral');
      MainV.show();
      const d = S.rings.filter(g => g.state === 'done').length;
      setTimeout(() => Stage.look('user'), 1200);
      Line.say(line('mainline', { d, n: S.rings.length }), { soft: true, hold: 2600 }).then(() => this.mode === 'main' && Line.hide());
    });
  },
  sheet(kind) {
    Line.hide(); MainV.hide();
    if (this.mode === 'exec') Exec.hide();
    this._sheetFrom = this.mode === 'exec' || (Store.S.active && this.mode !== 'lobby') ? 'exec' : 'lobby';
    this.setMode('sheet'); this.lineAt('sheet');
    Stage.setCam('panel'); Stage.look({ x: Stage.W / 2, y: Stage.H * .7 });
    Sheet.open(kind);
    setTimeout(() => Stage.look('user'), 900);
    if (kind === 'archive') {
      const w = Store.weakest(), s = Store.strongest();
      Line.say(Math.random() < .5 ? line('archive', { weak: w.name, wv: w.v }) : tpl(LINES.archive[1], { strong: s.name }), { emo: 'smug', soft: true, hold: 2200 });
    } else if (kind === 'supply') Line.say(line('supply'), { emo: 'smug', soft: true, hold: 2000 });
  },
  closeSheet() {
    Sheet.close(); Line.hide();
    if (this._sheetFrom === 'exec' && Store.S.active) return this.exec();
    return this.lobby();
  },
  async newGoal(inFlow) {
    const go = async () => {
      MainV.hide();
      this.setMode('onboard'); this.lineAt('onboard'); Stage.setCam('talk');
      if (!inFlow) {
        await Line.say(line('abandon'), { emo: 'cold' });
        const c = await choose([{ t: '换。', v: 'y', main: true }, { t: '算了，不换。', v: 'n' }]);
        if (c === 'n') { Line.hide(); return this.lobby(); }
      }
      let plan;
      for (; ;) {
        await Line.say(line('newGoal'), { emo: 'focus', hold: 300 });
        const g = await askText({ ps: '目标 ›', ph: '一句话', presets: ['三个月跑完半马', '一个月早睡早起', '考研上岸', '半年减重 10 斤', '学会画画'] });
        plan = Store.makeGoal(g); if (!plan.vague) break;
        await Line.say(line('vague', { goal: g }), { emo: 'annoyed' });
      }
      await Line.say(line('decomp'), { emo: 'focus', motion: 'think', hold: 400 });
      await this.assemble(plan);
      Store.newGoal(plan);
      await Line.say(line('ringsDone', { n: plan.rings.length }), { emo: 'smug', look: 'up' });
      Line.hide(); this.lobby();
    };
    if (inFlow === true) { this.busy = true; try { await go(); } finally { this.busy = false; } } else await this.run(go);
  },

  /* 没人理她，她就会打瞌睡；一碰就醒，还嘴硬 */
  doze() {
    this.dozing = true;
    Stage.emote('sleep'); Stage.faceT.lid = .12; Stage.faceT.ay = -12; Stage.look('down');
    Stage.holoTo({ bright: .78, scan: .45 }); Sound.ambient(.55, 3);
    Line.say(line('doze'), { soft: true, emo: 'sleep', speed: 120, hold: 2400 }).then(() => { if (this.dozing) Line.hide(); });
  },
  async undoze() {
    if (!this.dozing) return; this.dozing = false;
    Stage.glitch(220, .8); Sound.play('poke'); Sound.ambient(1, 1);
    Stage.holoTo({ bright: 1, scan: this.settings.holo ? .2 : 0 });
    Stage.emote('surprised'); Stage.motion('surprise'); Stage.look('user');
    await sleep(380);
    await Line.say(line('dozeWake'), { emo: 'tsun', hold: 1600 });
    if (this.mode === 'lobby' && !this.busy) { Line.hide(); const m = Store.mood(); Stage.emote({ cold: 'cold', pleased: 'pleased' }[m] || 'neutral'); Stage.look('pointer'); }
    this.nextIdle = performance.now() + rand(26000, 40000);
  },

  /* 戳她 */
  poke() {
    const S = Store.S; S.pokes = (S.pokes || 0) + 1;
    const i = Math.min(LINES.poke.length - 1, (this._pokeN = (this._pokeN || 0) + 1) - 1);
    Sound.play('poke'); buzz(8);
    Stage.motion(i >= 3 ? 'fluster' : 'poke');
    Line.say(LINES.poke[i], { emo: i >= 4 ? 'cold' : i >= 2 ? 'annoyed' : 'tsun', hold: 1500 }).then(() => {
      if (this.mode === 'lobby') { Line.hide(); const m = Store.mood(); Stage.emote({ cold: 'cold', pleased: 'pleased' }[m] || 'neutral'); }
    });
    clearTimeout(this._pokeReset); this._pokeReset = setTimeout(() => { this._pokeN = 0; }, 20000);
  },

  /* 背景大字：她身后写着你的目标 */
  setWord(text, latin) {
    const w = $('#bgWord'); const len = [...text].length || 1;
    w.classList.toggle('latin', !!latin || /^[A-Z0-9\-−]+$/i.test(text));
    w.querySelector('span').textContent = text;
    w.style.setProperty('--wf', Math.round(Math.min(latin ? 120 : 175, (latin ? 560 : 360) / len)) + 'px');
    w.style.opacity = text ? 1 : 0;
  },

  /* 每帧：把 DOM 标签钉到舞台上 */
  place() {
    if (!Stage.cam) return;
    const S = Store.S;
    const head = Stage.toScreen(0, NY.eyes), chest = Stage.toScreen(0, NY.waist - .04);
    const bg = $('#bg');
    bg.style.setProperty('--hx', head.x + 'px'); bg.style.setProperty('--hy', head.y + 'px');
    bg.style.setProperty('--wy', chest.y + 'px');
    bg.style.setProperty('--ws', (.75 + Stage.bodyH / Stage.H * .25).toFixed(3));
    if (this.mode === 'lobby' && S && S.rings.length) {
      const ci = Store.curRing();
      if (ci >= 0) {
        const p = Stage.ringPoint(ci, 1), tag = $('#ringTag');
        tag.style.transform = `translate(${Math.round(p.x + 4)}px,${Math.round(p.y - 14)}px)`;
      }
    }
    if (this._asm) this._asm.forEach(t => { const p = Stage.ringPoint(t.i, 1); if (p) { t.el.style.left = (p.x + 8) + 'px'; t.el.style.top = p.y + 'px'; } });
    MainV.place(); Beam.place();
    const eye = $('#exEye'); if (eye) eye.style.transform = `scaleY(${Math.max(.1, Stage.blinkMul * Math.min(1, Stage.face.lid + .1)).toFixed(2)})`;
  },

  /* 每秒：计时、换日、碎碎念 */
  second() {
    const S = Store.S; if (!S || !S.bound) return;
    Dock.render();
    if (S.day !== dayKey() && ['lobby'].includes(this.mode) && !this.busy) { const r = Store.rollDay(); if (r) { this._roll = r; HUD.render(); this.greet(); } }
    const now = performance.now();
    if (this.mode === 'lobby' && !this.busy && !this.dozing && now - this.lastAct > 80000 && !$('#line').classList.contains('on')) this.doze();
    if (this.mode === 'lobby' && !this.busy && !this.dozing && now > this.nextIdle && !$('#line').classList.contains('on') && now - this.lastAct > 6000) {
      this.nextIdle = now + rand(26000, 42000);
      const h = new Date(Clock.now()).getHours();
      const ci = Store.curRing();
      const t = h >= 23 || h < 5 ? line('idleNight') : h < 10 && Math.random() < .4 ? line('idleMorning') : line('idle', { ring: ci + 1 });
      Line.say(t, { soft: true, emo: Store.mood() === 'cold' ? 'cold' : 'smug', hold: 3200 }).then(() => { if (this.mode === 'lobby' && !this.busy) Line.hide(); });
    }
    if (this.mode === 'exec' && S.active && now > this.nextComment && !$('#line').classList.contains('on') && !this.busy) {
      this.nextComment = now + rand(45000, 75000);
      const e = Clock.now() - S.active.startAt, lim = S.active.task.min * 6e4;
      let t = line('exec');
      if (lim - e < 3 * 6e4 && lim - e > 0) t = line('execNear', { t: fmtDur(lim - e) });
      Stage.look('user'); setTimeout(() => this.mode === 'exec' && Stage.look({ x: Stage.W * .26, y: Stage.H * .22 }), 2200);
      Line.say(t, { soft: true, emo: 'focus', hold: 2600 }).then(() => { if (this.mode === 'exec') Line.hide(); });
    }
  },

  setSetting(k, v) {
    const ST = this.settings;
    if (k === 'sound') { ST.sound = v === '1'; Sound.setOn(ST.sound); }
    if (k === 'haptic') ST.haptic = v === '1';
    if (k === 'holo') { ST.holo = v === '1'; Stage.holoTo({ rim: ST.holo ? .55 : 0, scan: ST.holo ? .2 : 0 }); }
    if (k === 'voice') { Voice.mode = v; if (v === 'tts' && !Voice.pickVoice()) { Voice.mode = 'blip'; Banner.show('人声不可用', '这台设备没有中文语音，已退回电子音', '!'); } }
    ST.voice = Voice.mode;
    localStorage.setItem('opus-v2/settings', JSON.stringify(ST));
    if (k === 'voice' && Voice.mode !== 'mute') Line.say('这样说话，可以吗？', { emo: 'smug', hold: 1400 });
  },

  /* ═══ 战报：一张想发出去的图 ═══ */
  async shareCard(res, said) {
    const S = Store.S, T = res.task, R = RARITY[T.r];
    Stage.noBlink = Stage.t + .6; Stage.blinkMul = 1; await nextFrame(); await nextFrame();
    const W = 900, H = 1600, c = document.createElement('canvas'); c.width = W; c.height = H;
    const g = c.getContext('2d');
    const bg = g.createLinearGradient(0, 0, 0, H); bg.addColorStop(0, '#071430'); bg.addColorStop(.55, '#040a18'); bg.addColorStop(1, '#020409');
    g.fillStyle = bg; g.fillRect(0, 0, W, H);
    const rg = g.createRadialGradient(W / 2, 520, 0, W / 2, 520, 620); rg.addColorStop(0, 'rgba(31,139,255,.32)'); rg.addColorStop(1, 'rgba(31,139,255,0)');
    g.fillStyle = rg; g.fillRect(0, 0, W, H);
    g.strokeStyle = 'rgba(56,225,255,.06)'; g.lineWidth = 1;
    for (let x = 0; x < W; x += 45) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke(); }
    for (let y = 0; y < H; y += 45) { g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke(); }
    g.save(); g.font = `400 300px ShuHei`; g.textAlign = 'center'; g.strokeStyle = 'rgba(56,225,255,.16)'; g.lineWidth = 2;
    g.strokeText(S.goal?.short || 'SYSTEM', W / 2, 640); g.restore();
    const shot = Stage.snapshot();
    if (shot) {
      const sw = shot.width, shh = shot.height * .6, k = W / sw;
      g.drawImage(shot, 0, 0, sw, shh, 0, 30, W, shh * k);
      const fade = g.createLinearGradient(0, 600, 0, 1000); fade.addColorStop(0, 'rgba(2,4,9,0)'); fade.addColorStop(1, 'rgba(2,4,9,.96)');
      g.fillStyle = fade; g.fillRect(0, 600, W, 420);
    }
    g.fillStyle = 'rgba(2,4,9,.96)'; g.fillRect(0, 1000, W, H - 1000);
    // 稀有度
    g.save(); g.shadowColor = R.c; g.shadowBlur = 50; g.font = '900 230px Tektur'; g.textAlign = 'center'; g.fillStyle = R.c;
    g.fillText(T.r, W / 2, 1010); g.restore();
    g.textAlign = 'center';
    g.font = '600 22px KodeMono'; g.fillStyle = '#38e1ff'; g.fillText('CLEAR · ' + (T.kind === 'main' ? 'MAINLINE RING ' + (T.ring + 1) : T.kind.toUpperCase()), W / 2, 1070);
    g.font = '400 50px ShuHei'; g.fillStyle = '#f2fcff'; g.fillText(T.name.slice(0, 16), W / 2, 1140);
    g.font = '800 96px Tektur'; g.fillStyle = '#ffffff'; g.shadowColor = '#38e1ff'; g.shadowBlur = 30;
    g.fillText('+' + res.exp + ' EXP', W / 2, 1270); g.shadowBlur = 0;
    const tags = [res.crit ? 'CRIT ×2' : '', res.dbl ? '双倍卡 ×2' : '', '◈ +' + res.coin, ...Object.entries(res.attrs).map(([k, v]) => ATTR_NAME[k] + ' +' + v)].filter(Boolean);
    g.font = '600 30px FangYuan'; g.fillStyle = '#9fe9ff'; g.fillText(tags.join('   '), W / 2, 1335);
    if (said) {
      g.font = '500 30px FangYuan'; g.fillStyle = '#e9fbff';
      const q = '「' + said + '」', rows = []; let cur = '';
      for (const ch of q) { if (g.measureText(cur + ch).width > W - 160) { rows.push(cur); cur = ch; } else cur += ch; }
      rows.push(cur);
      rows.slice(0, 2).forEach((r, i) => g.fillText(r, W / 2, 1398 + i * 42));
      g.font = '600 20px KodeMono'; g.fillStyle = '#38e1ff'; g.fillText('— SYSTEM', W / 2, 1398 + Math.min(2, rows.length) * 42 + 4);
    }
    g.textAlign = 'left'; g.font = '600 24px FangYuan'; g.fillStyle = '#e9fbff';
    g.fillText(`${S.name} · LV${S.lv} · 「${Store.title}」`, 60, 1548);
    g.textAlign = 'right'; g.font = '500 20px KodeMono'; g.fillStyle = '#5f7190';
    const d = new Date(Clock.now()); g.fillText(`${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()} ${hhmm(d)} · SYSTEM`, W - 60, 1548);
    const url = c.toDataURL('image/png');
    const a = document.createElement('a'); a.href = url; a.download = `战报-${T.r}-${Date.now()}.png`; a.click();
    Banner.show('战报', '已保存 · 发给谁随你', '⤓', 1600);
    this.lastShare = url;
  },
};
