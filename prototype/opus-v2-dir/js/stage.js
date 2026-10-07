/* ═══════════════════════════════════════════════════════════
   stage.js — 她所在的舞台（WebGL2 · ournotes-player · 丰川祥子 casual_spring）

   · 模型 = ournotes-live2d 自定义元素（63 个动作 / 28 个表情）
   · 世界坐标：她站在一个 1.6 × 2.4 的矩形里（_canvasRect()），
        x 以身体中线为 0，y 向上为正。她的真实占位（实测）：
        发顶 +0.44 · 眼 +0.23 · 下巴 +0.13 · 胸 -0.12 · 腰 -0.25
        裙摆 -0.85 · 膝 -1.05 · 踝 -1.36 · 脚底 -1.51
   · 相机 = 把世界里 (ax, ay) 这一点钉在屏幕 (sx, sy)，缩放 S（css px / 世界单位）。
     做法是在每帧的 unity_MatrixVP 右边乘一个世界空间的仿射矩阵（见 _camMul）
   · 主线环：世界空间里的椭圆，跟着她一起缩放位移；画在一张 2D 画布上（加色混合）
   · 表情：① 播放器自己的动作曲线 → ② _applyFace 写参数 → ③ _post 后置覆写
   ═══════════════════════════════════════════════════════════ */
'use strict';

/* 她的身体：世界 y（实测值，换模型时用 alpha 包围盒重测即可） */
const NY = { hair: .44, top: .38, eyes: .23, chin: .13, neck: .07, shoulder: .01, chest: -.12, waist: -.25, hem: -.85, knee: -1.05, ankle: -1.36, feet: -1.51 };
const BODY = { top: NY.hair, bot: NY.feet };          // 她的整体高度 = 1.95 世界单位

const MODEL_SRC = 'live2d/sakiko/models/adv_live2d_sakiko_010_casual_spring_01.json';
/* 播放器与 Cubism Core 放 vendor/（入库，gitignore 只管 live2d/ 下的模型本体）；
   live2d/sakiko/vendor/ 里那份是模型包自带的副本，仅供模型包独立可用，运行时不用 */
const CORE_SRC = 'vendor/live2dcubismcore.min.js';
const PLAYER_SRC = 'vendor/ournotes-live2d.element.min.js';

/* 情绪预设：lid 眼睑倍率 · smile 眼笑 · mouth 口型(-1~1) · cheek 脸红(0~1) · brow 眉 · ax/ay/az 头角度 · open 张嘴 */
const FACES = {
  neutral: { lid: 1, smile: 0, mouth: 0, cheek: 0, brow: 0, ax: 0, ay: 0, az: 0 },
  smug: { lid: .42, smile: .22, mouth: .45, cheek: 0, brow: .22, ax: 0, ay: -2, az: 6 },
  cold: { lid: .3, smile: 0, mouth: -.35, cheek: 0, brow: -.45, ax: -5, ay: -2, az: -2 },
  annoyed: { lid: .3, smile: 0, mouth: -.72, cheek: .18, brow: -.7, ax: 0, ay: 0, az: -4 },
  pleased: { lid: .34, smile: .55, mouth: .6, cheek: .4, brow: .35, ax: 0, ay: 2, az: 3 },
  tsun: { lid: .2, smile: 0, mouth: -.55, cheek: 1, brow: -.5, ax: 9, ay: -3, az: -4 },
  joy: { lid: .06, smile: 1, mouth: 1, cheek: .8, brow: .5, ax: 0, ay: 4, az: 5, open: .18 },
  proud: { lid: .33, smile: .5, mouth: .85, cheek: .35, brow: .25, ax: 0, ay: 3, az: 4 },
  surprised: { lid: 1.3, smile: 0, mouth: -.15, cheek: 0, brow: 1, ax: 0, ay: 5, az: 0, open: .42 },
  sad: { lid: .55, smile: 0, mouth: -.7, cheek: 0, brow: -.2, ax: -6, ay: -12, az: 3 },
  focus: { lid: .6, smile: 0, mouth: -1, cheek: 0, brow: -.15, ax: 0, ay: -1, az: 0 },
  sleep: { lid: 0, smile: 0, mouth: 0, cheek: .1, brow: 0, ax: 0, ay: -16, az: 2 },
};
const FACE_KEYS = ['lid', 'smile', 'mouth', 'cheek', 'brow', 'ax', 'ay', 'az', 'open'];

/* 动作表：App 的动词 → 模型的 63 个动作（C 中 / L 左 / R 右 三向）。
   数组 = 每次随机挑一个；pools 里的用在待机 */
const MOVE = {
  present: { m: ['mtn_kime01_C', 'mtn_kime01_L', 'mtn_kime01_R'], fade: .35 },   // 派单：亮个相
  cheer: { m: ['mtn_kime01_C', 'mtn_smile02_C'], fade: .3 },                     // 结算
  nod: { m: 'mtn_nod01_C', fade: .3 },
  nod2: { m: ['mtn_nod01_L', 'mtn_nod01_R', 'mtn_nod02_C'], fade: .3 },
  surprise: { m: ['mtn_surprised01_C', 'mtn_surprised01_L'], fade: .2 },         // 惊
  fluster: { m: ['mtn_denial02_C', 'mtn_denial01_C', 'mtn_denial02_L'], fade: .25 }, // 被叫「统子」
  down: { m: ['mtn_sad01_C', 'mtn_sad02_C'], fade: .4 },                         // 低落
  think: { m: ['mtn_thinking01_C', 'mtn_thinking01_L'], fade: .35 },             // 思考
  happy: { m: ['mtn_smile01_C', 'mtn_smile02_C'], fade: .3 },
  poke: { m: ['mtn_check01_C', 'mtn_question01_C', 'mtn_nod02_C'], fade: .3, exp: 'exp_shy01' },
  lookAway: { m: ['mtn_look01_L', 'mtn_look01_R', 'mtn_look02_C', 'mtn_look02_L'], fade: .4 },
  deny: { m: ['mtn_denial01_C', 'mtn_denial02_C'], fade: .3 },
  ask: { m: 'mtn_question01_C', fade: .3 },
  bye: { m: ['mtn_bye01_C', 'mtn_bye01_L', 'mtn_bye01_R'], fade: .35 },
  check: { m: 'mtn_check01_C', fade: .3 },
  serious: { m: 'mtn_serious01_C', fade: .35 },
  angry: { m: ['mtn_angry01_C', 'mtn_angry01_L'], fade: .25 },
  cry: { m: ['mtn_cry01_C', 'mtn_cry01_L'], fade: .4 },
  maskoff: { m: 'mtn_maskoff01_C', fade: .3 },
};
/* 待机行为池：心情决定她闲下来演什么 */
const IDLE_POOL = {
  cold: [['mtn_serious01_C'], ['mtn_look02_C'], ['mtn_look01_L'], ['mtn_serious01_R'], ['mtn_nod02_C']],
  pleased: [['mtn_smile01_C'], ['mtn_smile02_C'], ['mtn_kime01_C'], ['mtn_smile02_L'], ['mtn_nod01_C']],
  neutral: [['mtn_look01_C'], ['mtn_check01_C'], ['mtn_nod02_C'], ['mtn_smile01_C'], ['mtn_look02_L'], ['mtn_thinking01_C'], ['mtn_idle01_L']],
};
/* 情绪 → 表情（只在切换情绪时下发一次，免得压住动作自带的情绪） */
const EMO_EXP = {
  neutral: 'exp_idle01', smug: 'exp_bsmile01', cold: 'exp_serious01', annoyed: 'exp_angry02',
  pleased: 'exp_smile01', tsun: 'exp_shy01', joy: 'exp_bsmile02', proud: 'exp_smile02',
  surprised: 'exp_surprised02', sad: 'exp_sad02', focus: 'exp_serious02', sleep: 'exp_idle04',
};

/* 相机：FIT = 她正好占满屏高时，1 个世界单位 = 多少 css px */
const camFit = H => H / (BODY.top - BODY.bot);

const Stage = {
  el: null, host: null, player: null, session: null, ch: null, ready: false, failed: false,
  W: 390, H: 844, cv: null, cx: null,          // cv = 模型画布, cx = 环的画布
  cam: null, camName: 'boot', t: 0,
  face: {}, faceT: {}, emo: 'neutral', blinkMul: 1, _blink: { next: 2, t: -1 },
  gaze: { mode: 'user', x: 0, y: 0, px: 0, py: 0, lastMove: 0, sacc: 0, sx: 0, sy: 0 },
  rings: [], ringAnim: [], shocks: [], ringMul: [], ringVis: [], ringScale: [],  fx: { sat: 1, bright: 1, rim: .55, scan: .22, glitch: 0, lift: .5 }, fxT: null,
  rimColor: [.22, .88, 1], rimT: [.22, .88, 1], ringA: 1, ringAT: 1, scan: 0, scanT: 0,
  lookT: null,
  idle: { next: 4, play: 0, mood: 'neutral' }, idleMood: 'neutral',
  _hookOK: true, _hookErr: '', _log: [],
  onTick: [],

  /* ── 启动：Cubism 核心 → 播放器模块（index.html 里的 module 引导）→ 模型 ── */
  async init(host, onProgress = () => { }) {
    this.host = host;
    this.W = host.clientWidth || 390; this.H = host.clientHeight || 844;
    const F = camFit(this.H);
    this.cam = {
      S: new Spring(F * .62, 70, .95), ax: new Spring(0, 70, .95), ay: new Spring(-.3, 70, .95),
      sx: new Spring(this.W / 2, 70, .95), sy: new Spring(this.H * .3, 70, .95),
    };
    FACE_KEYS.forEach(k => { this.face[k] = FACES.sleep[k] || 0; this.faceT[k] = FACES.sleep[k] || 0; });
    this.fxT = { ...this.fx };
    this.lookT = { x: new Spring(0, 90, .85), y: new Spring(0, 90, .85) };

    onProgress(.10, 'CUBISM CORE');
    await loadScript(CORE_SRC);
    if (!window.Live2DCubismCore) throw new Error('Live2D Cubism Core 未就绪');
    onProgress(.26, 'CORE ✓');
    /* 播放器模块只导出、不自注册：拿到命名空间后必须自己调 defineOurnotesLive2D() */
    const mod = await import(/* @vite-ignore */ new URL(PLAYER_SRC, location.href).href);
    if (typeof mod.defineOurnotesLive2D !== 'function') throw new Error('播放器模块没有 defineOurnotesLive2D');
    mod.defineOurnotesLive2D();
    if (!customElements.get('ournotes-live2d')) throw new Error('ournotes 播放器未定义');
    onProgress(.34, 'PLAYER ✓');

    /* 模型元素：占满舞台，宽高比由播放器自己定（2:3 = 画布 1.6×2.4） */
    const el = this.el = document.createElement('ournotes-live2d');
    el.id = 'stageCv';
    el.style.cssText = 'position:absolute;left:50%;top:0;transform:translateX(-50%);height:100%;width:auto';
    host.appendChild(el);
    el.playerOpts = { pixelRatio: 2 };       // 元素没有暴露该属性，但播放器读 el.playerOpts → 画布按 2 倍光栅

    /* 环的画布：盖在模型上，加色混合 */
    const cv = this.cx = document.createElement('canvas');
    cv.id = 'ringCv';
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none';
    host.appendChild(cv);
    this._sizeRings();

    const failed = this._once(el, 'error', 45000).then(e => {
      const d = e && e.detail && e.detail.error;
      throw new Error('模型加载失败：' + (d && d.message ? d.message : d));
    });
    const ok = this._once(el, 'ready', 45000).then(() => true);
    let lastP = .34;
    el.addEventListener('progress', e => {
      const d = e.detail || {}; if (!d.total) return;
      const p = .34 + .6 * Math.min(1, d.loaded / d.total);
      if (p - lastP > .04) { lastP = p; onProgress(p, `资源 ${(d.loaded / 1048576).toFixed(1)}MB`); }
    });

    const src = new URL(MODEL_SRC, location.href).href;
    el.setAttribute('src', src);
    await Promise.race([ok, failed]);
    onProgress(.96, '人格 ✓');

    this.player = el.player;
    this.session = this.player.session;
    this.ch = this.session.character;
    this.cv = this.session.gl.canvas;
    /* 她真正的几何：直接向渲染器要她现在占了多少像素（含动作/表情形变、和动作无关的头身比） */
    await this._fitGeo();
    try { this.ch._onLateUpdateInternal = this._wrap(this.ch._onLateUpdateInternal.bind(this.ch)); }
    catch (e) { this._hookOK = false; this._log.push('hook: ' + e.message); }

    this.el.addEventListener('pointerdown', () => { this.host.style.setProperty('--poked', Date.now() + ''); });
    this._resizeObs = new ResizeObserver(() => this.resize()); this._resizeObs.observe(host);

    /* 镜头：挂到播放器的 render() 上（它每帧自己算 globals，我们算完就改矩阵） */
    this._hookOK2 = this._hookCam();
    if (!this._hookOK2) this._log.push('cam hook failed');
    this.setCam('boot', true);
    try {
      this.player.playMotion(this.player.defaultMotion || 'mtn_idle01_C', { loop: true });
      if (this.player.defaultExpression) this.player.setExpression(this.player.defaultExpression);
    } catch (e) { }
    this.ready = true;
    onProgress(1, '就绪');
  },
  _once(el, name, ms) {
    return new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error('超时：' + name)), ms);
      el.addEventListener(name, e => { clearTimeout(t); res(e); }, { once: true });
    });
  },

  /* ── 向渲染器问她的世界占位（换模型不用改代码） ──
     ⚠ meshes[front].pos 是「drawable 本地坐标」，要看整体必须过 rd.transform.localToWorld()
     只统计「可见 + 不透明」的 drawable，免得被权重为 0 的残影拉偏 */
  async _fitGeo() {
    const r = this.session._canvasRect();
    const g = { top: null, feet: null, half: null };
    try {
      await this.session.step({ draw: true });
      const rs = this.ch.renderers || [];
      let yTop = -9, yBot = 9, half = 0, used = 0;
      for (const rd of rs) {
        if (!rd || rd.enabled === false || rd.opacity < .02) continue;
        if (rd.isMaskSource) continue;         // 掩膜层用的是另一套变换，混进来会把身高量矮
        const m = rd.meshes && rd.meshes[rd.front];
        const a = m && m.pos; if (!a || a.length < 2) continue;
        let x0 = 9, x1 = -9, y0 = 9, y1 = -9;
        for (let i = 0; i + 1 < a.length; i += 2) {
          const x = a[i], y = a[i + 1];
          if (!isFinite(x) || !isFinite(y)) continue;
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
        if (x0 > x1) continue;
        let M = null;
        try { M = rd.transform && rd.transform.localToWorld && rd.transform.localToWorld(); } catch (e) { }
        if (!M) continue;
        used++;
        // 把本地包围盒 4 个角映射到世界（仿射下平行四边形的包围盒）
        for (const [lx, ly] of [[x0, y0], [x1, y0], [x0, y1], [x1, y1]]) {
          const wx = M[0] * lx + M[4] * ly + M[12];
          const wy = M[1] * lx + M[5] * ly + M[13];
          if (!isFinite(wx) || !isFinite(wy)) continue;
          if (wy > yTop) yTop = wy;
          if (wy < yBot) yBot = wy;
          const ax = Math.abs(wx); if (ax > half) half = ax;
        }
      }
      if (used && yTop > yBot) { g.top = yTop; g.feet = yBot; g.half = half; g.used = used; }
    } catch (e) { this._log.push('fitGeo: ' + e.message); }
    if (g.top == null) {                       // 兜底：拍摄实测值
      g.top = .44; g.feet = -1.51; g.half = .30;
    }
    this.geo = { top: g.top, feet: g.feet, cx: (r.x0 + r.x1) / 2, h: g.top - g.feet, half: g.half, rect: r };
    Object.assign(NY, {
      hair: g.top, eyes: lerp(g.feet, g.top, .893), chin: lerp(g.feet, g.top, .844),
      neck: lerp(g.feet, g.top, .812), shoulder: lerp(g.feet, g.top, .78), chest: lerp(g.feet, g.top, .72),
      waist: lerp(g.feet, g.top, .64), hem: lerp(g.feet, g.top, .33), knee: lerp(g.feet, g.top, .23),
      ankle: lerp(g.feet, g.top, .075), feet: g.feet,
    });
    BODY.top = g.top; BODY.bot = g.feet;
    this._log.push(`geo top=${g.top.toFixed(3)} feet=${g.feet.toFixed(3)} h=${(g.top - g.feet).toFixed(3)} half=${g.half.toFixed(3)} n=${g.used || 0}`);
  },

  resize() {
    if (!this.host) return;
    const w = this.host.clientWidth, h = this.host.clientHeight; if (!w || !h) return;
    this.W = w; this.H = h;
    this._sizeRings();
    this.setCam(this.camName, true);
  },
  _sizeRings() {
    const d = Math.min(devicePixelRatio || 1, 2);
    this._rdpr = d;
    this.cx.width = Math.round(this.W * d); this.cx.height = Math.round(this.H * d);
    this.cg = this.cx.getContext('2d');
  },

  /* ── 相机 ──
     把世界里 (ax, ay) 钉在屏幕 (sx, sy)，S = css px / 世界单位。
     矩阵做的是 p → (p - ax)/K + t，K = Sfit/S（见 _camMul）。
     S 的取值 = camFit(H) × 系数，系数就是「她占屏高的百分比」（实测标定，和旧稿对齐）：
     旧稿大厅 91%、主线全景 68%、开机待机 60%（头 20% 脚 80%） */
  CAMS: {
    boot: (W, H) => ({ S: camFit(H) * .64, ax: 0, ay: -.30, sx: W / 2, sy: H * .444 }),
    lobby: (W, H) => ({ S: camFit(H) * .92, ax: 0, ay: -.535, sx: W / 2, sy: H * .505 }),
    talk: (W, H) => ({ S: camFit(H) * 1.70, ax: 0, ay: .30, sx: W / 2, sy: H * .14 }),
    exec: (W, H) => ({ S: camFit(H) * .72, ax: 0, ay: -.50, sx: W * .76, sy: H * .42 }),
    result: (W, H) => ({ S: camFit(H) * 1.05, ax: 0, ay: .18, sx: W / 2, sy: H * .26 }),
    full: (W, H) => ({ S: camFit(H) * .68, ax: 0, ay: -.535, sx: W * .46, sy: H * .46 }),
    panel: (W, H) => ({ S: camFit(H) * .88, ax: 0, ay: -.15, sx: W * .5, sy: H * .34 }),
    fail: (W, H) => ({ S: camFit(H) * .72, ax: 0, ay: -.45, sx: W * .5, sy: H * .40 }),
  },
  setCam(name, snap) {
    this.camName = name;
    const c = (this.CAMS[name] || this.CAMS.lobby)(this.W, this.H);
    for (const k of ['S', 'ax', 'ay', 'sx', 'sy']) this.cam[k].set(c[k], snap);
    this._camDirty = true;
  },
  /* 世界 (x, y) → 屏幕 css px */
  toScreen(x, w) {
    const c = this.cam, S = c.S.x;
    return { x: c.sx.x + (x - c.ax.x) * S, y: c.sy.x + (c.ay.x - w) * S };
  },
  get zoom() { return this.cam.S.x; },
  get fit() { return camFit(this.H); },          // 她正好占满屏高时的 S
  get bodyH() { return this.cam.S.x * (BODY.top - BODY.bot); },   // 她在屏幕上多高（css px）

  /* ── 每帧的镜头矩阵：在 unity_MatrixVP 右边乘一个世界空间仿射 ──
     投影 P 是播放器自己那套固定 fit（世界 1.6×2.4 → 画布），我们只改它前面的世界侧：
     把世界点 a 送到 t（那正是屏幕上 (sx, sy) 对应的点），并把世界放大 1/K 倍。
     ⚠ K 必须是「fit 缩放 / 目标缩放」：K = Sfit/S，写成 1/S 会让镜头×fit 相乘（人直接飞走） */
  _camMul(g, w, h) {
    const c = this.cam, el = this.el;
    const e0 = el.getBoundingClientRect();                   // 画布在页面里的位置（left:50% + translateX(-50%) 会有负偏移）
    const s0 = this.host.getBoundingClientRect();            // 舞台（手机屏）在页面里的位置——桌面上不是 0
    const kx = w / (el.clientWidth || w), ky = h / (el.clientHeight || h);   // css → 画布 px
    const r = this.session._canvasRect();
    const S = c.S.x;
    const h0 = (r.y1 - r.y0) / 2, l0 = (r.x1 - r.x0) / 2, o = w / h;
    const Sfit = h / (2 * (l0 / h0 > o ? l0 / o : h0));      // 播放器那套 fit 的缩放（画布 px / 世界单位）
    const K = Sfit / (S * kx);                               // S 是 css px/世界单位，矩阵在画布 px 里算
    const px = (s0.x + c.sx.x - e0.x) * kx;                  // 舞台上的目标点 → 画布 px
    const py = (s0.y + c.sy.x - e0.y) * ky;
    const tx = r.x0 + px * (r.x1 - r.x0) / w;                // 目标点（世界）
    const ty = r.y1 - py * (r.y1 - r.y0) / h;
    const ax = c.ax.x, ay = c.ay.x;
    g.unity_MatrixVP = mul4(g.unity_MatrixVP, new Float32Array([
      1 / K, 0, 0, 0, 0, 1 / K, 0, 0, 0, 0, 1, 0, tx - ax / K, ty - ay / K, 0, 1,
    ]));
    return g;
  },
  /* 挂到 session._globals 上：render() 每帧算一次 globals，我们算完立刻改矩阵 */
  _hookCam() {
    const s = this.session;
    if (!s || typeof s._globals !== 'function' || s.__camHooked) return false;
    const orig = s._globals.bind(s);
    const st = this;
    s._globals = function (w, h) {
      const g = orig(w, h);
      try { st._camMul(g, w, h); } catch (e) { }
      return g;
    };
    s.__camHooked = true;
    return true;
  },

  /* ── 情绪 / 动作 / 视线 ── */
  emote(name, gaze) {
    if (!FACES[name]) name = 'neutral';
    this.emo = name;
    const F = FACES[name];
    FACE_KEYS.forEach(k => { this.faceT[k] = F[k] || 0; });
    if (gaze) this.look(gaze);
    else if (name === 'tsun') this.look('away');
    else if (name === 'sad') this.look('down');
    else if (name === 'cold') this.look('aside');
    return this;
  },
  motion(name) {
    const d = MOVE[name]; if (!d) return;
    this.play(d.m, { fade: d.fade, exp: d.exp });
  },
  /* 直接播模型动作；name 可以是数组（随机挑一个）；exp 只在该动作期间生效 */
  play(name, o = {}) {
    if (!this.ready) return;
    const m = Array.isArray(name) ? pick(name) : name;
    this.idle.play = this.t + 2.2;
    try {
      const p = this.player.playMotion(m, { loop: false });
      if (p && p.catch) p.catch(() => { });
    } catch (e) { return; }
    if (o.exp) {
      try { this.player.setExpression(o.exp); } catch (e) { }
      this._expToken = (this._expToken || 0) + 1;
      this._expUntil = this.t + (o.expMs ? o.expMs / 1000 : 3.2);
    }
  },
  setIdle(mood) {
    this.idleMood = IDLE_POOL[mood] ? mood : 'neutral';
    this.idle.mood = this.idleMood;
    this.idle.next = Math.max(this.idle.next, this.t + 3);
  },
  /* mode: user 看你 / pointer 跟手指 / away 别过脸 / down 低头 / aside 侧目 / read 读证据 / up / {x,y} */
  look(mode) { this.gaze.mode = mode; },
  pointer(x, y) { this.gaze.px = x; this.gaze.py = y; this.gaze.lastMove = this.t; },

  /* ── 全息滤镜（DOM filter，不是渲染管线） ── */
  holoTo(o) { Object.assign(this.fxT, o); },
  rim(hex) {
    const n = typeof hex === 'string' ? parseInt(hex.slice(1), 16) : hex;
    this.rimT = [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
  },
  glitch(ms = 260, amt = 1) { this.fx.glitch = amt; this.fxT.glitch = 0; this._glitchUntil = this.t + ms / 1000; },

  /* ── 主线环（世界空间，跟着她缩放） ── */
  setRings(rings) {
    this.rings = rings.map((g, i) => ({ ...g, i }));
    const n = rings.length;
    this.rings.forEach((g, i) => {
      if (g.final) { g.ry = NY.hair + .20; g.rx = .42; g.ryy = .055; }
      else {
        const m = Math.max(1, n - 2), f = m ? i / m : 0;
        g.ry = lerp(NY.feet + .20, NY.shoulder - .06, f);
        g.rx = lerp(.30, .25, f); g.ryy = g.rx * lerp(.22, .15, f);
      }
      if (this.ringMul[i] == null) this.ringMul[i] = 1;
      if (this.ringVis[i] == null) this.ringVis[i] = 1;
      if (this.ringScale[i] == null) this.ringScale[i] = new Spring(1, 140, .55);
    });
    this.ringMul.length = this.ringVis.length = n;
  },
  ringPoint(i, side = 1) {                      // 环的右/左端点（给 DOM 标签挂线用）
    const g = this.rings[i]; if (!g) return null;
    return this.toScreen(side * g.rx * (this.ringScale[i] ? this.ringScale[i].x : 1), g.ry);
  },
  igniteRing(i) { this.ringAnim.push({ i, t0: this.t, kind: 'ignite' }); },
  hideRings() { this.ringVis = this.ringVis.map(() => 0); },
  showRing(i) { this.ringVis[i] = 1; const s = this.ringScale[i]; if (s) { s.x = .15; s.v = 0; s.set(1); } },
  dimRing(i, v) { if (i >= 0) this.ringMul[i] = v; },
  shock(color = 0x38e1ff, w = NY.waist, power = 1) { this.shocks.push({ t0: this.t, color, w, power }); },

  /* ── 每帧（自己的 rAF：镜头 / 环 / 情绪；模型由播放器自己 30fps 推进） ── */
  _tick(dt) {
    if (!this.cam || !this.cx) return;        // 模型没就绪前也要安全：主循环每一帧都会喊它
    dt = Math.min(dt, .05); this.t += dt;
    const c = this.cam;
    for (const k in c) c[k].step(dt);

    // 情绪弹性插值
    const r = 1 - Math.pow(.004, dt);
    FACE_KEYS.forEach(k => { this.face[k] += ((this.faceT[k] || 0) - this.face[k]) * r; });
    this._applyFace();                        // 颊 / 眉 / 头身角：每帧写一次（播放器每帧会重置）
    this._blinkMul(dt);
    // 全息滤镜：目标值 → 现值
    const f = this.fx, ft = this.fxT, q = 1 - Math.pow(.02, dt);
    if (this._glitchUntil && this.t > this._glitchUntil) this._glitchUntil = 0;
    for (const k in ft) f[k] += (ft[k] - f[k]) * (k === 'glitch' && this._glitchUntil ? 0 : q);
    for (let i = 0; i < 3; i++) this.rimColor[i] += (this.rimT[i] - this.rimColor[i]) * q;
    this._holo();
    // 待机：她闲下来会自己演点小动作
    if (this.ready && this.t > this.idle.next && this.idle.play < this.t) {
      this.idle.next = this.t + rand(7, 15);
      const pool = IDLE_POOL[this.idleMood] || IDLE_POOL.neutral;
      this.play(pick(pool), { fade: .45 });
    }
    // 表情归还（动作表情只借一会儿）
    if (this._expUntil && this.t > this._expUntil) {
      this._expUntil = 0;
      const want = EMO_EXP[this.emo] || EMO_EXP.neutral;
      if (this.player && this.player.expression !== want) { try { this.player.setExpression(want); } catch (e) { } }
    }
    this._exShake(dt);
    this._drawRings(dt);
    for (const fn of this.onTick) fn(dt);
  },
  /* 眨眼：默认交给她自己（和动作/呼吸同一套节拍）；只有「睡了/装死」这类强压眼皮才自己排程 */
  _blinkMul(dt) {
    const want = (this.faceT.lid < .5 && this.face.lid < .5);
    if (!want) { this.blinkMul = 1; this._blink = { next: 0, t: -1 }; return; }
    const b = this._blink;
    if (b.t < 0) { if (!b.next) b.next = this.t + rand(1.2, 3); if (this.t > b.next) b.t = 0; else { this.blinkMul = 1; return; } }
    b.t += dt; const p = b.t;
    this.blinkMul = p < .07 ? 1 - p / .07 : p < .19 ? (p - .07) / .12 : 1;
    if (p >= .19) { b.t = -1; b.next = this.t + rand(2.2, 5.5); }
  },
  /* 表情微动：让脸活着。幅度极小（眉毛 ±0.05、嘴 ±0.03），只在待机时呼吸般地动 */
  _exShake(dt) {
    this._sT = (this._sT || 0) + dt;
    const t = this._sT, F = this.face;
    // 两个不同周期叠加 → 不会看出循环
    this.exShake = {
      brow: .5 * Math.sin(t * .55) * .5 + .5 * Math.sin(t * .23 + 1.1) * .5,
      browA: .5 * Math.sin(t * .41 + 2.2) * .5 + .5 * Math.sin(t * .17) * .5,
      mouth: .5 * Math.sin(t * .37 + .7) * .5 + .5 * Math.sin(t * .19 + 2.6) * .5,
      head: .5 * Math.sin(t * .29 + 1.7) * .5 + .5 * Math.sin(t * .13 + .4) * .5,
    };
  },
  /* 全息：把滤镜参数写成元素上的 CSS filter（模型是 WebGL 画布，只能整体调色） */
  _holo() {
    if (!this.el) return;
    const f = this.fx, c = this.rimColor;
    const rgb = `${(c[0] * 255) | 0},${(c[1] * 255) | 0},${(c[2] * 255) | 0}`;
    this.el.style.filter =
      `saturate(${Math.max(0, f.sat).toFixed(2)}) ` +
      `brightness(${f.bright.toFixed(2)}) ` +
      `drop-shadow(0 0 ${(1 + f.rim * 3).toFixed(1)}px rgba(${rgb},${(f.rim * .55).toFixed(2)}))`;
  },

  _gaze(dt) {
    const g = this.gaze; let tx = 0, ty = 0;
    const head = this.toScreen(0, NY.eyes);
    switch (g.mode) {
      case 'pointer':
        if (this.t - g.lastMove < 2.8) {
          tx = clamp((g.px - head.x) / (this.W * .55), -1, 1); ty = clamp((head.y - g.py) / (this.H * .45), -1, 1);
        } else {
          if (this.t > g.sacc) { g.sacc = this.t + rand(1.6, 4); g.sx = Math.random() < .3 ? rand(-.5, .5) : rand(-.12, .12); g.sy = Math.random() < .3 ? rand(-.3, .25) : rand(-.08, .08); }
          tx = g.sx; ty = g.sy;
        }
        break;
      case 'user':
        if (this.t > g.sacc) { g.sacc = this.t + rand(1.2, 3.2); g.sx = rand(-.1, .1); g.sy = rand(-.06, .08); }
        tx = g.sx; ty = g.sy; break;
      case 'away': tx = .85; ty = .05; break;
      case 'aside': tx = -.55; ty = -.1; break;
      case 'down': tx = -.25; ty = -.75; break;
      case 'read': tx = Math.sin(this.t * 7) * .45; ty = -.35; break;
      case 'up': tx = 0; ty = .8; break;
      default:
        if (typeof g.mode === 'object') { tx = clamp((g.mode.x - head.x) / (this.W * .5), -1, 1); ty = clamp((head.y - g.mode.y) / (this.H * .4), -1, 1); }
    }
    const L = this.lookT;
    L.x.set(tx); L.y.set(-ty);           // 参数的 Y 向上为正，屏幕坐标向下为正
    g.x = L.x.step(dt); g.y = L.y.step(dt);
    if (this.ch) { try { this.ch.setLookX(g.x); this.ch.setLookY(g.y); } catch (e) { } }
  },

  /* ② 情绪面板：只做「必须每帧重设」的两件事——头/身角度与说话时的头部轻晃。
     脸颊/眉/嘴都放到 _post 里写（那里在模型算完之后、渲染之前，最可靠） */
  _applyFace() {
    if (!this.ch) return;
    const F = this.face;
    const bob = Voice.mouth > .08 ? Math.sin(this.t * 9.5) * 2.4 * Voice.mouth : 0;
    try {
      this.ch.setAngleX(F.ax);
      this.ch.setBodyAngleX(F.ax * .3);
    } catch (e) { }
    this._bob = F.ay + bob; this._bobZ = F.az + bob * .4;
  },
  /* 参数写入器：名字 → 索引 → 值（索引不存在就跳过，换模型不炸） */
  _setter(pr) {
    const P = pr || (this.ch && this.ch.params);
    return (id, v, w) => {
      try {
        const i = P.index.get(id);
        if (i !== undefined) P.override(i, v, w == null ? 1 : w);
      } catch (e) { }
    };
  },
  /* ③ 后置覆写：播放器算完这一帧、引擎执行之前，补几个它不负责的量。
     ⚠ 原则：情绪「有话说」才覆写；中性时一律放行，别把动作自己的头部/身体曲线压平 */
  _post(pr) {
    const F = this.face, ov = this._setter(pr);
    // 眼睑：模型自带眨眼 × 本 App 的眨眼 / 眼睑
    // ⚠ override(索引, 值, 权重)：权重漏传会变成 1-undefined=NaN，参数一旦 NaN
    //    依赖它驱动的眉毛/睫毛层会整片消失（脸会变"贴纸"），所以权重必须显式给
    const mul = F.lid * this.blinkMul;
    if (mul < .997) {
      for (const id of ['ParamEyeLOpen', 'ParamEyeROpen']) {
        const i = pr.index.get(id);
        if (i !== undefined) pr.override(i, clamp(pr.value[i] * mul, 0, 1), 1);
      }
    }
    const sm = F.smile;
    if (Math.abs(sm) > .02) { ov('ParamEyeLSmile', sm, .9); ov('ParamEyeRSmile', sm, .9); }
    // 眉：中性时一个字都不动（眉形是模型的本钱）；情绪说话时只在动作算出的值上加一个偏移，
    //     绝不写成绝对值——写绝对值会把动作/物理的眉形曲线整条抹平，脸会变"贴纸"
    if (Math.abs(F.brow) > .02) {
      for (const id of ['ParamBrowLY', 'ParamBrowRY']) {
        const i = pr.index.get(id);
        if (i !== undefined) pr.override(i, pr.value[i] + F.brow, .85);
      }
    }
    // 头：Y/Z 播放器不管（它只暴露 angleX/bodyAngleX），但只有情绪给出角度时才压
    const ay = this._bob || 0, az = this._bobZ || 0;
    if (Math.abs(ay) > .25) ov('ParamAngleY', ay, .8);
    if (Math.abs(az) > .25) ov('ParamAngleZ', az, .8);
    // 嘴：情绪底色 + 说话包络（两者都没有就交还给动作，免得动画里的口型被吃掉）
    const talk = (typeof Voice !== 'undefined' ? Voice.mouth : 0) * .95;
    if (Math.abs(F.mouth) > .02 || talk > .02) {
      ov('ParamMouthForm', F.mouth);
      ov('ParamMouthOpenY', clamp(Math.max(F.open || 0, talk * ((F.mouth + 1) / 2 * .85 + .15)), 0, 1));
    }
    // 半身：有情绪角度时压一点，其余交给动作 + 物理
    if (Math.abs(F.ax) > .4) {
      for (const id of ['ParamBodyAngleY', 'ParamBodyAngleZ']) {
        const i = pr.index.get(id);
        if (i !== undefined) pr.override(i, pr.value[i] * .45 + F.ax * .25, 1);
      }
    }
    // 呼吸：交给她自己的节拍（睡了就慢一倍、浅一半）
    if (pr.index.has('ParamBreath')) {
      const z = this.dozeMul || 1;
      ov('ParamBreath', .5 + .34 * Math.sin(this.t * (1.25 / z) + 1.7), 1);
    }
  },
  _wrap(orig) {
    const h = this;
    return function () {
      orig();
      if (!h._hookOK) return;
      const pr = h.ch && h.ch.params;
      if (!pr) return;
      try { h._post(pr); } catch (e) { if (h._hookErr !== String(e)) { h._hookErr = String(e); console.warn('[stage] post hook off:', e); } h._hookOK = false; }
    };
  },

  /* ── 环：世界空间的椭圆投影到屏幕，加色画在 2D 画布上 ── */
  _drawRings(dt) {
    const g = this.cg, cv = this.cx; if (!g) return;
    const d = this._rdpr;
    g.setTransform(d, 0, 0, d, 0, 0);
    g.clearRect(0, 0, this.W, this.H);
    this.ringA += (this.ringAT - this.ringA) * Math.min(1, dt * 4);
    const S = this.cam.S.x, px = 1 / S, t = this.t, dim = this.fx.bright * this.ringA;
    const arc = (cx, cy, rx, ry, a0, a1, w, col, al) => {
      if (al <= .003 || a1 <= a0) return;
      g.strokeStyle = hexa(col, Math.min(1, al));
      g.lineWidth = Math.max(.4, w * px);
      const n = Math.max(4, Math.ceil((a1 - a0) / .07));
      g.beginPath();
      for (let i = 0; i <= n; i++) {
        const a = a0 + (a1 - a0) * i / n, x = cx + rx * Math.cos(a), y = cy + ry * Math.sin(a);
        i ? g.lineTo(x, y) : g.moveTo(x, y);
      }
      g.stroke();
    };
    const TH = Math.PI * 2;
    const glow = (cx, cy, rx, ry, a0, a1, col, al, core = 1.6) => {
      if (al <= .004 || rx <= 0 || ry <= 0) return;
      let s = ((a0 % TH) + TH) % TH;
      const e = s + (a1 - a0);
      const pts = [[s, e, 0], [0, Math.PI, 1], [Math.PI, TH, 0], [TH, TH + Math.PI, 1], [TH + Math.PI, TH * 2, 0]];
      for (const [a, b, front] of pts) {
        const lo = Math.max(a, s), hi = Math.min(b, e);
        if (hi <= lo) continue;
        const w = front ? 1 : .55;
        g.globalCompositeOperation = 'lighter';
        arc(cx, cy, rx, ry, lo, hi, 9, col, al * .07 * w);
        arc(cx, cy, rx, ry, lo, hi, 4, col, al * .16 * w);
        arc(cx, cy, rx, ry, lo, hi, core, col, al * .9 * w);
        g.globalCompositeOperation = 'source-over';
      }
    };
    g.save();
    this.rings.forEach((ring, i) => {
      const vis = this.ringVis[i]; if (!vis) return;
      const sc = this.ringScale[i].step(dt);
      const p = this.toScreen(0, ring.ry);
      const rx = ring.rx * sc * S, ry = ring.ryy * sc * S;
      const cy = p.y, cxp = p.x, mul = this.ringMul[i] * dim;
      if (ring.state === 'done') {
        glow(cxp, cy, rx, ry, 0, TH, ring.final ? 0xe9fbff : 0x38e1ff, .95 * mul, ring.final ? 2.4 : 1.6);
        for (let j = 0; j < 12; j++) {           // 刻度：慢慢转
          const a = j * Math.PI / 6 + t * .12;
          const x = cxp + rx * Math.cos(a), y = cy + ry * Math.sin(a);
          g.strokeStyle = hexa(0xbff6ff, .7 * mul); g.lineWidth = Math.max(.4, 1.2 * px);
          g.beginPath(); g.moveTo(x, y - 4 * px); g.lineTo(x, y + 4 * px); g.stroke();
        }
      } else if (ring.state === 'cur') {
        const pulse = .55 + .45 * Math.sin(t * 2.6);
        glow(cxp, cy, rx, ry, 0, TH, 0x38e1ff, (.38 + .3 * pulse) * mul, 1.3);
        const a = t * 1.15;                      // 彗星
        for (let j = 0; j < 14; j++) {
          const s2 = a - .95 + j * .068;
          glow(cxp, cy, rx, ry, s2, s2 + .07, 0xe9fbff, (j / 14) * .95 * mul, 2.2);
        }
        const na = t * .55, x = cxp + rx * Math.cos(na), y = cy + ry * Math.sin(na);
        const dd = 5 * px;
        g.fillStyle = hexa(0xe9fbff, mul);
        g.beginPath(); g.moveTo(x, y - dd * 1.4); g.lineTo(x + dd, y); g.lineTo(x, y + dd * 1.4); g.lineTo(x - dd, y); g.closePath(); g.fill();
      } else {
        const segs = ring.final ? 24 : 36, gap = TH / segs;
        if (ring.final) glow(cxp, cy, rx, ry, 0, TH, 0x38e1ff, .32 * mul, 1);
        for (let j = 0; j < segs; j++) {
          const s2 = j * gap + t * .05;
          arc(cxp, cy, rx, ry, s2, s2 + gap * .45, 1.2, 0x38e1ff, .5 * mul);
        }
      }
    });
    // 待机扫描：一圈光从脚下扫到头顶，再扫回来
    this.scan += (this.scanT - this.scan) * Math.min(1, dt * 3);
    if (this.scan > .01) {
      const ph = (Math.sin(t * 1.1 - Math.PI / 2) + 1) / 2, wy = lerp(NY.feet + .06, NY.hair + .06, ease.inOutCubic(ph));
      const p = this.toScreen(0, wy), a = this.scan;
      glow(p.x, p.y, .70 * S, .125 * S, 0, TH, 0x9ff0ff, .95 * a, 2);
      for (let j = 1; j <= 5; j++) { const dy = j * 7 * (Math.cos(t * 1.1 - Math.PI / 2) > 0 ? -1 : 1); glow(p.x, p.y + dy, .70 * S, .125 * S, 0, TH, 0x38e1ff, a * .16 * (1 - j / 6), 1); }
    }
    // 点燃动画：一圈外扩的光
    this.ringAnim = this.ringAnim.filter(an => {
      const q = (t - an.t0) / .9; if (q >= 1) return false;
      const ring = this.rings[an.i]; if (!ring) return false;
      const e = ease.outCubic(q), rx = ring.rx * (1 + .55 * e) * S, ry = ring.ryy * (1 + .55 * e) * S;
      const p = this.toScreen(0, ring.ry);
      glow(p.x, p.y, rx, ry, 0, TH, 0xe9fbff, (1 - q) * 1.2, 2.6);
      if (q < .25) glow(p.x, p.y, ring.rx * S, ring.ryy * S, 0, TH, 0xffffff, (1 - q * 4) * 1.5, 4);
      return true;
    });
    this.shocks = this.shocks.filter(s => {
      const q = (t - s.t0) / 1.15; if (q >= 1) return false;
      const e = ease.outCubic(q), rx = (80 + 1100 * e * s.power) * px, ry = rx * .2;
      const p = this.toScreen(0, s.w);
      glow(p.x, p.y, rx, ry, 0, TH, s.color, Math.pow(1 - q, 1.6) * 1.4, 3);
      return true;
    });
    g.restore();
  },

  /* 戳她：模型是 WebGL，没有命中树；按她此刻的像素占位与实测半宽判断 */
  hit(x, y) {
    if (!this.ready || !this.geo) return false;
    const G = this.geo;
    const a = this.toScreen(0, G.top), b = this.toScreen(0, G.feet);
    if (y < a.y || y > b.y) return false;
    const h = b.y - a.y, f = clamp((y - a.y) / h, 0, 1);   // 0 头顶 → 1 脚底
    // 头窄、肩最宽、裙摆再宽一点：一条宽度曲线近似她
    const w = h * G.half * lerp(.42, 1, Math.min(1, f / .24)) * (f > .5 ? lerp(1, 1.15, (f - .5) / .5) : 1);
    return Math.abs(x - a.x) < w;
  },

  /* 截战报：她 + 环 叠成一张 canvas（异步：要先借一帧把 WebGL 内容读出来） */
  async snapshot(o = {}) {
    try {
      const p = this.player; if (!p) return null;
      const was = p.paused;
      p.paused = true;
      try { await this.session.step({ draw: true }); } catch (e) { }
      const cv = document.createElement('canvas');
      const W = this.W, H = this.H, s = 2;
      cv.width = W * s; cv.height = H * s;
      const g = cv.getContext('2d');
      g.setTransform(s, 0, 0, s, 0, 0);
      const m = this.el;
      if (m) {
        const r = m.getBoundingClientRect(), ar = this.host.getBoundingClientRect();
        const dx = (r.left - ar.left) * (W / (ar.width || 1)), dy = (r.top - ar.top) * (H / (ar.height || 1));
        const dw = r.width * (W / (ar.width || 1)), dh = r.height * (H / (ar.height || 1));
        g.save();
        g.filter = `saturate(${this.fx.sat.toFixed(2)}) brightness(${this.fx.bright.toFixed(2)})`;
        try { g.drawImage(this.cv, dx, dy, dw, dh); } catch (e) { }
        g.restore();
      }
      if (this.cx) g.drawImage(this.cx, 0, 0, W, H);
      p.paused = was;
      return cv;
    } catch (e) { console.warn(e); return null; }
  },
};

/* #rrggbb + alpha → rgba() */
function hexa(v, a) {
  const n = typeof v === 'string' ? parseInt(v.slice(1), 16) : v;
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a.toFixed(3)})`;
}
/* 列主序 4×4：a·b */
function mul4(a, b) {
  const o = new Float32Array(16);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) {
    let t = 0; for (let k = 0; k < 4; k++) t += a[k * 4 + r] * b[c * 4 + k];
    o[c * 4 + r] = t;
  }
  return o;
}
function loadScript(src) {
  return new Promise((res, rej) => {
    const s = document.createElement('script');
    s.async = false; s.src = new URL(src, location.href).href;
    s.onload = () => res(); s.onerror = () => rej(new Error('脚本加载失败：' + src));
    document.head.appendChild(s);
  });
}
