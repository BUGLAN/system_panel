# v5B 交互改版 · 独立验证报告（T4 / task-4）

- 验证者：`verifier`（独立于实现者 lead；只读被测代码，写作用域仅 `prototype/references/`）
- 被测对象：`prototype/app/index.html`
- **最终（R3 · 冻结交付）被测指纹：SHA256 = `43E72D32E7B3DD4E18ABFE235C439049D66AF724EEC54F7DA364D5562AFFAB1A`**（实测复核一致，mtime 2026-10-05 22:43:10）
- 历史指纹：R2 补丁版 `FD069065650C6C10E0826377FAC841D4A2630D9012FF373CC83293162E5DC2BF`（22:26:43）；R1 初版 `5318B94B44D3DA68F3D5641B2BD2AFD781273CD50C46A343C1C1577C0F204F5D`（22:01:50），git HEAD `a037a51`
- 复验轮次与范围：#R1 全量 10 条 → #R2 复验 #1/#3/#7/#8 → **#R3 复验 #1/#7（`.ev .tm` 加回 `margin-left:auto`）**；其余 6 条未受任何补丁影响（代码复核：三轮改动只涉及 `.page` padding、`.nsheet` 下落动画、`.evl` 双层轴、`.ev*` 几何与 `.th` 隐藏方式），沿用 R1 结论
- 环境：Windows / PowerShell 7；`cd prototype/app; node server.mjs` → http://localhost:4921（实测 200）
- 视口：`agent-browser --session verifier set viewport 900 900 2`；手机帧 `#phone` 实测 rect = `[255, 20, 390, 800]`，DPR=2
- 截图与证据：`prototype/references/verify-v5b-*.png` / `verify-v5b-10-docs-grep.txt`
- 注入存档：`prototype/references/verify-v5b-assets/`（`inject-chain-exec.js` 变体 B、`inject-chain-noexec.js` 变体 A、`inject-chain-8.js` 变体 C、`inject-empty.js` 清档）
- 执行计划：`prototype/references/verify-v5b-plan.md`
- 说明：本报告所有数字/字符串均来自本次会话的 `eval` 实测输出或截图，未实测处一律标注。

## 结论汇总

| # | 验收项 | 结论 | 关键实测值 |
|---|---|---|---|
| 1 | 加载无 console 错误 + 启动 | **通过**（R3 复验） | `errors` 空、`console` 无 error/warn（5 条 info：PixiJS/Live2D）；`typeof S` = `"object"`；`#errBox` absent；`.page` padding-bottom `78px` |
| 2 | 面板按钮文案 + 认输红按钮硬边裁角 | **通过**（R1，未复验） | 三按钮 `快照记录`/`提交任务`/`认输`；三者 `clipPath` **同一字符串**；认输红色渐变+红描边 |
| 3 | 三类节点从顶部落面板 / 高 60% / 遮罩可关 | **通过**（R2 复验 · 补丁已修） | 三态 `topPx=0`、`heightPx=480`、`ratio=0.600`；**过冲峰值 +7.99px**（原 +47px，目标 ≈8px）、落定 ≈390ms（动画时长 420ms）；`animationName=sheetDrop` |
| 4 | 已完成面板：回顾数据 + 零按钮 | **通过**（R1，未复验） | `时长 31 分钟` / `证据 1 份` / `结算 +10 EXP · +5`；`buttons=0`、`[onclick]=0` |
| 5 | 执行中面板：计时器跳 + 证据轴 + 三按钮 | **通过**（R1，未复验） | `00:03:13 → 00:03:15`；4 行证据（live/note/shot/start）；按钮 3 个 |
| 6 | 待执行面板：接任务 / 有执行中则无 | **通过**（R1，未复验） | A：`buttons=["接任务"]`；B：`buttons=[]` + `.nsbusy`「手上有活：先提交当前任务」 |
| 7 | 证据轴：连续轴线 + 类型差异 + 缩略图 + 时间右对齐 | **通过**（R3 复验 · 已修） | **live 行 `rightGap=0`**（`margin-left:auto` 解析为 `264px`，原 264px gap 已消除）、其余行均 `rightGap=0`/`leftRatio=0.87`；双层轴 ✓、4 类形状签名 ✓、`.th` 34×24 且非 shot `display:none` ✓、live 光环 19×19+breathe2 ✓、旧 `.t`=0 ✓ |
| 8 | 主线底部无两按钮 + 末节点完整可见 | **通过**（R2 复验 · 补丁已修） | 按钮/文案为 0；8 环滚到底（scrollTop 273 = max）末卡 `bottom=731` vs 底栏 `top=760` → **gap +29px**，`elementFromPoint` 命中 `DIV.ncard`/`DIV.nmeta`（原为 `DIV.tab`，被裁 19px） |
| 9 | 回归：绑定降临 + 执行提交 + 自动飞币 + 结算卡贴底 | **通过**（R1，未复验） | `bound=true`、5 环钉单；全链路无报错；结算卡底边距 **20px**；`.coin` 峰值 **5**、无拾取交互 |
| 10 | 文档无「入轴/封轴/中辍换单」 | **通过**（R1，未复验） | 全仓库唯一命中 = `docs/17:3` 的显式「旧称 → 新称」对照行（属排除项） |

**最终结论（R3，指纹 `43E72D32…`）：通过 10 / 10**（R2 遗留的唯一缺陷 #7 live 行时间对齐已被方案 A 修复并复验通过）。

> 下面 §1~§10 是**第一轮**（指纹 `5318B94B…`）的逐条实测明细，保留作对照；**当前有效结论 = R3（见下方「第三轮（R3 · 最终）」一节；R2 见其后）**。

## 第三轮（R3 · 最终）：#1 / #7 聚焦复验 —— [均通过]

指纹 `43E72D32…`（mtime 22:43:10）。修复方式（方案 A）：`.ev .tm{order:3;flex:none;margin-left:auto;min-width:38px;text-align:right;…}`。

### R3-#1 加载无报错 —— [通过]

- `agent-browser errors` → **空**
- `console` 过滤 `[error]|[warn]|Uncaught|TypeError|ReferenceError` → **无输出**（全部 5 条为 info 级：PixiJS 6.5.10 横幅 + Live2D Cubism 4 条）
- `{"S":"object","ready":"complete","pagePadBottom":"78px","errBox":"absent"}`

### R3-#7 证据轴 —— [通过]（R2 遗留缺陷已消除）

实测（每次以 `SYS._nid` + `#ov-node.on` 交叉校验确认真开面板，噪声已预清理）：

| 容器 | 行类 | `rightGap` | `leftRatio` | `.tm` used `margin-left` | `.th` |
|---|---|---|---|---|---|
| 执行中节点面板 `#nodeBody .evl` | `ev live` | **0** | 0.87 | 264px（`auto` 解析值） | 无（live 分支不输出） |
| | `ev note` | 0 | 0.87 | 0px | `display:none` |
| | `ev shot` | 0 | 0.87 | 0px | `block` 34×24 |
| | `ev start` | 0 | 0.87 | 0px | `display:none` |
| 执行面板 `#execTl` | `ev live` | **0** | 0.87 | — | 无 |
| | `ev note` / `ev shot` / `ev start` | 0 / 0 / 0 | 0.87 | — | `none` / `block` 34×24 / `none` |
| 已完成节点面板 | `ev done` ×2 | 0 | 0.87 | — | `none` |
| | `ev shot` / `ev start` | 0 / 0 | 0.87 | — | `block` 34×24 / `none` |

- live 行时间从 R2 的 `rightGap=264px`（`leftRatio=0.00`）→ **`rightGap=0`（`leftRatio=0.87`）**，与其余行完全一致（判据 ≤10px ✓）
- 双层轴未回归（两容器一致）：`::before` 底轨 `2px×122px`、`rgba(150,180,220,.13)`；`::after` 走过段 `2px×122px`、`#CFF6FF→cyan 40%→透明` 渐变 + 双辉光 + `transition: height .45s`；容器 `max-height:140px`、`mask-image: linear-gradient(rgb(0,0,0) 82%, rgba(0,0,0,0))`、`--wlk=calc(100% - 18px)`
- 形状签名 4 类互不相同：`note 8px/圆角1px/void`、`shot 9px/cyan`、`start`≡`live` `11px/cyan`、`done 11px/rgb(255,90,60)`；live 另有 `::after` **19px×19px + `breathe2`** 光环 ✓
- 旧左对齐时间 `.ev .t` = 0 ✓；`.th` 非 shot 行 `display:none`、shot 行 34×24 ✓
- 截图：`verify-v5b-r3-07-panel-live.png`（live 行 `22:46` 与其余行一样贴右）、`verify-v5b-r3-07-exec-spine.png`

---

## 1. 加载无 console 错误，app 正常启动 —— [通过]

- 命令：`errors --clear` → `console --clear` → `reload` → `wait --load networkidle`
- 实测 DOM：
  `{"S":"object","ready":"complete","phone":[255,20,390,800],"dpr":2,"curPage":["pg-main"],"tabs":4,"errBox":"absent/none","bound":false}`
- `agent-browser errors` → **空**（无未捕获异常）
- `agent-browser console` → 仅 4 条 info 级日志（PixiJS 6.5.10 横幅、Live2D Cubism 5.1.0 三行），**无 error/warn**
- 网络噪声（与代码错误分开记）：`GET /favicon.ico → 404`（浏览器默认请求，与 app 无关）；`fonts.googleapis.com` 样式表实测 **200**
- 截图：`verify-v5b-01-boot.png`

## 2. 执行面板按钮文案 +「认输」是红色按钮且同款硬边裁角 —— [通过]

- 实测按钮（`#execPanel button`，视口内真实渲染）：

| 文案 | class | clip-path | 背景 | 描边 | 尺寸 |
|---|---|---|---|---|---|
| 快照记录 | `btn` | `polygon(0px 0px, calc(100% - 9px) 0px, 100% 9px, 100% 100%, 9px 100%, 0px calc(100% - 9px))` | `linear-gradient(rgba(59,227,255,.2), rgba(59,227,255,.06))` | `1px rgba(59,227,255,.5)` | 160×41 |
| 提交任务 | `btn ghost` | 同上（字符串相同） | `rgba(255,255,255,.02)` | `1px rgba(150,180,220,.34)` | 160×41 |
| **认输** | `btn danger` | 同上（**同一字符串**） | `linear-gradient(rgba(255,75,87,.26), rgba(255,75,87,.08))` | `1px rgba(255,75,87,.6)` | 328×46 |

- `clipSet`（去重后）= 1 个值 → 三个按钮**同款硬边裁角**（9px 斜切），实测 `clipPath !== 'none'`
- 「认输」实测：`tag=BUTTON`、`cursor=pointer`、`color=rgb(255,221,225)`，红色渐变背景 + 红描边 → **不是纯文本链接**（对照：T3 前为 `<span class="meta">中辍换单（计连败）</span>`，无背景无描边）
- 面板内叶子文本实测：`["EXECUTING · 唯一执行中","● LIVE","步行挑战：单日 8000 步","E 级 · 步数截图 · 开始 22:10","00:02:21","22:13","走到小区门口","22:12","第 1 次快照","22:12","拔单，开始执行","22:10","快照记录","提交任务","认输"]` → 无「快照入轴/完成封轴/中辍换单」
- 截图：`verify-v5b-02-exec-buttons.png`

## 3. 任意节点从顶部落下面板（三态各一次）/ 高 ≈60% / 遮罩可关 —— [通过]（另见「待补丁」）

真实鼠标点击 `#rings .node[data-i="N"] .ncard`，每次均实测：

| 点击节点 | 状态 | `topPx`（相对手机顶） | `heightPx` | 占手机高 |
|---|---|---|---|---|
| `data-i=0` | 已完成 | 0 | 480 | 0.600 |
| `data-i=1` | 执行中 | 0 | 480 | 0.600 |
| `data-i=2` | 待执行 | 0 | 480 | 0.600 |

- 高度判定：480px，恰为手机高 800×60%；与 480±20px 判据一致
- **下落动画**（rAF 采样 `#nodeSheet` top，采样起于点击前；原始样本 1175 条）：
  - `t=191ms → -485px`（初始位 `translateY(-101%)`）
  - `t=194 → -463`、`276 → -146`、`310 → -63`、`315 → -47`、`320 → -39`、`324 → -32`、`328 → -25`、`332 → -18`、`336 → -12`、`340 → -6.45`、`344 → -1`
  - **峰值过冲 `top = +47px`（`t=419ms`）**，>0.5px 的过冲样本 61 条，**完全落定 `t≈590ms`**，终值 0
  - 即：从顶部落下存在，但**触底后继续下冲 47px**（= 行程 485px 的 9.7%），手机顶边出现 47px 缝隙。对照 T2 样机实测三段曲线峰值过冲 7.9997px → 该项**待补丁**（lead 已确认 `.nsheet{transition:transform .42s var(--spring)}` 为本轮待修项）
- 遮罩关闭（真实坐标点击，非 JS 调用）：面板底边 480px，取 `(450, 540)` 实测 `elementFromPoint` = `DIV#ov-node.ov.dim.on`（空白遮罩）→ `mouse down/up` 后实测 `ovOn=false`、`#nodeSheet.className="nsheet"`（`.in` 已移除）、`#ov-node` 恢复 `display:none`（其 rect 归零，top 读数 -20 即 `0 - phoneTop`）
- 截图：`verify-v5b-03a-done.png`、`03b-cur.png`、`03c-todo.png`、`03d-closed.png`

## 4. 已完成节点面板：时长/证据份数/结算数字，无任何操作按钮 —— [通过]

- 实测数据行（`.npdata div`）逐字：`["时长 31 分钟","证据 1 份","结算 +10 EXP · +5"]`
- `hasDuration=true`、`hasShots=true`，结算数字 `+10 EXP · +5`（该环 F 级 = EXP 10 / 金币 5，与 `DIFF.F` 一致）
- **按钮数 = 0**；面板内带 `[onclick]` 的元素数 = **0**（无任何可点动作）
- 面板文本：`F 饮水令：今日喝满 8 杯水 F 级 · 水杯照片 时长 31 分钟 证据 1 份 结算 +10 EXP · +5 结算入账 23:46 提交任务，等待验证 23:46 第 1 次快照 23:18 拔单，开始执行 23:15`
- 截图：`verify-v5b-04-done-readonly.png`

## 5. 执行中节点面板：计时器在跳 + 证据轴 + 三个动作按钮 —— [通过]

- 计时器两次取值（间隔 1.6s）：`00:03:13` → `00:03:15`（在跳）；执行面板处另测 `00:02:42` → `00:02:44`
- 证据轴：`.evl` 存在，行数 4，行类 `["ev live","ev note","ev shot","ev start"]`（含 LIVE 呼吸行）
- 按钮实测：`["快照记录","提交任务","认输"]`（3 个）
- 面板几何：`topPx=0`、`heightPx=480`、`ratio=0.600`
- 截图：`verify-v5b-03b-cur.png`（= 执行中面板），`verify-v5b-09e-exec.png`（真实流程中的执行面板，`00:00:02`）

## 6. 待执行节点面板：有「接任务」；有执行中任务时不出现 —— [通过]

- 变体 A（`S.exec=null`，实测 `{"exec":null,"states":["已完成","待执行","待执行"]}`）：
  - `buttons=["接任务"]`，`acceptBtn={cls:"btn", clip:"polygon(0px 0px, calc(100% - 9px) 0px, 1…", h:46}`，`.nsbusy` 不存在
  - 文本：`D 初次奔跑：完成 3 公里 D 级 · 跑步 App 截图 要求 初次奔跑：完成 3 公里 验证方式 上传完成截图（跑步 App 截图） 接任务`（含「要求」「验证方式」）
  - 截图：`verify-v5b-06a-todo-accept.png`
- 变体 B（`S.exec={rid:1}`）：
  - `buttons=[]`，`hasAcceptText=false`，`.nsbusy` 文本实测 = `手上有活：先提交当前任务`
  - 截图：`verify-v5b-06b-todo-noaccept-running.png`（与 `03c-todo.png` 同帧）

## 7. 执行面板与面板内证据轴：轴线连续 / 类型差异 / 缩略图 / 时间右对齐 —— [通过]

同一套 `.evl` 结构在两处各测一遍（面板内 `.evl.spine`、执行面板 `#execTl`），实测值一致：

- **轴线连续**（`getComputedStyle(axis,'::before')`）：`width=2px`、`height=108px`、`top=12px`、`bottom=12px`（单条贯穿容器，非逐行断开）；
  `background-image = linear-gradient(rgb(207,246,255), rgb(59,227,255) 34%, rgba(59,227,255,.28) 76%, rgba(120,145,180,.3) 100%)`；`box-shadow = rgba(59,227,255,.45) 0 0 14px`；行高 32px、`.evl.spine{max-height:196px}`
- **节点类型差异**（行 `::before` 实测签名，5 类互不相同）：

| 行类 | 尺寸 | 背景 | 圆角 | 其他 |
|---|---|---|---|---|
| `ev start` | 11×11 | `rgb(59,227,255)` | 50% | `margin-left:-1.5px`，辉光 `0 0 10px` |
| `ev shot` | 8×8 | `rgb(59,227,255)` | 50% | — |
| `ev note` | 8×8 | `rgb(7,11,18)` | **1px（方点）** | 描边青色 |
| `ev done` | 8×8 | `rgb(255,90,60)`（朱砂 --ver） | 50% | 辉光 `0 0 10px` |
| `ev live` | 8×8 | `rgb(59,227,255)` | 50% | `animation-name: breathe2`、辉光 `0 0 12px` |

- **快照缩略图**：`.ev.shot .th` 实测 `34×24`（两处一致），其余行类无 `.th`
- **时间右对齐**：`.tm` 行内 `rightGap = 0px`（贴右边缘）、`leftRatio = 0.90`（时间落在行右侧 10% 区）；`.tx` 承载内容左对齐；`margin-left:auto`
- **旧样式已消失**：旧左对齐时间 span `.ev .t` 数量 = **0**（两处均为 0）；DOM 顺序为 `th → tx → tm`
- 截图：`verify-v5b-07a-exec-spine.png`（执行面板）、`verify-v5b-07b-panel-spine.png`（节点面板）

## 8. 主线底部不再有「立新目标/放弃主线」+ 最后一个节点完整可见 —— **[第一轮：不通过 → 第二轮补丁后已修复为通过]**

用 **8 环长链**存档复测（`inject-chain-8.js`：2 已完成 / 1 执行中 / 5 待执行；3 环时页面无需滚动，测不出裁切风险）。

- **前半条通过**：`#pg-main` 内 `button` 数量 = **0**；`#pg-main` 内匹配 `立新目标|放弃主线` 的叶子文本 = **[]**（空）；页面节点数 8
- **后半条不通过（实测几何）**：
  - `pg.scrollTop = 1e6` → 实际 `scrollTop = 225`（= `scrollHeight 1025 - clientHeight 800`，已是滚动到底）
  - 末节点卡片 `.ncard`：`top=696px`、`bottom=779px`（高 83px）；**底栏 `#tabs` top = 760px**（高 60px，phone bottom = 820px）
  - → `gapToTabs = 760 - 779 = **-19px**`，即末卡有 **19px 被底栏压住**；`fullyVisible = false`
  - 遮挡实测（`elementFromPoint`，x = 末卡水平中心）：`y=774 → DIV.tab`、`y=767 → DIV.tab`、`y=764 → DIV.tab` → 命中底栏而非卡片，证明确实被覆盖
  - `#pg-main` 计算样式 `padding-bottom = 30px`（< 底栏 60px）
  - 截图 `verify-v5b-08a-main-bottom.png` 肉眼可见：末卡「最终检验：完成一次 5 公里跑」的 `截图验证` 一行被底栏切掉下半
- **最小复现步骤**：
  1. `Get-Content prototype\references\verify-v5b-assets\inject-chain-8.js -Raw` → base64 → `agent-browser --session verifier eval -b <b64>`（8 环长链）
  2. `agent-browser --session verifier click '#tabs .tab[data-p="main"]'`
  3. `agent-browser --session verifier eval "(function(){const pg=document.getElementById('pg-main');pg.scrollTop=1e6;const c=pg.querySelectorAll('.node .ncard');const last=c[c.length-1].getBoundingClientRect();const tabs=document.getElementById('tabs').getBoundingClientRect();return JSON.stringify({scrollTop:pg.scrollTop,max:pg.scrollHeight-pg.clientHeight,lastBottom:Math.round(last.bottom),tabsTop:Math.round(tabs.top),gap:Math.round(tabs.top-last.bottom)})})()"`
  4. 观察值：`{"scrollTop":225,"max":225,"lastBottom":779,"tabsTop":760,"gap":-19}`
- **附注（T3 第 4 条迁移验证，超出本条判据）**：设置页按钮实测 = `["保存 LLM 设置","保存并重载模型","语音：关","BGM：关","音效：开","立新目标","放弃主线","系统重置（删档）"]` → 两个入口确已迁至设置页；截图 `verify-v5b-08b-settings.png`

## 9. 回归：绑定降临全流程 + 执行提交 + 自动飞币 + 结算卡贴底 —— [通过]

清空 localStorage（`inject-empty.js`）后走真实 UI，全程无报错：

| 环节 | 实测证据 |
|---|---|
| 扫描 | `bootOn=true`、`bsScan.go=true`、`#bootLog` 3 行 → `verify-v5b-09a-scan.png` |
| 降临 | `#bsLines` = `检测到新宿主。 系统已接管。`；`#bsAsk.on` 出现（等待命中）→ `verify-v5b-09b-ask.png` |
| 报目标/签订 | 填 `#bsGoal` = `三个月减十斤`，点 `button.bs-btn` |
| 生成 | `bsGen.on=true`、`#bsGenTxt=编排周期科目`、`#bsGenBar=42%`、`#bsWrite=「三个月减十斤」` → `verify-v5b-09c-gen.png` |
| 钉单 | `bound=true`、`goal=三个月减十斤`、`title=三个月减十斤`、`rings=5`、`diffs=[F,E,E,D,C]`、`cycleDays=7`、`#boardSlots .qmod=5`、`boardCnt=5/6` → `verify-v5b-09d-board-pinned.png` |
| 拔单 | 点火焰 → `S.exec.rid=0`、`rings[0].state=执行中`、`timeline=[start]`；面板 `timer=00:00:02`、按钮 3 个 → `verify-v5b-09e-exec.png` |
| 快照记录 | 点面板 `快照记录` → `timeline=[start,shot]`，面板行数 2→3 |
| 提交任务 | 点面板 `提交任务` → `rings[0].state=待提交`、`S.exec=null`、详情浮层 on、`#submitBtn` 文案 = `提交任务`、`#slotRow` 含 `截图1 ✓` → `verify-v5b-09f-detail-submit.png` |
| 结算卡 | `#ov-settle.on`；**底边距 = 20px**（`phone.bottom - sheet.bottom`），左边距 12px；`sheetText = 任务结算 +10 EXP CRIT ×2 金币 +5 经验 +10 体 +1 系统评价：勉强符合预期。 收下` → `verify-v5b-09f-settle-bottom.png` |
| **自动飞币** | 无任何点击/拾取动作下 `.coin` 峰值 = **5**（两轮结算各测一次，均 5）：时间序列 `[[76300,1],[76363,2],[76450,3],[76513,4],[76571,5]]`；`pickupWords=false`（面板文案无「拾取/点收/一枚/点击收取」）；结算卡唯一按钮 = `收下`；第二轮用 `wait --fn "document.querySelectorAll('.coin').length>0"` 抓到 **coinsVisible=5** 的飞币瞬间 → `verify-v5b-09g-coins.png` |
| 数值结算 | 两轮结算后：`done=2`、`coins=15`（0+5+10）、`exp=30`（10+20）、`states=[已完成,已完成,待执行,待执行,待执行]` |
| 报错 | 全流程 `errors` **空**、`console` 无 error/warn、`#errBox` absent |

- 截图：`verify-v5b-09a-scan.png`、`09b-ask.png`、`09c-gen.png`、`09d-board-pinned.png`、`09e-exec.png`、`09f-detail-submit.png`、`09f-settle-bottom.png`、`09g-coins.png`（另有 `09g-coins-2.png`）

## 10. 文档一致性：无「入轴 / 封轴 / 中辍换单」 —— [通过]

- 命令与全文输出已存档 `verify-v5b-10-docs-grep.txt`：
  `17-主线时间轴与执行轴规则.txt:3: ▸ v5 改名（旧称 → 新称）：入轴 → 记录、封轴 → 提交任务、中辍换单 → 认输。只换措辞，机制一条没动；本文档其余部分只用新称。`
- 全仓库（`docs/*.txt` + `AGENTS.md`）命中数 = **1**，且该行**显式标注为「旧称 → 新称」对照**，属验收条款的排除项（历史旧称标注）→ **通过**
- 范围外附注（lead 已声明的范围）：`prototype/app/v5-sheet-mock.html`（T2 样机）命中 11 处、`prototype/app/redesign-mocks.html`（废弃旧稿）含旧词，两者均不在本条范围（判据只覆盖 `docs/` 与 `AGENTS.md`）

---

## 第二轮：补丁复验（指纹 `FD069065…`）

复验范围 #1 / #3 / #7 / #8。补丁内容已与代码逐条对照（`.page{padding-bottom:78px}`、`@keyframes sheetDrop`、`.evl::before`+`.evl::after` 双层、`.ev:not(.shot) .th{display:none}`、`.ev.live::after` 19px 光环）。

### R2-#1 加载无报错 —— [通过]

- `open` + `wait --load networkidle` 后：`{"S":"object","ready":"complete","pagePadBottom":"78px","padTop":"96px","errBox":"absent"}` → `padding-bottom=78px` 证明下发的确是补丁版（无 localhost 缓存问题）
- `agent-browser errors` → **空**；`console` 过滤 `[error]|[warn]|Uncaught|TypeError|ReferenceError` → **无输出**
- 截图：`verify-v5b-patch-03-drop.png`（含面板落定帧）

### R2-#3 顶部面板下落 —— [通过]

`#nodeSheet` rAF 采样（点击发生在采样起点后约 186ms；下表时间已换算为**相对点击**）：

| 观测点 | 补丁后实测 | 补丁前（R1） | 目标 |
|---|---|---|---|
| 起始位 | `top = -484.8px`（`translateY(-101%)`） | -485px | — |
| 首次到达 `top=0` | **319ms**（= 420ms × 76%，与键帧一致） | ~158ms | — |
| 过冲峰值 | **+7.99px** @ **365ms**（= 420ms × 88% 附近） | **+47px** @419ms | ≈8px ✓ |
| 过冲持续帧数 | 17 帧 | 61 帧 | — |
| 落定（|top|≤0.5 且保持） | **≈390ms**（`--out` 收尾段提前收敛；动画总时长 420ms） | 590ms | ≈420ms ✓ |
| `animationName` | `sheetDrop` | （transition，无动画名） | — |
| 终值 / 高度 | `top=0`、`height=480px`、`ratio=0.600` | 同 | 480±20px ✓ |

- 结论：过冲从 47px 降到 7.99px（-83%），与 T2 样机 7.9997px 目标一致；面板几何未受影响
- **三态复测（补丁版，8 环存档，每次以 `SYS._nid` 交叉校验真开面板）**：`data-i=0`（已完成）`topPx=0/480/0.600`；`data-i=2`（执行中）`topPx=0/480/0.600/anim=sheetDrop`；`data-i=4`（待执行）`topPx=0/480/0.600/anim=sheetDrop` → 三态一致，遮罩关闭同 R1（坐标点击 `#ov-node` 空白处 → `ovOn=false`）
- 截图：`verify-v5b-patch-03-drop.png`

### R2-#7 证据轴 —— **[不通过（局部：live 行时间未右对齐）]**

**通过的子项**（两处轴各测一遍：`#execTl` 与 `#nodeBody .evl.spine`，数值一致）：

- **两层都在**：`::before` 底轨 = `2px × 122px`、`background rgba(150,180,220,.13)`、无辉光；`::after` 走过段 = `2px × 122px`、渐变 `rgb(207,246,255) → rgb(59,227,255) 40% → rgba(59,227,255,.16) 88% → transparent`、双辉光 `rgba(59,227,255,.5) 0 0 12px + rgba(207,246,255,.85) 0 0 3px`、`transition: height .45s cubic-bezier(.16,1,.3,1)`
- 容器 `max-height=140px`（实测容器高 140）、`--wlk = calc(100% - 18px)` = 122px、`mask-image: linear-gradient(rgb(0,0,0) 82%, rgba(0,0,0,0))` ✓
- 如实记录：底轨与走过段**几何完全重合**（同 top 9px、同高 122px），底轨只在走过段渐变尾部（88%→100% 透明段）透出
- **形状签名 5 类互不相同**：`note 8px/圆角1px/void`、`shot 9px/cyan/50%`、`start 11px/cyan+辉光`、`done 11px/rgb(255,90,60)+辉光`、`live 11px/cyan+breathe2`；`live` 另带 `::after` 光环 **19px×19px、animation breathe2**、边框 `1px rgba(59,227,255,.5)` ✓
- **缩略图**：`.th` 存在于每个非 live 行；非 shot 行 `display:none`（rect 0×0），shot 行 `display:block` 且 **34×24** ✓
- 旧左对齐时间 `.ev .t` 数量 = **0** ✓

**不通过的子项 —— `ev live` 行时间未右对齐**：

| 行类 | `.tx` | `tm.rightGap` | `tm.leftRatio` | `.tm` order |
|---|---|---|---|---|
| `ev live` | **无** | **264px** | **0.00** | 3 |
| `ev note` | 有 | 0px | 0.87 | 3 |
| `ev shot` | 有 | 0px | 0.87 | 3 |
| `ev start` | 有 | 0px | 0.87 | 3 |

- live 行 DOM 实测：`<span class="tm">22:35</span>`（仅此一个子元素，无 `.tx`、无 `.th`），`tmLeft=314` = 行左边界 → 时间贴在**行最左端**，正是验收条款想消除的「左对齐时间」形态
- 根因：补丁把 `.tm` 的 `margin-left:auto` 换成了 `order:3` + `.tx{order:1;flex:1}` 的推挤式对齐；而 `evlHtml(tl,liveTop)` 的 live 分支只输出 `.tm`，没有 `.tx` 撑开，故其时间停在左侧（`.ev .tm` 无 `margin-left:auto`）
- 对照：补丁前（R1）三按钮/各行含 live 的 `tmRightGap` 均为 0 → **属补丁引入的回归**
- 建议修复（二选一）：`.ev .tm{margin-left:auto}`（一行，最稳）；或 live 分支补 `<span class="tx"></span>`
- 最小复现步骤：
  1. 注入 `inject-chain-exec.js`（变体 B，`rings[1]` 为执行中、`S.exec={rid:1}`）
  2. `click '#tabs .tab[data-p="main"]'` → `click '#rings .node[data-i="1"] .ncard'`（打开执行中节点面板，含 live 行）
  3. `eval`：`[...document.querySelectorAll('#nodeBody .evl .ev')].map(e=>{const r=e.getBoundingClientRect();const t=e.querySelector('.tm').getBoundingClientRect();return e.className+' gap='+Math.round(r.right-t.right)})`
  4. **观察值**：`ev live gap=264`、`ev note gap=0`、`ev shot gap=0`、`ev start gap=0`
- 截图：`verify-v5b-patch-07-exec-spine.png`（肉眼可见 live 行 `22:30` 贴左，其余行 `22:30 / 22:29 / 22:28` 贴右）、`verify-v5b-patch-07-panel-spine.png`、`verify-v5b-patch-07-panel-live.png`（live 行复测帧）
- 附注（非不通过项）：live 行也没有 `.th` 元素（`evlHtml` 的 live 分支不输出），与 lead「每行都输出 `.th`」的描述略有出入，但 live 行本不需要缩略图，不影响验收

### R2-#8 主线页末节点不被底栏裁切 —— [通过]

8 环长链（`inject-chain-8.js`，8 节点）滚到底实测：

| 观测项 | 补丁后实测 | 补丁前（R1） |
|---|---|---|
| `scrollTop` / `maxScroll` | 273 / 273（已到底） | 225 / 225 |
| `#pg-main` 计算 `padding-bottom` | **78px** | 30px |
| `#pg-main` 按钮 / 「立新目标\|放弃主线」文案 | `[]` / 0 | `[]` / 0 |
| 末卡 `.ncard` | `top=648`、`bottom=731`（高 83px） | bottom=779 |
| 底栏 `#tabs` top | 760 | 760 |
| **gapToTabs** | **+29px** | **-19px** |
| `elementFromPoint(cardCenterX, bottom-5)` | `DIV.ncard` | `DIV.tab` |
| `elementFromPoint(cardCenterX, bottom-16)` | `DIV.nmeta`（`截图验证` 行可见） | `DIV.tab` |

- 结论：末节点及 meta 行完整可见，遮挡问题已修复（lead 自测 +22px、本次实测 +29px，差异来自存档末节点高度/换行不同，两者均为正）
- 截图：`verify-v5b-patch-08-main-bottom.png`（末卡 `最终检验：完成一次 5 公里跑` 与 `截图验证` 完整露出）

### R2 方法学备注

- 复验期间命中环境噪声（**2 次**）：突发任务限时到点 → `SYS.failSudden()` 弹毒舌浮层（`#ov-roast`，z-index 44），吞掉了随后的主线 tab 点击与节点点击，导致首次读取到的是**上一次面板的残留 DOM**（表现为 `SYS._nid=null` 但 `#nodeBody` 有内容、行 rect 全 0）。我通过 `SYS._nid`/`ovOn` 交叉校验发现后，用 `SYS.closeRoast(); S.sudden=null; $('#sud').classList.remove('on')` 清理噪声并**重测**，上表均为清理后的有效数据。建议后续自动化断言加一条前置校验：`SYS._nid` 必须等于目标环号且 `#ov-node.on` 为真。

---

## 第一轮不通过项 · 最小复现步骤（已由补丁修复，留档）

### 第 8 条后半：8 环长链滚到底，末节点被底栏裁 19px

1. 注入 8 环长链：`inject-chain-8.js`（base64 + `eval -b`，脚本自身 `setItem('hostsys_v1')` 后 `location.reload()`）
2. 等 2.5s，点主线 tab：`click '#tabs .tab[data-p="main"]'`
3. 滚到底并量几何（脚本见 §8 第 3 步）
4. **观察值**：`lastCardBottom=779`、`tabsTop=760`、`gap=-19`、`scrollTop=225=maxScroll`
5. 佐证：`document.elementFromPoint(cardCenterX, 774).className = "tab"`；`#pg-main` 的 `padding-bottom=30px`（小于底栏 60px）
6. 截图：`verify-v5b-08a-main-bottom.png`（末卡 `截图验证` 一行被底栏切掉）

## 复验状态（R3 · 最终 · 已完成）

| 轮次 | 指纹 | 范围 | 结果 |
|---|---|---|---|
| R1 | `5318B94B…` | 全量 10 条 | 通过 9/10（#8 末节点被底栏裁 19px） |
| R2 | `FD069065…` | #1 / #3 / #7 / #8 | #1 ✓、#3 ✓（过冲 47→7.99px）、#8 ✓（gap +29px）、**#7 局部不通过**（live 行时间 `rightGap=264px`） |
| **R3（最终）** | **`43E72D32…`** | **#1 / #7** | **#1 ✓、#7 ✓（live 行 `rightGap=0`）→ 全量 10/10 通过** |

R2 遗留的唯一缺陷（live 行时间未右对齐）已由方案 A（`.ev .tm{margin-left:auto}`）修复并复验通过；R3 未引入新报错，双层轴/形状签名/缩略图/光环均未回归。**报告结论：可以冻结交付**（依据：R3 指纹下 10/10 通过；其中 6 条沿用 R1 未复验项、1 条沿用 R2 复验项，均无补丁触及）。

## 附：本轮验证的方法学备注 / 超范围观察

1. **工具坑（可复现）**：本机 PowerShell 下 `agent-browser eval --stdin`（管道喂 JS）**实测返回 `null` 且未执行**（用 `window.__t=42` 探针验证 `window.__t` 未定义）；改用 `eval -b <base64>`（PowerShell `[Convert]::ToBase64String` 生成）后全部正常。`verify-v5b-plan.md` 中的 stdin 写法已按此更正。
2. **注入脚本命名**：`inject-chain-7.js` 实际为 8 环，已重命名为 `inject-chain-8.js`（注释同步更正）。
3. 超范围观察（不影响 10 条判定）：首轮结算时我在 `#ov-settle.on` 出现的瞬间就取值，此时 `#sChips` 仍为空、`.coin` 尚未起飞——结算动画仍在进行中；按完整时序（约 1.7s 后开始飞币）复测即得峰值 5。若后续要以脚本断言飞币，需等待 `#sChips` 非空或轮询 `.coin`。
4. 环境噪声：页面每 30s 有 22% 概率弹「突发任务」（`#sud`），本轮 10 项检查期间未出现，未影响任何测量。
5. 本轮未覆盖（不属 task-4 判据）：`prototype/app/v5-sheet-mock.html`（T2 样机）与 `redesign-mocks.html`（废弃旧稿）的文案/视觉；Flutter 端移植。
