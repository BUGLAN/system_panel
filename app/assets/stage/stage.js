/* ═══════════════════════════════════════════════════════════
 *  舞台页 —— 只做一件事：把她渲染出来，并把把手交给 Flutter。
 *
 *  为什么单独搞这一页（路线 ②，理由见 app/STAGE-OPTIONS.md）：
 *  原型那个播放器（`ournotes-live2d.element.min.js`）认识的是**原始 prefab 数据**，
 *  换任何第三方原生插件都得先写转换器、而且渲染结果还得赌。直接用原型自己的
 *  播放器，渲染结果就是**同一份**。
 *
 *  初始化照抄原型 `stage.js` L112-147：
 *    · **动态 `import()` 播放器模块，再手动 `defineOurnotesLive2D()` 注册** ——
 *      那个模块只导出、不自注册，而且它是 ES 模块，不能当普通 script 挂
 *      （踩过：普通 script 加载会在解析阶段失败，且报错早于 onerror 注册，毫无信号）
 *    · 建 `<ournotes-live2d>`，样式 `left:50%;top:0;translateX(-50%);height:100%;width:auto`
 *    · `playerOpts = { pixelRatio: 2 }`
 *    · 监听 `progress` / `ready` / `error`
 *    · `setAttribute('src', <清单 URL>)`
 *
 *  与 Flutter 的通信：`StageBridge.postMessage(JSON)`；Flutter 用
 *  `runJavaScriptReturningResult('Stage.probe()')` 这类调用进来。
 * ═══════════════════════════════════════════════════════════ */
(async function () {
  'use strict';

  var ready = false;

  function post(m) {
    try { StageBridge.postMessage(JSON.stringify(m)); } catch (e) { /* 通道没注册就当没有 */ }
  }

  // ⚠️ 先把 JS 异常抓到手 —— WebView 里的错误在 Dart 那边看不见，
  //    `runJavaScriptReturningResult` 只会给一个 undefined，排查全靠猜。
  window.addEventListener('error', function (e) {
    post({ t: 'jserror', message: String(e.message || e.error || 'error') });
  });
  window.addEventListener('unhandledrejection', function (e) {
    post({ t: 'jserror', message: 'unhandled: ' + String((e.reason && e.reason.message) || e.reason) });
  });

  /* ── 1) 注册播放器元素（原型 stage.js L112-115 同款） ── */
  try {
    var modUrl = new URL('vendor/ournotes-live2d.element.min.js', location.href).href;
    var mod = await import(modUrl);
    if (typeof mod.defineOurnotesLive2D !== 'function') {
      throw new Error('播放器模块没有 defineOurnotesLive2D');
    }
    mod.defineOurnotesLive2D();
  } catch (e) {
    post({ t: 'jserror', message: '注册播放器失败：' + ((e && e.message) || e) });
    return;
  }

  /* ── 2) 建元素、挂上、喂清单 ── */
  var host = document.getElementById('host');
  var el = document.createElement('ournotes-live2d');
  el.id = 'stageCv';
  host.appendChild(el);
  el.playerOpts = { pixelRatio: 2 };

  el.addEventListener('progress', function (e) {
    var d = e.detail || {};
    if (!d.total) return;
    post({ t: 'progress', loaded: d.loaded, total: d.total });
  });
  el.addEventListener('ready', function () {
    ready = true;
    post({ t: 'ready' });
  });
  el.addEventListener('error', function (e) {
    var d = e && e.detail && e.detail.error;
    post({ t: 'error', message: String((d && d.message) || d || 'unknown') });
  });

  var q = new URLSearchParams(location.search);
  var src = q.get('src') || 'model/adv_live2d_sakiko_010_casual_spring_01.json';
  el.setAttribute('src', src);

  /* ── 3.5) 帧率探针：把 rAF 实际刷新率报给 Flutter（诊断掉帧用） ──
   * 每 3 秒汇总一次：fps（平均）、max（最差单帧 ms）、dpr、画布背衬尺寸。
   * Flutter 侧 [Live2DWebState] 收到 `t:'fps'` 后 debugPrint。 */
  (function () {
    var last = performance.now(), acc = 0, n = 0, worst = 0;
    function loop(now) {
      var dt = now - last; last = now;
      if (dt > 0 && dt < 1000) { acc += dt; n++; if (dt > worst) worst = dt; }
      if (acc >= 3000) {
        var sr = el.shadowRoot;
        var cv = (sr && sr.querySelector('canvas')) || document.querySelector('#stageCv canvas');
        post({
          t: 'fps',
          fps: n ? Math.round(1000 / (acc / n)) : 0,
          worstMs: Math.round(worst),
          samples: n,
          dpr: window.devicePixelRatio || 1,
          canvas: cv ? (cv.width + 'x' + cv.height) : 'none'
        });
        acc = 0; n = 0; worst = 0;
      }
      requestAnimationFrame(loop);
    }
    requestAnimationFrame(loop);
  })();

  /* ── 4) 给 Flutter 的把手 ── */
  window.Stage = {
    /** 自检：Flutter 用它确认播放器/会话到底有没有拿到 */
    probe: function () {
      var p = el.player || null;
      var s = (p && p.session) || null;
      return JSON.stringify({
        ready: ready,
        defined: !!customElements.get('ournotes-live2d'),
        hasPlayer: !!p,
        hasSession: !!s,
        hasCharacter: !!(s && s.character),
        srcAttr: el.getAttribute('src') || '',
        charKeys: (s && s.character) ? Object.keys(s.character).slice(0, 40) : []
      });
    },

    /** 相机：直接对元素做 CSS 变换。
     *  原型是在渲染器里乘一个世界空间仿射矩阵（`stage.js` `_camMul`），
     *  对"缩放 + 平移"来说，CSS 变换与它等价，而且不用碰原生。 */
    cam: function (scale, dx, dy) {
      el.style.transform =
        'translateX(-50%) translate(' + dx + 'px,' + dy + 'px) scale(' + scale + ')';
      return true;
    },

    /** 报一个尺寸/几何，供 Flutter 对齐相机 */
    geo: function () {
      var r = el.getBoundingClientRect();
      return JSON.stringify({
        x: r.x, y: r.y, w: r.width, h: r.height,
        inner: window.innerWidth + 'x' + window.innerHeight
      });
    }
  };
})();
