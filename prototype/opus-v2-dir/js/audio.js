/* audio.js — 全部声音都是现场合成的（Web Audio），没有一个音频文件
   Sound：音效 + 环境底噪；Voice：她说话（电子音节 / 浏览器人声）+ 嘴型包络 */
'use strict';

const Sound = {
  ctx: null, master: null, comp: null, sfx: null, vox: null, amb: null, lp: null,
  on: true, _amb: null,

  init() {
    if (this.ctx) { this.ctx.resume?.(); return; }
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
    const c = this.ctx = new AC();
    this.comp = c.createDynamicsCompressor();
    this.comp.threshold.value = -16; this.comp.ratio.value = 3.5;
    this.lp = c.createBiquadFilter(); this.lp.type = 'lowpass'; this.lp.frequency.value = 18000;
    this.master = c.createGain(); this.master.gain.value = this.on ? .9 : 0;
    this.sfx = c.createGain(); this.vox = c.createGain(); this.amb = c.createGain();
    this.amb.gain.value = 0;
    [this.sfx, this.vox, this.amb].forEach(g => g.connect(this.lp));
    this.lp.connect(this.master); this.master.connect(this.comp); this.comp.connect(c.destination);
    this._noise = this._mkNoise();
  },
  setOn(v) { this.on = v; if (this.master) this.master.gain.setTargetAtTime(v ? .9 : 0, this.ctx.currentTime, .05); },
  get t() { return this.ctx ? this.ctx.currentTime : 0; },
  _mkNoise() {
    const c = this.ctx, b = c.createBuffer(1, c.sampleRate * 2, c.sampleRate), d = b.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    return b;
  },

  /* 一个振荡器音符：f → f2 滑音，attack/decay 包络，可接滤波 */
  tone(o) {
    if (!this.ctx) return;
    const c = this.ctx, t0 = c.currentTime + (o.at || 0), dur = o.dur || .2;
    const osc = c.createOscillator(), g = c.createGain();
    osc.type = o.type || 'sine';
    osc.frequency.setValueAtTime(o.f, t0);
    if (o.f2) osc.frequency.exponentialRampToValueAtTime(Math.max(1, o.f2), t0 + (o.slide || dur));
    if (o.detune) osc.detune.value = o.detune;
    const v = o.vol ?? .1, a = o.a ?? .005;
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(v, t0 + a);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    let node = osc;
    if (o.lp || o.bp) {
      const f = c.createBiquadFilter(); f.type = o.lp ? 'lowpass' : 'bandpass';
      f.frequency.value = o.lp || o.bp; f.Q.value = o.q || .8; node.connect(f); node = f;
    }
    node.connect(g); g.connect(o.bus || this.sfx);
    osc.start(t0); osc.stop(t0 + dur + .05);
    return osc;
  },
  noise(o) {
    if (!this.ctx) return;
    const c = this.ctx, t0 = c.currentTime + (o.at || 0), dur = o.dur || .2;
    const s = c.createBufferSource(); s.buffer = this._noise; s.loop = true;
    const f = c.createBiquadFilter(); f.type = o.type || 'bandpass'; f.Q.value = o.q || 1;
    f.frequency.setValueAtTime(o.f || 1200, t0);
    if (o.f2) f.frequency.exponentialRampToValueAtTime(o.f2, t0 + dur);
    const g = c.createGain(), v = o.vol ?? .05;
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(v, t0 + (o.a || .01));
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    s.connect(f); f.connect(g); g.connect(o.bus || this.sfx);
    s.start(t0, Math.random()); s.stop(t0 + dur + .05);
  },
  chord(fs, o = {}) { fs.forEach((f, i) => this.tone({ ...o, f, at: (o.at || 0) + (o.spread || 0) * i })); },

  /* ── 具名音效 ── */
  play(name, x) {
    if (!this.ctx || !this.on) return;
    const T = this;
    switch (name) {
      case 'tap': T.tone({ f: 1320, f2: 1080, dur: .05, vol: .04 }); break;
      case 'soft': T.tone({ f: 880, f2: 990, dur: .08, vol: .03, type: 'triangle' }); break;
      case 'choose':
        T.tone({ f: 740, f2: 1110, dur: .12, vol: .045, type: 'triangle' });
        T.noise({ f: 2400, f2: 5200, dur: .18, vol: .02 }); break;
      case 'ding': /* 叮：只属于派单 */
        T.tone({ f: 2093, dur: 1.5, vol: .14, a: .003 });
        T.tone({ f: 3136, dur: .9, vol: .05, a: .003 });
        T.tone({ f: 4186, dur: .35, vol: .02, a: .002 }); break;
      case 'boot':
        T.tone({ f: 38, f2: 112, dur: 1.1, slide: .9, vol: .3, a: .2 });
        T.noise({ f: 300, f2: 5200, dur: .95, vol: .06, a: .6, q: .7 });
        T.chord([220, 329.6, 440, 554.4, 659.3], { type: 'triangle', dur: 2.6, vol: .045, a: .02, at: .9, spread: .035 });
        T.tone({ f: 1760, dur: 1.8, vol: .02, at: .95 }); break;
      case 'ignite': {
        const f = [523.3, 587.3, 659.3, 784, 880, 1046.5, 1174.7, 1318.5][clamp(x | 0, 0, 7)];
        T.tone({ f, dur: 1.1, vol: .07, a: .004 }); T.tone({ f: f * 2.76, dur: .4, vol: .02, a: .003 }); break;
      }
      case 'whoosh': T.noise({ f: 280, f2: 2600, dur: .38, vol: .06, a: .12, q: .6 }); break;
      case 'land':
        T.tone({ f: 96, f2: 40, dur: .42, vol: .38, a: .004 });
        T.noise({ type: 'lowpass', f: 700, dur: .16, vol: .14, a: .002 });
        T.tone({ f: 2400, dur: .03, vol: .03 }); break;
      case 'rung': T.tone({ f: 300 * Math.pow(2, (x || 0) / 5), dur: .07, vol: .045, type: 'square', lp: 2600 }); break;
      case 'rank': { // 稀有度落定：越高越重
        const i = x || 0;
        T.tone({ f: 80, f2: 45, dur: .35 + i * .05, vol: .2 + i * .03 });
        const base = [392, 440, 494, 523.3, 587.3, 659.3, 784][i];
        T.chord([base, base * 1.26, base * 1.5, base * 2], { type: 'triangle', dur: .8 + i * .15, vol: .03 + i * .006, spread: .02 });
        if (i >= 5) { T.noise({ f: 6000, dur: .8, vol: .03, a: .01 }); T.tone({ f: base * 4, dur: 1.4, vol: .02, at: .05 }); }
        break;
      }
      case 'engrave': T.noise({ f: 4200 + Math.random() * 2400, q: 3, dur: .03, vol: .018, a: .002 }); break;
      case 'seal':
        T.tone({ f: 70, f2: 44, dur: .5, vol: .34 });
        T.chord([293.7, 370, 440, 587.3], { type: 'triangle', dur: 1.2, vol: .05, spread: .015 });
        T.noise({ f: 1800, f2: 400, dur: .3, vol: .06 }); break;
      case 'scan': T.noise({ f: 900, f2: 6400, dur: .7, vol: .035, a: .1, q: 2 });
        for (let i = 0; i < 6; i++) T.tone({ f: 1400 + i * 180, dur: .03, vol: .015, type: 'square', at: i * .09 }); break;
      case 'impact':
        T.tone({ f: 130, f2: 36, dur: .75, vol: .5, a: .003 });
        T.noise({ type: 'lowpass', f: 1200, f2: 200, dur: .4, vol: .2, a: .002 });
        T.chord([1318.5, 1760, 2637], { dur: 1.2, vol: .022, at: .02, spread: .03 }); break;
      case 'count': T.tone({ f: 1700 + Math.random() * 300, dur: .025, vol: .016, type: 'square', lp: 4000 }); break;
      case 'crit':
        T.noise({ f: 3000, f2: 9000, dur: .18, vol: .05, a: .15, at: 0 });
        T.tone({ f: 1567, dur: .5, vol: .08, type: 'square', lp: 5000, at: .16 });
        T.tone({ f: 2093, dur: .7, vol: .06, at: .16 });
        T.tone({ f: 110, f2: 50, dur: .3, vol: .3, at: .16 }); break;
      case 'levelup':
        [523.3, 659.3, 784, 1046.5, 1318.5].forEach((f, i) => T.tone({ f, dur: .7, vol: .055, type: 'triangle', at: i * .07 }));
        T.noise({ f: 7000, dur: .9, vol: .02, at: .3 }); break;
      case 'coin': T.tone({ f: 1975.5, dur: .09, vol: .045 }); T.tone({ f: 2637, dur: .22, vol: .045, at: .07 }); break;
      case 'title': T.tone({ f: 1046.5, dur: .9, vol: .05 }); T.tone({ f: 1568, dur: 1.1, vol: .04, at: .12 }); break;
      case 'fail': /* 更暗、更安静、更短：只有一个往下沉的低音 */
        T.tone({ f: 98, f2: 69, dur: 1.7, slide: 1.5, vol: .13, a: .06 }); break;
      case 'poke': T.tone({ f: 620, f2: 990, dur: .1, vol: .05, type: 'triangle' }); break;
      case 'shutter': T.noise({ type: 'highpass', f: 2500, dur: .05, vol: .08, a: .002 }); T.tone({ f: 3200, dur: .02, vol: .03, at: .05 }); break;
      case 'deny': T.tone({ f: 220, f2: 180, dur: .14, vol: .05, type: 'square', lp: 1200 }); break;
      case 'hold': T.tone({ f: 600 + (x || 0) * 500, dur: .04, vol: .02, type: 'square', lp: 3000 }); break;
      case 'unhold': T.tone({ f: 500, f2: 300, dur: .1, vol: .025, type: 'triangle' }); break;
    }
  },

  /* 按住类的持续音：返回 stop()。rise=true 往上爬（接单），false 往下沉（认输） */
  drone(rise = true, ms = 900) {
    if (!this.ctx || !this.on) return { stop() { } };
    const c = this.ctx, t0 = c.currentTime;
    const o = c.createOscillator(), g = c.createGain(), f = c.createBiquadFilter();
    o.type = rise ? 'sawtooth' : 'sine';
    o.frequency.setValueAtTime(rise ? 150 : 210, t0);
    o.frequency.exponentialRampToValueAtTime(rise ? 760 : 92, t0 + ms / 1000);
    f.type = 'lowpass'; f.frequency.value = rise ? 1800 : 600;
    g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(rise ? .03 : .06, t0 + .08);
    o.connect(f); f.connect(g); g.connect(this.sfx); o.start(t0);
    return { stop() { const t = c.currentTime; g.gain.cancelScheduledValues(t); g.gain.setTargetAtTime(0.0001, t, .03); o.stop(t + .2); } };
  },

  /* 环境底噪：只有一层低频 pad（55/82/110/165Hz 的呼吸和弦）。失败时整体收掉。
     ⚠ 这里曾经还有第二层「极轻的空气声」= 白噪声 → bandpass(7kHz, Q=.5)。
     别再加回来：Q=.5 的带宽是 14kHz，那不是空气声，是一条几乎全通的**持续高频噪声**
     （实测 1.5k~16kHz 的能量 100% 来自它，手机喇叭上底噪一整层只剩这阵沙沙）。
     pad 是给耳机的空间感；喇叭上听不见就算了，安静比噪声好 */
  ambient(level = 1, sec = 1.2) {
    if (!this.ctx) return;
    if (!this._amb) {
      const c = this.ctx, lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 520; lp.Q.value = 2;
      const lfo = c.createOscillator(), lg = c.createGain(); lfo.frequency.value = .07; lg.gain.value = 160;
      lfo.connect(lg); lg.connect(lp.frequency); lfo.start();
      [55, 82.41, 110.2, 164.8].forEach((f, i) => {
        const o = c.createOscillator(); o.type = i < 2 ? 'triangle' : 'sine'; o.frequency.value = f; o.detune.value = (i - 1.5) * 6;
        const g = c.createGain(); g.gain.value = [.5, .35, .18, .08][i]; o.connect(g); g.connect(lp); o.start();
      });
      const pg = c.createGain(); pg.gain.value = .11; lp.connect(pg); pg.connect(this.amb);
      this._amb = true;
    }
    this.amb.gain.setTargetAtTime(.32 * level, this.ctx.currentTime, sec / 3);
  },
  /* 失败那一刻：整个世界的高频被拿走 */
  muffle(on, sec = .6) {
    if (!this.ctx) return;
    this.lp.frequency.setTargetAtTime(on ? 700 : 18000, this.ctx.currentTime, sec / 3);
  },
};

/* ═══ Voice：她的声音 + 嘴型 ═══ */
const Voice = {
  mode: 'blip',            // blip 电子音节 / tts 浏览器人声 / mute
  mouth: 0, _target: 0, _ttsOn: false, _voice: null, level: 0,
  PITCH: { neutral: 560, smug: 520, cold: 470, annoyed: 610, pleased: 610, tsun: 660, joy: 700, surprised: 720, sad: 360, focus: 540, sleep: 300, proud: 600 },

  tick(dt) {
    if (this._ttsOn) { // 人声模式拿不到振幅：用伪随机开合模拟
      const t = performance.now() / 1000;
      this._target = Math.max(0, .45 + .4 * Math.sin(t * 17) * Math.sin(t * 5.3 + 1) + (Math.random() - .5) * .3);
    } else this._target *= Math.pow(.0009, dt);  // 每个音节后迅速合嘴
    this.mouth += (this._target - this.mouth) * (1 - Math.pow(.00002, dt));
    this.level = this.mouth;
  },
  /* 一个字：电子音节 + 张嘴 */
  syllable(ch, emo = 'neutral', soft = false) {
    if (/[，。！？、…—\s,.!?「」『』（）()：:；;"“”‘’]/.test(ch)) { this._target = 0; return; }
    this._target = rand(.55, 1);
    if (this.mode !== 'blip' || !Sound.ctx || !Sound.on) return;
    const base = (this.PITCH[emo] || 560) * rand(.92, 1.08);
    Sound.tone({ f: base, f2: base * rand(.86, 1.12), dur: .06, vol: soft ? .016 : .03, type: 'square', bp: base * 2.1, q: 1.4, bus: Sound.vox, a: .004 });
  },
  pickVoice() {
    if (!('speechSynthesis' in window)) return null;
    const vs = speechSynthesis.getVoices().filter(v => /zh|cmn|Chinese/i.test(v.lang + v.name));
    const pref = [/Xiaoxiao|Xiaoyi|Natural/i, /Tingting|婷婷/i, /Google.*(普通话|中国)/i, /Huihui|Yaoyao/i];
    for (const re of pref) { const v = vs.find(v => re.test(v.name)); if (v) return v; }
    return vs[0] || null;
  },
  /* 人声模式：整句交给浏览器 TTS；拿不到声音就退回电子音节 */
  /* 返回 Promise（说完才 resolve）；拿不到中文语音就返回 null，字幕退回电子音节 */
  speak(text, emo) {
    if (this.mode !== 'tts' || !('speechSynthesis' in window)) return null;
    const v = this._voice || (this._voice = this.pickVoice()); if (!v) return null;
    const say = plain(text).replace(/……|…/g, '，').replace(/[——]+/g, '，');
    if (!/[一-龥A-Za-z0-9]/.test(say)) return null;
    return new Promise(res => {
      let done = false;
      const fin = () => { if (done) return; done = true; this._ttsOn = false; this._target = 0; res(); };
      try {
        speechSynthesis.cancel();
        const u = new SpeechSynthesisUtterance(say);
        u.voice = v; u.lang = v.lang; u.rate = emo === 'sad' ? .92 : 1.08; u.pitch = emo === 'sad' ? 1.0 : 1.32; u.volume = Sound.on ? 1 : 0;
        u.onstart = () => { this._ttsOn = true; };
        u.onend = u.onerror = fin;
        setTimeout(fin, 1200 + say.length * 340);
        speechSynthesis.speak(u);
      } catch (e) { fin(); }
    });
  },
  hush() { this._target = 0; this._ttsOn = false; try { speechSynthesis.cancel(); } catch (e) { } },
};
