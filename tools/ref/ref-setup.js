/* ═══════════════════════════════════════════════════════════
   标准参考态 —— 每次截图比对前先跑这一段
   （agent-browser --session X eval "$(Get-Content tools/ref/ref-setup.js -Raw)"）

   用法：把文件末尾的 `capPage('lobby')` 改成要抓的页，再截图。
   可用的页：lobby / onboard / dispatch / exec / result / fail /
             archive / supply / system / main / banner / rings

   要点：
     1. 先 `Store.veteran()` 恢复原型自带的「老宿主 · 第 23 天」，
        否则会拿到被玩脏的存档（踩过：items 少键 → 印「持有 ×undefined」）
     2. 重载后 `#boot` 还在等点击，必须显式关掉
     3. `#stage` 里有两样东西：Live2D 模型（Flutter 还没有）和**环的画布**
        （`stage.js` L127 `cv.id='ringCv'`）。不能整个 display:none ——
        那样会把环一起藏掉（踩过：13 张参考图全缺环）。先把环画布挪到 `#app`
        下（两者都是 inset:0，几何不变），再藏 `#stage`
     4. 开机态 `holoTo({bright:.34})`，恢复靠 tick 补间 —— 清掉 onTick 后
        会永远停在 .34（环只有 34% 亮）。这里直接落位
     5. 启动时 `App.boot()` 会把 8 个环全部 showRing；`_drawRings` 也挂 tick 上，
        所以清掉 onTick 后要**手动补画一次**，否则画布是空的
   ═══════════════════════════════════════════════════════════ */

/* ── 环：同步到当前相机并补画一帧 ───────────────────────────── */
/* ⚠️ `main.js` L25 有一个**无条件的 rAF 主循环**：每帧 `Stage._tick(dt)`
   → `t += dt` 并重画环。所以光设 `Stage.t = 0` 没用，下一帧就被覆盖，
   截图里的相位（彗星位置 / 虚线相位 / 刻度角度）是随机的 ——
   这就是逐环比对里那 ±9 的来源。这里把 t 钉死在 0。 */
function refFreezeT() {
  if (typeof Stage === 'undefined' || Stage.__tFrozen) return;
  var orig = Stage._drawRings.bind(Stage);
  Stage._drawRings = function (dt) { Stage.t = 0; return orig(dt); };
  Stage.__tFrozen = true;
}

function refRings(t) {
  if (typeof Stage === 'undefined' || !Stage.setRings) return;
  refFreezeT();
  Stage.setRings(Store.S.rings);
  for (var i = 0; i < Store.S.rings.length; i++) Stage.showRing(i);
  Stage.t = typeof t === 'number' ? t : 0;
  for (var k = 0; k < 80; k++) Stage._drawRings(0.016); // 让 ringScale / ringA 收敛
}

/* ── 基础清理 ──────────────────────────────────────────────── */
function refSetup(mode, cam) {
  Store.veteran();

  // ① 环画布挪出 #stage（下面要藏 #stage）
  var cv = document.getElementById('ringCv');
  if (cv && cv.parentElement && cv.parentElement.id === 'stage') {
    document.getElementById('app').appendChild(cv);
  }
  // ② 全息参数落位（别停在开机态的 .34）
  if (Stage.holoTo) {
    Stage.holoTo({ sat: 1, bright: 1, rim: .55, scan: .2, lift: .5 });
    Object.assign(Stage.fx, Stage.fxT);
  }
  // ③ 关开机覆盖层
  var boot = document.getElementById('boot');
  if (boot) {
    boot.style.transition = 'none';
    boot.style.opacity = 0;
    boot.style.display = 'none';
  }
  // ④ 摆状态
  App.setMode(mode);
  Stage.setCam(cam, true);
  var st = document.getElementById('stage');
  if (st) st.style.display = 'none';
  Stage.onTick.length = 0; // 每帧驱动的 transform 会冻住，下面该归位的都归位

  // ⑤ 清空所有覆盖层（内联 opacity 也要清 —— 它会压过 .on 类）
  ['plate', 'plateAlt', 'exec', 'result', 'failv'].forEach(function (id) {
    var e = document.getElementById(id);
    if (e) { e.classList.remove('on'); e.style.opacity = ''; e.innerHTML = ''; }
  });
  Sheet.close();
  var mv = document.getElementById('mainv');
  if (mv) { mv.classList.remove('on'); mv.innerHTML = ''; }
  var rl = document.getElementById('ringLabels');
  if (rl) { rl.classList.remove('on'); rl.innerHTML = ''; }
  var tag = document.getElementById('ringTag');
  if (tag) tag.classList.remove('on');
  var b = document.getElementById('banner');
  if (b) { b.classList.remove('on'); b.innerHTML = ''; }
  document.getElementById('choices').innerHTML = '';
  document.getElementById('ask').classList.remove('on');
  var veil = document.getElementById('veil');
  veil.style.opacity = 0;
  veil.style.transition = 'none';
  var pill = document.getElementById('execPill');
  if (pill) pill.classList.remove('on');
  if (typeof MainV !== 'undefined') MainV.hide();
  var ln = document.getElementById('line');
  ln.style.transition = 'none';
  ln.classList.remove('soft');
  ln.classList.remove('on');
  var eye = document.getElementById('exEye');
  if (eye) eye.style.transform = 'none'; // 眨眼/口型动画会冻在半截
  return mode;
}

/* ── 字幕 ──────────────────────────────────────────────────── */
function refLine(y, html, mood) {
  var ln = document.getElementById('line');
  Line.at(y);
  document.getElementById('lineTxt').innerHTML = html;
  document.getElementById('lineMood').textContent = mood;
  ln.classList.add('on');
}

/* ── 当前环挂签（大厅里才有） ─────────────────────────────── */
function refRingTag() {
  var S = Store.S, ci = Store.curRing();
  if (ci < 0) return;
  document.getElementById('rtNum').innerHTML =
    'R' + (ci + 1) + '<small>/' + S.rings.length + '</small>';
  document.getElementById('rtName').textContent = S.rings[ci].final
    ? S.goal.short
    : S.rings[ci].n;
  document.getElementById('ringTag').classList.add('on');
}

function refBanner(kick, text, glyph) {
  var b = document.getElementById('banner');
  b.innerHTML =
    '<span class="glyph">' + glyph + '</span><span><small>' + kick +
    '</small><b>' + text + '</b></span>';
  b.style.transition = 'none';
  b.classList.add('on');
}

/* ── 各页 ──────────────────────────────────────────────────── */
function capPage(page) {
  var S = Store.S;

  if (page === 'lobby' || page === 'banner') {
    refSetup('lobby', 'lobby');
    App.setWord('半马', false);
    HUD.render(); Dock.render();
    refRingTag();
    refLine(Stage.H * .6, '<span class="c on">我手里有 4 单。都是给你的。</span>', '尚可');
    if (page === 'banner') refBanner('见面礼', '双倍卡 ×1', '×2');
    App.place(); refRings();
    return page;
  }

  if (page === 'onboard') {
    refSetup('onboard', 'boot');
    App.setWord('SYSTEM', true);
    refLine(Stage.H * .55,
      '<span class="c on">说吧。你想变成什么样？<em>一句话</em>。</span>', '专注');
    document.getElementById('askPs').textContent = '目标 ›';
    var inp = document.getElementById('askIn');
    inp.placeholder = '比如：三个月跑完半马';
    inp.value = '';
    document.getElementById('askPresets').innerHTML =
      ['三个月跑完半马', '一个月早睡早起', '考研上岸', '半年减重 10 斤', '学会画画', '变优秀']
        .map(function (t) { return '<button type="button">' + t + '</button>'; }).join('');
    var f = document.getElementById('ask');
    f.style.transition = 'none';
    f.classList.add('on');
    App.place(); refRings();
    return page;
  }

  if (page === 'dispatch') {
    // 玻璃板是异步演出：build → land → rankRoll → engrave，得分开调
    refSetup('dispatch', 'talk');
    window.__T = Store.head();
    Plate.fast = true;
    Plate.build(window.__T);
    Plate.land();
    return page + ':1';
  }

  if (page === 'dispatch2') {
    Plate.rankRoll(window.__T.r);
    return page;
  }

  if (page === 'dispatch3') {
    Plate.engrave();
    return page;
  }

  if (page === 'dispatch4') {
    var pl = document.getElementById('plate'), pa = document.getElementById('plateAlt');
    pl.style.transition = 'none'; pl.style.opacity = 1; pl.classList.add('on');
    Plate.alt([{ t: '换一个', v: 'x' }, { t: '等会儿', v: 'y' }], function () {});
    pa.style.transition = 'none'; pa.style.opacity = ''; pa.classList.add('on');
    refLine(Stage.H - 568, '<span class="c on">接不接？</span>', '监视');
    App.place(); refRings();
    return page;
  }

  if (page === 'exec') {
    refSetup('exec', 'exec');
    Store.accept(Store.head());
    // ⚠️ 一定要现取 `Store.S` —— `refSetup()` 里的 `Store.veteran()` 会**换掉整个
    //    Store.S 对象**，在 capPage 顶部捕获的引用是旧的（踩过：这里静默抛异常，
    //    截图里执行面板整个不见了）
    Store.S.active.startAt = Clock.now() - 7 * 60000;
    App.exec();
    document.getElementById('exEye').style.transform = 'none';
    App.place(); refRings();
    return page;
  }

  if (page === 'result') {
    refSetup('result', 'result');
    var T = Store.head();
    ResultUI.build({
      task: T, before: { lv: 7, exp: 214, need: 340 }, baseExp: 50, exp: 50,
      coin: 24, attrs: { '体': 1, '力': 1 }, streak: 6, streakUp: false,
      crit: false, dbl: false, ringClear: 4, near: 0, photos: 0, chance: 0.12,
    });
    ['rsGlyph', 'rsHead', 'rsCard', 'rsSave'].forEach(function (k) {
      document.getElementById(k).classList.add('on');
    });
    document.getElementById('rsExp').textContent = '50';
    document.getElementById('rsBarI').style.width = (264 / 340 * 100) + '%';
    document.getElementById('rsNeed').textContent = '264 / 340';
    ResultUI.chip('<b>+24</b>', 'coin');
    ResultUI.chip('体质 <b>+1</b>');
    ResultUI.chip('力量 <b>+1</b>');
    [].forEach.call(document.querySelectorAll('#rsGain .chip'), function (c) {
      c.classList.add('on');
    });
    var nr = document.getElementById('rsNear');
    nr.innerHTML = '本单 0 份证据 · 暴击率只有 <b>12%</b>';
    nr.classList.add('on');
    App.place(); refRings();
    return page;
  }

  if (page === 'fail') {
    refSetup('fail', 'fail');
    var v = document.getElementById('veil');
    v.style.opacity = .6;
    var fv = document.getElementById('failv');
    fv.innerHTML = '<p class="fv-rec">认输 · 已记录 <b>20:02</b></p>' +
      '<div class="fv-remedy" id="fvRem"></div>';
    fv.classList.add('on');
    var rem = document.getElementById('fvRem');
    rem.innerHTML = '<span class="kick">补救 · REMEDY</span>' +
      '<b>跑完 8 公里，跑后拉伸 10 分钟</b>（做一半）· 35 分钟<br>' +
      '截止 明天 20:02 · D 级 · 做到了，这一笔划掉';
    rem.classList.add('on');
    var ln = document.getElementById('line');
    ln.classList.add('soft');
    refLine(Stage.H * .47,
      '<span class="c on">补救的路，我给你留着：明天 20:02 前，做一半。做到了，这次不算。</span>',
      '待机');
    document.getElementById('choices').innerHTML =
      '<button class="ch main on"><span>……接。</span></button>' +
      '<button class="ch on"><span>今天算了。</span></button>';
    App.place(); refRings();
    return page;
  }

  if (page === 'archive' || page === 'supply' || page === 'system') {
    refSetup('sheet', 'panel');
    Sheet.open(page);
    Beam.place();
    App.place(); refRings();
    return page;
  }

  if (page === 'main') {
    refSetup('main', 'full');
    App.setWord('半马', false);
    MainV.show();
    MainV.detail(4);
    document.getElementById('line').classList.remove('on');
    App.place(); refRings();
    return page;
  }

  if (page === 'rings') {
    refSetup('main', 'full');
    App.setWord('半马', false);
    MainV.show();
    document.getElementById('line').classList.remove('on');
    App.place(); refRings();
    return page;
  }

  return 'unknown:' + page;
}

capPage('lobby');
