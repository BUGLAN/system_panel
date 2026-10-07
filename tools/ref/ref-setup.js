/* ═══════════════════════════════════════════════════════════
   标准参考态 —— 每次截图比对前先跑这一段（agent-browser eval "$(cat ...)"）
   要点：
     1. 先 `Store.veteran()` 把存档恢复成原型自带的「老宿主 · 第 23 天」，
        否则会拿到被玩脏的存档（踩过：items 少键 → 界面印「持有 ×undefined」）
     2. 重载页面后 `#boot` 覆盖层还在等点击，必须显式关掉
     3. `#stage` 是 WebGL 的 Live2D，Flutter 侧还没上舞台，比对时先隐藏
     4. 每个状态的显隐照 `App.setMode()` 的类名规则来
   ═══════════════════════════════════════════════════════════ */
function refSetup(mode, cam, extra) {
  Store.veteran();
  const boot = document.getElementById('boot');
  if (boot) { boot.style.transition = 'none'; boot.style.opacity = 0; boot.style.display = 'none'; }
  App.setMode(mode);
  Stage.setCam(cam, true);
  const st = document.getElementById('stage');
  if (st) st.style.display = 'none';
  Stage.onTick.length = 0;
  ['plate', 'plateAlt', 'exec', 'result', 'failv'].forEach(function (id) {
    const e = document.getElementById(id);
    if (e) { e.classList.remove('on'); e.style.opacity = 0; e.innerHTML = ''; }
  });
  Sheet.close();
  const rl = document.getElementById('ringLabels');
  if (rl) { rl.classList.remove('on'); rl.innerHTML = ''; }
  document.getElementById('choices').innerHTML = '';
  document.getElementById('veil').style.opacity = 0;
  document.getElementById('veil').style.transition = 'none';
  const pill = document.getElementById('execPill');
  if (pill) pill.classList.remove('on');
  if (typeof MainV !== 'undefined') MainV.hide();
  const ln = document.getElementById('line');
  ln.style.transition = 'none';
  ln.classList.remove('soft');
  Dock.render();
  HUD.render();
  return mode;
}
refSetup('lobby', 'lobby');
Line.at(Stage.H * .6);
document.getElementById('lineTxt').innerHTML =
  '<span class="c on">我手里有 4 单。都是给你的。</span>';
document.getElementById('lineMood').textContent = '尚可';
document.getElementById('line').classList.add('on');
JSON.stringify({
  mode: App.mode,
  cap: document.getElementById('ctaCap').textContent,
  queue: Store.S.queue.length,
  items: Store.S.items,
});
/* ── 藏掉 Live2D 模型，但**留下环** ──────────────────────────────
   环画在 #stage 里的一张独立 canvas 上（stage.js L127 `cv.id='ringCv'`），
   直接把 #stage 设成 display:none 会把环一起藏掉 —— 之前 13 张参考图都缺这一层。
   把环画布挪到 #app 下面（两者都是 inset:0，几何不变）即可。 */
(function () {
  var cv = document.getElementById('ringCv');
  if (cv && cv.parentElement && cv.parentElement.id === 'stage') {
    document.getElementById('app').appendChild(cv);
  }
})();

/* 开机态把全息参数调成了 bright:.34，恢复它靠 tick 补间 —— 清掉 onTick 后
   会永远停在 .34（环只有 34% 亮）。这里直接落到位。 */
if (typeof Stage !== 'undefined' && Stage.holoTo) {
  Stage.holoTo({ sat: 1, bright: 1, rim: .55, scan: .2, lift: .5 });
  Object.assign(Stage.fx, Stage.fxT);
}
