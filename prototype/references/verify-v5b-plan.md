# v5B 交互改版 · 验证执行计划（T4 / task-4 · 第一阶段产物）

> 本文件只是**执行计划**（准备阶段），不含任何结论。实测结论写进 `verify-v5b.md`。
> 状态：**已按本计划执行完毕**（T3 指纹 `5318B94B…`，结果见 `verify-v5b.md`，通过 9/10，第 8 条不通过）。

## 0. 环境与固定动作

- 原型：`cd prototype/app; node server.mjs` → http://localhost:4921（2026-02 准备阶段实测 HTTP 200）
- 浏览器会话：**专用命名会话 `verifier`**，避免动到 lead 的 `default` 会话
  ```powershell
  agent-browser --session verifier open http://localhost:4921/
  agent-browser --session verifier set viewport 900 900 2
  ```
- 手机帧：`#phone` 固定 `390×800`，body 居中（flex）；**所有高度/边距一律换算成相对 `#phone.getBoundingClientRect()` 的值**，不写死视口坐标。
- 每项检查前先 `agent-browser --session verifier errors --clear` + `console --clear`，结束后读一次，做到「单项归因」。
- 复杂 JS 一律走 **base64**（实测有效；`--stdin` 在本机 PowerShell + 该 CLI 组合下**返回 null 且不执行**，已用 `window.__t=42` 探针复现）：
  ```powershell
  $js = @'
  <JS>
  '@
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($js))
  agent-browser --session verifier eval -b $b64
  ```
- 注入存档同理：`[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content <file>.js -Raw)))` → `eval -b`
- 页面内异步采样不用「eval 里 await Promise」（不确定是否 await），统一用**同步挂钩 + 事后读取**：
  ```js
  // 挂钩（同步返回）
  window.__s=[];(function f(){const e=EL; if(e)window.__s.push([Math.round(performance.now()), Math.round(e.getBoundingClientRect().top-phoneTop)]); requestAnimationFrame(f)})();'hooked'
  ```
- 截图统一存 `prototype/references/verify-v5b-*.png`（DPR2 会出 1800×1800 像素，尺寸本身也是证据）。
- 干扰项已知：`setInterval(...,30000)` 有 22% 概率弹「突发任务」（`#sud`）。它不遮挡主线页操作；如截图里出现，报告中标注为环境噪声，**不点击**。另有 `#errBox`（全局报错网）与 Live2D 本地模型 `live2d/Hiyori/*`（18 个文件，存在）+ Google Fonts 外链——字体/CDN 的**网络失败**要与**页面脚本错误**分开记（判据见第 1 条）。

## 1. 十条验收项 → 可执行检查

约定：`P` = `#phone` 的 rect；`S` = 面板（顶部面板 / settleSheet 等）的 rect；`pw()` 辅助函数每段内联重写，避免依赖全局。

---

### 检查 1｜加载无 console 错误 + app 启动 `typeof S !== 'undefined'` → 截图 `verify-v5b-01-boot.png`

```powershell
agent-browser --session verifier errors --clear
agent-browser --session verifier console --clear
agent-browser --session verifier reload
agent-browser --session verifier wait --load networkidle
agent-browser --session verifier eval "JSON.stringify({S:typeof S,loaded:document.readyState,phone:!!document.getElementById('phone'),tabs:document.querySelectorAll('#tabs .tab').length,curPage:[...document.querySelectorAll('.page.on')].map(e=>e.id),errBox:(document.getElementById('errBox')||{}).style?.display||null})"
agent-browser --session verifier errors
agent-browser --session verifier console
agent-browser --session verifier screenshot prototype/references/verify-v5b-01-boot.png
```
判据：`errors` 为空；`console` 中无 `error` 级条目（`warn` 单列说明）；`typeof S === "object"`；`#errBox` 不存在或 `display:none`。
「网络类失败」（fonts.googleapis.com / jsdelivr / voice/*.mp3 404）单独列一行，不计入本项成败，但必须如实写出。

---

### 检查 2｜执行面板按钮文案 +「认输」是红色按钮且与其它按钮同款硬边裁角 → 截图 `verify-v5b-02-exec-buttons.png`

注入**变体 B**（有执行中，见 §2 `inject-chain-exec.js`），切到任务页（`UI.tab('quest')`）。

```js
(()=>{const p=document.getElementById('execPanel');if(!p)return 'NO_EXEC_PANEL';
 const c=e=>{const s=getComputedStyle(e);return{tag:e.tagName,text:e.textContent.trim(),
   clip:s.clipPath,bg:s.backgroundColor,bgi:(s.backgroundImage||'').slice(0,60),border:s.borderTopWidth+' '+s.borderTopColor,
   color:s.color,r:(r=>({w:Math.round(r.width),h:Math.round(r.height)}))(e.getBoundingClientRect())}};
 const leaves=[...p.querySelectorAll('*')].filter(e=>!e.children.length&&e.textContent.trim());
 const btns=[...p.querySelectorAll('button')].map(c);
 const lose=leaves.find(e=>e.textContent.trim()==='认输');
 return JSON.stringify({btns,loser:lose?{...c(lose),isButton:lose.tagName==='BUTTON',cursor:getComputedStyle(lose).cursor,
   parentTag:lose.parentElement.tagName}:null,
   clipSet:[...new Set(btns.map(b=>b.clip))],allLeafTexts:leaves.map(e=>e.textContent.trim())})})()
```
判据：
- 按钮文案集合 ⊇ {`快照记录`, `提交任务`}，且不再出现 `快照入轴`/`完成封轴`/`中辍换单` 字样；
- `认输` 元素：`clipPath !== 'none'` 且与另外两个按钮的 `clipPath` **字符串相同**（同款硬边裁角）；`backgroundColor` 非全透明**或** `border` 有实色（"有背景色/描边，不是纯文本链接"），颜色属于 danger 系（`rgb(255,75,87)`/`#FF4B57` 或其透明变体）；
- 若 `认输` 仍是 `SPAN` 且 `bg` 全透明、`border 0px` → 判**不通过**（当前基线正是这种"纯文本 span"，见 §3 基线快照）。

---

### 检查 3｜三类节点都从顶部落面板；面板高 ≈60% 手机高（480±20px）；有下落动画；点遮罩关闭 → 截图 `verify-v5b-03a-done.png` / `03b-cur.png` / `03c-todo.png` / `03d-closed.png`

注入**变体 B**（同时含 已完成 / 执行中 / 待执行 三态，`rings[0..2]`），`UI.tab('main')`。

点击目标的发现顺序（T3 可能把 handler 绑在 `.ncard` 或 `.node` 上）：
```js
(()=>{const n=document.querySelector('#rings .node[data-i="0"]');
 const cands=[n.querySelector('.ncard'),n].filter(Boolean).map(e=>({sel:e.className,hasOnclick:!!e.getAttribute('onclick'),onclick:(e.getAttribute('onclick')||'').slice(0,40)}));
 return JSON.stringify(cands)})()
```

动画采样（先挂钩，再真实点击）：
```js
(()=>{const P=document.getElementById('phone').getBoundingClientRect();window.__s=[];
 const pick=()=>[...document.querySelectorAll('body *')].filter(e=>{const r=e.getBoundingClientRect();const cs=getComputedStyle(e);
   return cs.display!=='none'&&(cs.position==='absolute'||cs.position==='fixed')&&r.height>300&&r.width>250&&r.top<P.top+260&&cs.zIndex!=='auto'}).sort((a,b)=>+getComputedStyle(b).zIndex-+getComputedStyle(a).zIndex)[0];
 window.__pickOnTop=!!pick();
 (function f(){const e=pick();if(e)window.__s.push([Math.round(performance.now()),Math.round(e.getBoundingClientRect().top-P.top),Math.round(e.getBoundingClientRect().height),getComputedStyle(e).transform.slice(0,40)]);requestAnimationFrame(f)})();return 'hooked'})()
```
然后真实点击 + 读采样：
```powershell
agent-browser --session verifier click '#rings .node[data-i="0"] .ncard'
# 若上一步报找不到元素，改用 '#rings .node[data-i="0"]'
agent-browser --session verifier wait 700
agent-browser --session verifier eval "JSON.stringify(window.__s.slice(0,40))"
agent-browser --session verifier screenshot prototype/references/verify-v5b-03a-done.png
agent-browser --session verifier eval "(()=>{const P=document.getElementById('phone').getBoundingClientRect();const el=[...document.querySelectorAll('body *')].filter(e=>{const r=e.getBoundingClientRect();const cs=getComputedStyle(e);return cs.display!=='none'&&(cs.position==='absolute'||cs.position==='fixed')&&r.height>300&&r.width>250&&r.top<P.top+260}).sort((a,b)=>+getComputedStyle(b).zIndex-+getComputedStyle(a).zIndex)[0];const r=el.getBoundingClientRect();return JSON.stringify({tag:el.tagName,id:el.id,cls:el.className,topPx:Math.round(r.top-P.top),heightPx:Math.round(r.height),ratio:+(r.height/P.height).toFixed(3),animations:el.getAnimations().map(a=>({dur:a.effect.getTiming().duration,easing:a.effect.getTiming().easing}))})})()"
```
判据：
- 采样序列中 `topPx` 从**负值/小于终值**单调趋近 `≈0`（存在下落过程），或 `animations` 里有 duration ≥ 250ms 的 transform 动画；
- 稳定后 `Math.abs(topPx) <= 8`（从顶部垂下）且 `Math.abs(heightPx-480) <= 20`（≈60%×800）；
- 三态各点一次（`data-i="0"/"1"/"2"`），每次都能落下同一面板：分别截图并记录 `heightPx`。
- 关闭：先 `eval` 求遮罩空白坐标（面板底边下方 40px、手机中线），确认 `elementFromPoint` 命中的不是面板，再真实点击：
  ```powershell
  agent-browser --session verifier eval "(()=>{const P=document.getElementById('phone').getBoundingClientRect();return JSON.stringify({x:Math.round(P.left+P.width/2),y:Math.round(P.top+P.height*0.8),hit:(document.elementFromPoint(P.left+P.width/2,P.top+P.height*0.8)||{}).className})})()"
  agent-browser --session verifier mouse move <x> <y>
  agent-browser --session verifier mouse down
  agent-browser --session verifier mouse up
  agent-browser --session verifier wait 500
  agent-browser --session verifier screenshot prototype/references/verify-v5b-03d-closed.png
  ```
  判据：点击后同一 `pick()` 找不到面板（高度>300 的顶层面板消失），或 `topPx <= -300`（已移出屏幕）。

---

### 检查 4｜已完成节点面板：时长/证据份数/结算数字，且**无任何操作按钮** → 截图 `verify-v5b-04-done-readonly.png`

变体 B，点 `data-i="0"`（已完成；timeline 内 start→shot→done 相隔 31 分钟，见证时长可算）。

```js
(()=>{const P=document.getElementById('phone').getBoundingClientRect();
 const el=[...document.querySelectorAll('body *')].filter(e=>{const r=e.getBoundingClientRect();const cs=getComputedStyle(e);return cs.display!=='none'&&(cs.position==='absolute'||cs.position==='fixed')&&r.height>300&&r.width>250&&r.top<P.top+260}).sort((a,b)=>+getComputedStyle(b).zIndex-+getComputedStyle(a).zIndex)[0];
 const txt=el.innerText.replace(/\s+/g,' ').trim();
 return JSON.stringify({text:txt,buttons:[...el.querySelectorAll('button')].map(b=>b.textContent.trim()),
  hasClickable:[...el.querySelectorAll('[onclick]')].map(e=>e.tagName+':'+(e.getAttribute('onclick')||'').slice(0,30)),
  hasDuration:/时长/.test(txt),hasShots:/证据|份/.test(txt),hasSettle:/(\+?\d+\s*EXP)|(金币\s*\+?\d+)/.test(txt),numbers:(txt.match(/\d+/g)||[]).slice(0,10)})})()
```
判据：`/时长/`、`/(证据|份)/`、`EXP 与金币数字` 三者都出现（实测字符串抄进报告）；`buttons.length === 0`（严格禁止 `快照记录/提交任务/认输/接任务` 出现）。

---

### 检查 5｜执行中节点面板：计时器在跳 + 证据轴 + 三个动作按钮 → 截图 `verify-v5b-05-cur-live.png`

变体 B，点 `data-i="1"`（执行中，`S.exec.startedAt = now-125s`）。

```powershell
agent-browser --session verifier click '#rings .node[data-i="1"] .ncard'
agent-browser --session verifier eval "(()=>{const P=document.getElementById('phone').getBoundingClientRect();const el=[...document.querySelectorAll('body *')].filter(e=>{const r=e.getBoundingClientRect();const cs=getComputedStyle(e);return cs.display!=='none'&&(cs.position==='absolute'||cs.position==='fixed')&&r.height>300&&r.width>250&&r.top<P.top+260}).sort((a,b)=>+getComputedStyle(b).zIndex-+getComputedStyle(a).zIndex)[0];const t=[...el.querySelectorAll('*')].filter(e=>/^\d{2}:\d{2}(:\d{2})?$/.test(e.textContent.trim())).map(e=>e.textContent.trim());return JSON.stringify({timers:t,btns:[...el.querySelectorAll('button')].map(b=>b.textContent.trim()),axis:!!el.querySelector('.evl'),rows:el.querySelectorAll('.evl .ev').length})})()"
agent-browser --session verifier wait 1500
agent-browser --session verifier eval "同上表达式（第二次取值）"
```
判据：两次取到的计时器字符串**不同**（在跳）；`axis === true` 且 `rows >= 3`（start/shot/note）；`btns` 恰好/至少包含 {`快照记录`,`提交任务`,`认输`} 三个。

---

### 检查 6｜待执行节点面板：有「接任务」；有执行中任务时不出现 → 截图 `verify-v5b-06a-todo-accept.png` / `06b-todo-noaccept-running.png`

- 变体 A（`exec:null`，`rings[2]` 待执行）→ 点 `data-i="2"`：面板文本含 `接任务`，且含 `要求`/`验证方式`。
- 变体 B（`exec` 存在）→ 点 `data-i="2"`：面板内**不出现** `接任务`（按钮或文本都没有），出现一行等宽提示（记录该行字符串）。
每次改动注入后必须 `location.reload()` 再 `UI.tab('main')`（`S` 是加载期读入的）。

### 检查 7｜执行面板与面板内证据轴：轴线连续、节点类型差异、快照缩略图、时间右对齐 → 截图 `verify-v5b-07a-exec-spine.png` / `07b-panel-spine.png`

对 `.evl` 容器与其行做实测（`::before` 伪元素取 `getComputedStyle(el,'::before')`）：

```js
(()=>{const out={axes:[],rows:[]};
 document.querySelectorAll('.evl').forEach((a,i)=>{const cs=getComputedStyle(a);const b=getComputedStyle(a,'::before');
  out.axes.push({i,rows:a.querySelectorAll('.ev').length,beforeW:b.width,beforeH:b.height,beforeBg:b.backgroundImage.slice(0,80),beforeShadow:b.boxShadow.slice(0,60),padLeft:cs.paddingLeft})});
 document.querySelectorAll('.ev').forEach(e=>{const r=e.getBoundingClientRect();const b=getComputedStyle(e,'::before');
  const tm=e.querySelector('.tm')||e.querySelector('.t');const tr=tm?tm.getBoundingClientRect():null;
  out.rows.push({cls:e.className,dot:{w:b.width,h:b.height,bg:b.backgroundColor,br:b.borderRadius,bc:b.borderTopColor},
   txt:e.textContent.trim().slice(0,24),
   tm:{cls:tm?tm.className:null,rightGap:tr?Math.round(r.right-tr.right):null,leftRatio:tr?+((tr.left-r.left)/r.width).toFixed(2):null},
   thumb:(()=>{const th=e.querySelector('.th');if(!th)return null;const t=th.getBoundingClientRect();return{w:Math.round(t.width),h:Math.round(t.height),border:getComputedStyle(th).borderTopWidth}})()})});
 return JSON.stringify(out)})()
```
判据：
- **轴线连续**：`.evl::before` 宽度 1–3px、`backgroundImage` 含 `linear-gradient`、`boxShadow ≠ none`；
- **节点类型差异**：出现的行类（`start/shot/note/done/abn/live`）中至少 3 类，其 `::before` 的 `{w,h,bg,br}` 签名至少 3 种不同（写进报告，逐个列出）；
- **快照缩略图**：`.ev.shot .th` 存在，尺寸 ≈26–34 × 19–24（记录实测）；
- **时间右对齐**：`.tm`（或旧 `.t`）`rightGap <= 10`（贴右边缘）且 `leftRatio >= 0.5`；同时报告里写明"基线（两圆点+左对齐时间）"已不存在。

### 检查 8｜主线页底部无「立新目标/放弃主线」；最后节点完整可见 → 截图 `verify-v5b-08a-main-bottom.png` / `08b-settings.png`

```js
(()=>{const pg=document.getElementById('pg-main');pg.scrollTop=pg.scrollHeight;
 const tabs=document.getElementById('tabs').getBoundingClientRect();const P=document.getElementById('phone').getBoundingClientRect();
 const nodes=[...pg.querySelectorAll('.node')];const last=nodes[nodes.length-1];
 const card=last?last.querySelector('.ncard'):null;const cr=card?card.getBoundingClientRect():null;
 return JSON.stringify({scrollTop:pg.scrollTop,scrollHeight:pg.scrollHeight,clientHeight:pg.clientHeight,
  btns:[...pg.querySelectorAll('button')].map(b=>b.textContent.trim()),
  legendTexts:[...pg.querySelectorAll('*')].filter(e=>!e.children.length&&/立新目标|放弃主线/.test(e.textContent)).map(e=>e.tagName+':'+e.textContent.trim()),
  lastCardBottom:cr?Math.round(cr.bottom):null,tabsTop:Math.round(tabs.top),phoneBottom:Math.round(P.bottom),
  gapToTabs:cr?Math.round(tabs.top-cr.bottom):null})})()
```
判据：`btns` 与 `legendTexts` 都不含 `立新目标`/`放弃主线`；`gapToTabs >= 0`（最后一张卡完整露出，未被底栏压住）。设置页另截一张，记录两个功能入口是否在设置页（T3 第 4 条），作为附注。

### 检查 9｜回归：清空 localStorage 走完绑定降临 + 执行并提交 + 自动飞币 + 结算卡贴底 → 截图 `verify-v5b-09a-scan/09b-ask/09c-gen/09d-board-pinned/09e-exec/09f-settle-bottom/09g-coins.png`

1. 清档并挂钩：
   ```powershell
   agent-browser --session verifier errors --clear; agent-browser --session verifier console --clear
   agent-browser --session verifier eval "localStorage.removeItem('hostsys_v1');location.reload();'cleared'"
   agent-browser --session verifier wait 600
   agent-browser --session verifier screenshot prototype/references/verify-v5b-09a-scan.png
   ```
2. 等到 `#bsAsk.on`（降临+报目标）：`wait '#bsAsk.on'`（超时 25s 内应到；`arrive()` 全流程 ≈3.4s）。截图 `09b-ask.png`，填目标并签订：
   ```powershell
   agent-browser --session verifier fill '#bsGoal' '三个月减十斤'
   agent-browser --session verifier click 'button.bs-btn'   # 文案「签 订 契 约」
   agent-browser --session verifier wait --fn "!document.getElementById('boot').classList.contains('on')"
   agent-browser --session verifier eval "JSON.stringify({bound:S.bound,goal:S.goal,rings:S.main.rings.length,cycleDays:S.main.cycleDays,slots:document.querySelectorAll('#boardSlots .qmod').length,boardCnt:document.getElementById('boardCnt').textContent,title:S.main.title})"
   agent-browser --session verifier screenshot prototype/references/verify-v5b-09d-board-pinned.png
   ```
   （`09c-gen.png` 在签订后 ~1.2s 抓一次，对应 `#bsGen.on`。）
3. 执行并提交（真实交互，不走火焰捷径——火焰捷径不弹结算卡）：
   ```powershell
   agent-browser --session verifier click '#streakBox'                     # 拔单进入执行（simTap 第一次）
   agent-browser --session verifier eval "UI.tab('main')"                  # 回主线
   agent-browser --session verifier click '#rings .node[data-i="0"] .ncard' # 打开执行中节点面板
   agent-browser --session verifier screenshot prototype/references/verify-v5b-09e-exec.png
   agent-browser --session verifier find text "快照记录" click
   agent-browser --session verifier find text "提交任务" click              # 进入详情（preset=1 张截图）
   agent-browser --session verifier eval "window.__coinMax=0;window.__coinT=setInterval(()=>{const n=document.querySelectorAll('.coin').length;if(n>window.__coinMax)window.__coinMax=n},40);'coin-hooked'"
   agent-browser --session verifier find text "提交任务" click              # 详情里的提交按钮（提交后 1.5s 出现结算卡）
   agent-browser --session verifier wait 900
   agent-browser --session verifier screenshot prototype/references/verify-v5b-09f-settle-bottom.png
   agent-browser --session verifier eval "(()=>{const P=document.getElementById('phone').getBoundingClientRect();const sh=document.getElementById('settleSheet').getBoundingClientRect();return JSON.stringify({settleOn:document.getElementById('ov-settle').classList.contains('on'),bottomMarginPx:Math.round(P.bottom-sh.bottom),leftMarginPx:Math.round(sh.left-P.left),sheetText:document.getElementById('settleSheet').innerText.replace(/\s+/g,' ').trim(),coinNow:document.querySelectorAll('.coin').length,coinMax:window.__coinMax,errorsShown:!!document.getElementById('errBox'),pickupWords:/拾取|点击收|点收|一枚/.test(document.getElementById('settleSheet').innerText)})})()"
   agent-browser --session verifier screenshot prototype/references/verify-v5b-09g-coins.png
   agent-browser --session verifier errors
   ```
   判据：`boardCnt`/`slots` > 0 且 `bound===true`（钉单完成）；`bottomMarginPx` 在 16–24（目标 ≈20）；`coinMax >= 3`（自动飞币）且 `pickupWords === false`（无拾取交互）；整条链路 `errors` 为空。

### 检查 10｜文档一致性：docs/ 与 AGENTS.md 无「入轴」「封轴」「中辍换单」（历史旧称标注除外）→ 证据 `verify-v5b-10-docs-grep.txt`

```powershell
cd E:\repo\system_panel
Select-String -Path docs\*.txt,AGENTS.md -Pattern '入轴|封轴|中辍换单' | ForEach-Object {"$($_.Path):$($_.LineNumber): $($_.Line.Trim())"} | Tee-Object prototype\references\verify-v5b-10-docs-grep.txt
```
判据：无匹配 → 通过；有匹配 → 逐行判断是否**显式标注为历史旧称**（含 `旧称/原名/曾称/历史`，如 17 号文档开头的改名对照表），标注可排除，否则不通过。**准备阶段基线（供对照）**：`docs/17:15`、`docs/17:24`、`docs/16:3`、`docs/16:5`、`docs/16:6`、`docs/05:5`，共 6 处；AGENTS.md 0 处（此刻 task-1 仍在进行中，最终以 T3 完成后的复测为准）。

## 2. 注入存档（`localStorage` key = `hostsys_v1`）

三个可直接用的文件已放在 `prototype/references/verify-v5b-assets/`：

| 文件 | 用途 |
|---|---|
| `inject-chain-exec.js` | 变体 B：3 环 = 已完成/执行中/待执行，`S.exec={rid:1}`（检查 2/3/4/5/6B/7） |
| `inject-chain-noexec.js` | 变体 A：同上但无执行中（`rings[1]` 也待执行；检查 6A） |
| `inject-empty.js` | 清档（检查 9 起点） |

用法：
```powershell
Get-Content prototype\references\verify-v5b-assets\inject-chain-exec.js -Raw | agent-browser --session verifier eval --stdin
```
脚本自身以 `localStorage.setItem('hostsys_v1', JSON.stringify(state)); location.reload();` 收尾（先同步写、再重载，`S` 在 load 时重新 hydrate）。
已知约束（读源码得出，实测复核）：`load()` 是**浅合并**，所以注入的 `attrs` 必须是完整六维；`S.exec` 的 ring 会被启动逻辑强制成 `执行中`（`index.html` 启动块）；启动时默认页是主线 `#pg-main`。

## 3. 准备阶段基线快照（T3 之前，供对比，不作为结论）

| 观测点 | T3 前基线（读源码/实测定位） |
|---|---|
| 执行面板按钮文案 | `快照入轴`（L725）、`完成封轴`（L726） |
| 「认输」前身 | `<span class="meta" style="color:var(--danger)">中辍换单（计连败）</span>`（L727）＝**纯文本，无背景无描边** |
| 主线节点点击 | `SYS.toggleNode(i)` → `.node.open .npanel` **内联展开**（L1179/L1367） |
| 节点面板三态 | 已有三态内容，但承载在侧边 47% 内联卡，非顶部面板 |
| 证据轴 | `evlHtml()`：`<span class="t">时间</span>` **在最左**，两圆点/小圆点（L1093-1098，CSS L513-519） |
| 主线页底部按钮 | `立新目标` + `放弃主线`（L765-766） |
| 结算卡 | `#settleSheet`，`.sheet{bottom:20px}`（L100）→ 底边距应 ≈20px |
| 主线页/底栏 | `.page{inset:0}` + `.tabbar{height:60px;bottom:0}`（覆盖在页面上，可能压住最后一张卡） |
| AGENTS.md 17 行 | 准备阶段已被 docs-archivist 更新为「v5 · 顶部面板三态 + 紧凑书脊」 |

## 4. 第二阶段执行顺序与产物清单

顺序：1 → 10（文档 grep 可提前跑）→ 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9（回归最耗时，放最后，因为它会清档）。
每项完成即把 [通过/不通过] + 实测值写入 `verify-v5b.md`；不通过项补「最小复现步骤（从注入存档开始的最小命令序列）+ 观察值」。
全部写完后：`team_task_update(task-4, action=complete)` → `send_message(lead, ≤12 行简报)`。
