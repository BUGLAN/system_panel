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
