# 01 · PWA 实施计划

> 日期：2026-11-21 ｜ 依据：`docs/00-PWA重写提示词.md`、`宿主养成系统_重设计.html`、tag `flutter-final`（`app/lib/`、`docs/50`、`app/test/`）
> 状态：已确认并按 8 步实施完毕（2026-11-21）。部署见 docs/02，验收见 docs/03，长期约定见根目录 AGENTS.md。

---

## 1. 总体做法

- 产品机制、数值、文案一律从 `flutter-final:app/lib/` 移植，**按模块翻译成 TS，不重新设计**；旧代码里「为老存档兼容」的分支（`rings` / `suspect` / `ringIndex` / totalExp 回填 / 旧色谱 `data/rarity.dart` 等）一律不带过来（第 00 文：不迁移 Flutter 存档）。
- 视觉照参考稿拆组件：参考稿的 `:root` 令牌、CSS 规则直接搬成 CSS 变量 + CSS Modules；参考稿没有的页面（首启告知、绑定仪式 / 访谈 / 拆解进度、接单前简报、证据来源底板、换目标、聊天、LLM 设置）按 `flutter-final:app/lib/ui/ref/ref_*.dart` 的交互细节，用同一套令牌做。
- 主壳不再是 4000 行的 `main.dart`：流程编排拆成「纯逻辑状态机（`src/core/flow/`）+ 若干编排器（`src/store/actions/`）+ 场景组件（`src/ui/scenes/`）」，每个文件 ≤ 600 行。

## 2. 目录与模块拆分

```
src/
  design/          令牌（唯一源）
    tokens.css       :root 变量：底色/强调色/文本/稀有度色/缓动/字体族/布局常量
    tokens.ts        TS 侧镜像（rankColor()、动效参数常量：弹簧、亮帧、count-up、经验条时长…）
    fonts.ts         Fontsource 引入（只引用到的字重）
  core/            纯逻辑，不碰 DOM / React / IndexedDB，全部可单测
    data/            attrs、titles、items、rewards（奖励表 + need(lv)）、rank（档位阶梯 / rankShift）、
                     content（台词库 copy + content）、crisisWords、dailyPool
    model/           Quest、PlanTask、Goal、HostState、ActiveQuest、EvidenceShot、QuestResult、HistoryEntry
    flow/            questFlow（队列/接单/道具/暴击率/结算/认输/补救/换一个/购买/佩戴/补签——移植 quest_flow.dart）
                     grade（评级唯一口径）、streak（连胜）、rollDay（换日）、publish（在手窗口）
    goal/            categories（11 类目 + 访谈卡 + 倾向六维 + 专属日常池）、planWindow（滚动窗口、阶梯、分段）、
                     planProgressDigest、dailyPick
    machine/         主流程状态机：scene 枚举（boot/consent/onboard/lobby/main/board/exec/result/fail/archive/shop）
                     + 叠层（briefing/sheet/modal/chat/settings/evidenceSource/goalSwap/planLoading）的转移规则
    save/            SaveData 模型、toJson/fromJson（在默认值上合并）、版本号、导出包格式与校验
    time/            clock（可注入）、日历日工具、away 问候分档
  agent/           LLM 层（不碰 React；依赖注入 fetch，便于测）
    llmClient.ts     OpenAI 兼容 /v1/chat/completions；重试（502/503/504/断网 ×1，800ms）、超时不重试、失败分类
                     （noKey / noConsent / network / cors / http4xx / http5xx / timeout / badJson / noPlan / badGoal）
    corsProbe.ts     区分 CORS 与断网（见 5.3）
    persona.ts       backstory 原文 + 四语气 + 铁律 + splitTag（12 情绪）
    guardrail.ts     护栏条款、〔不拆〕识别；crisisGate（本地自伤闸门）
    goalMatch.ts     set_goal_category
    planBrief.ts / planAgent.ts   首段 / 续拆 / 收官提示词；>12 张两路并行；set_plan 解析与校验
    tools.ts         set_goal_category / set_plan / adjust_plan / swap_quest / get_status / summarize_progress / remember / recall
    vision.ts        证据校验（30s 超时、不重试、4 态结论）
    memory.ts        长期记忆（访谈答案 + remember；digest ≤8 条）
    chatService.ts   聊天工具循环
  store/           Zustand
    db.ts            Dexie：kv（save / save.bak / save.corrupt / consent / llmSettings / prefs）、chat、history、memory、evidence（Blob）
    saveRepo.ts      读档（主档→坏档另存 corrupt→退 bak）、写档（先滚 bak 再写主档）、重置、导出 / 导入
    autosave.ts      订阅存档字段 → 同一拍合并 → 串行写入
    gameStore.ts     host / goal / queue / active / pendingGoal / 运行时连胜与退缩字段（全部进存档）
    uiStore.ts       当前场景、叠层栈、她的台词气泡、toast
    actions/         编排器：boot、bind（绑定仪式）、plan（拆解 / 重试 / 续拆）、exec（接单 / 证据 / 交单 / 认输）、
                     settle（结算演出数据）、shop、chat、settings、wipe、backup
  audio/           音效总线（按 build-game-audio-feedback skill 设计，见 5.5）
  ui/
    kit/             Button（按下声在这里）、HoldButton（按住认输）、Sheet、Modal、Toast、Typewriter、Core（她的头像）、
                     Ring、Bar、RankBadge、TicketCard、Carousel、Radar、FlashLayer、FxCanvas、Background
    scenes/          Boot、Consent、Onboard（输入 / 访谈 / 复核态）、Lobby、Main、Board、Exec、Result、Fail、Archive、Shop
    overlays/        Briefing、EvidenceSource、SystemSheet、LlmSettings、GoalSwap、PlanLoading、Chat、InstallGuide、LevelUp
    hooks/           useReducedMotion、useVisibility（页面不可见暂停常驻动画）、useKeyboardInset、useComposition
  main.tsx / App.tsx
tests/             Vitest：core/**、agent/**、store/**（Dexie 用 fake-indexeddb）
```

## 3. 关键设计决定（我按真源自己定的，不同意就改）

1. **存档结构**：一个 `SaveData` JSON（`v: 1`）存在 Dexie `kv` 表，值用字符串，保留「能解析才算好档」的语义：写前把上一份好串滚进 `save.bak`；读坏把原串存 `save.corrupt` 再退 bak；没有主档时不翻 bak。
2. **旧版漏存的运行时字段一并入档**：`lastDoneDay`（连胜判定）、`retreatDay / retreatToday / retreatTotal`、`titleBeforeShame`、`remedyOffer / remedyDeadline`、`lastRollDay`。旧版这些只活在内存里，重启后下一单的连胜会被算成 1 —— 属于 bug，PWA 直接修掉。另按第 6 节定案新增：`brokenStreak / missedDay`（补签用）、执行中单据的护盾顺延截止时间。
3. **自动存档**：`gameStore` 里所有存档字段的改动都走 core 的纯函数返回新状态；`autosave` 订阅这一片，`queueMicrotask` 合并同一拍，写盘排串行 Promise 链；读档完成前不写。切后台（`visibilitychange` hidden / `pagehide`）额外立即写一次。
4. **结算的时序**沿用 G4.1：入账 → 清 active → 补发 → 记流水 → 先落盘 → 再 await 续拆 / 收官；拆解失败抛 `SettleFollowUpFailed`，结算页照常演这一单，大厅出「重试拆解」待拆卡。
5. **证据照片**：选图后先压缩（`createImageBitmap` → canvas，长边 ≤1024，JPEG q≈0.82）再入库；库里只存压缩后 Blob，存档里只存证据 id + 状态。视觉请求直接用这份 JPEG 转 data URL。
6. **开发期功能**（演示截图、秘籍、彩蛋提示）只在 `import.meta.env.DEV` 下出现，生产构建不带。演示截图同样「不送校验、按未校验照收」（D3.1）。
7. **首启告知页（简化版）**：一页说明「目标、聊天、照片会发给你自己配置的模型服务商」+【同意】，同意记录（版本号 + 时间）单独存、重置不清；系统设置里能重看 / 撤回。不再出用户协议 / 隐私政策全文页。未同意时 `llmClient` 闸门零请求（`noConsent`）。
8. **设置项**：LLM 设置页（端点 / Key / 文本模型 / 视觉模型 / 温度 /【测试连接】）；系统设置抽屉里有：音效开关 + 音量、证据视觉校验开关（G2.3）、LLM 设置入口、告知与同意、导出 / 导入存档、重置存档。没有流式、思考档位、严格模式、上下文上限这些旧开发参数。
9. **拆解超时**：拆解 / 续拆单次请求 90s、匹配 30s、聊天 45s、视觉 30s；统一「超时不重试」。
10. **路由**：不用 URL 路由，场景由状态机驱动（与旧版一致），浏览器返回键（`popstate`）映射成「关叠层 / 返回上一场景」。

## 4. 开发顺序与每步验收

每一步结束都跑：`npx tsc --noEmit`、`npx vitest run`、`npm run build`，全绿才提交（在 `main` 上提交，中文 Conventional Commits，不 push）。

| 步 | 内容 | 验法 |
|---|---|---|
| 1 | **工程骨架 + 设计令牌 + 存档层**：替换 `.gitignore`；Vite + React 19 + TS strict + vite-plugin-pwa（先占位）+ Motion + Zustand + Dexie + Vitest；ESLint/Prettier 最小配置；`tokens.css`/`tokens.ts`、Fontsource 字体；`core/save` 模型 + `store/db.ts` + `saveRepo`（主档 / bak / corrupt / 重置 / 导出导入校验）+ `autosave` | 存档单测（移植 `save_file_test` / `g_save_backup_test` / `autosave_test` 的断言 + 导出导入往返、坏包拒收不动数据、导入前先备份）；令牌单测（稀有度色与 `Ref.rank` 一致） |
| 2 | **核心逻辑 + 单测**：data 全量、模型、questFlow（结算 / 认输 / 补救顶替 / 道具 / 暴击率 / 连胜 / 换一个 / 购买 / 佩戴 / 补签）、评级、换日、在手窗口、11 类目与访谈卡、日常池、滚动窗口与阶梯、主线解锁口径、台词库 | 移植 `rewards_test`（含「显示 = 结算」全档位交叉断言）、`quest_flow_test`、`quest_test`、`checkin_quest_test`、`goal_gen_test`、`plan_segment_test`、`g_total_exp_test`、`e1/e2_fixes_test`、`content_test`、`away_test`、`app_clock_test` 的核心断言 |
| 3 | **LLM 层与拆解**：llmClient + 失败分类 + CORS 探测、persona、护栏 + 自伤闸门、匹配、首段 / 续拆 / 收官拆解（两路并行）、工具注册表、视觉校验、记忆 | 移植 `llm_client_test`、`llm_gateway_test`、`plan_agent_test`、`plan_pipeline_test`、`agent_test`、`vision_test`、`evidence_checks_test`、`g_llm_vision_test`、`g_guardrail_test`、`g_consent_test`（闸门部分）；全部用假 fetch |
| 4 | **大厅与绑定流程**：设备壳 / 背景 / 粒子 / 亮帧 / 打字机 / 按钮 / 她的头像等基础件；开机 → 首启告知 → 绑定仪式（输入 → 匹配 → 3 张访谈卡 → 分步拆解进度 → 复核态与四个按钮 → 先跳过）→ 大厅（主线卡 / 待拆卡 / 立目标卡、委托球、执行中药丸、HUD、系统设置抽屉、LLM 设置页、换日问候） | 组件级逻辑单测（字数只数已上屏、组字时置灰、50/200 上限）；构建通过；交互由宿主在手机上验 |
| 5 | **执行 / 结算 / 失败**：接单前简报、执行面板（计时单 / 打卡单、证据槽 ≤3、来源底板、后台校验、拒收留痕、道具托盘、按住认输、交单等校验 ≤20s）、结算演出（扫描 → 评级 → count-up → 暴击 → 经验条 → 升级）、失败页 + 补救票、超时判负 | 结算演出的时间轴做成纯数据（`buildSettleTimeline()`）并单测总时长 ≤1.6s、升级 ≤2s；证据封存 / 迟到结论丢弃单测 |
| 6 | **委托板 / 主线 / 补给 / 档案 / 聊天**：委托板 tabs + 票券 + 主线锁 + 空态区分；主线页（3D 卡轮播 + 分段标识 + 节点轨 + 战报评级）；换目标（含首次立目标模式）；补给货架 + 购买 / 使用；档案（资料卡 / 雷达 / 名牒册 / 7 天战报 / 六维条 / 累计 EXP）；聊天面板（工具卡、状态卡、打字中、自伤闸门） | `chat_test` 核心断言；`HistoryLog.summarize` 单测 |
| 7 | **PWA 化**：manifest、图标（`brand/icon/app-icon.svg` → assets-generator）、SW 预缓存壳 + 音效、字体运行时 CacheFirst、iOS 添加到主屏引导、`storage.persist()`、安全区 / `100dvh` / 键盘、音效总线、震动、后台暂停动画 | 构建产物检查（manifest 字段、precache 清单里没有 woff2、有音效）；音效总线单测（优先级、并发上限、节点释放，假 AudioContext） |
| 8 | **部署说明 + 收尾**：`docs/02-部署到CloudflarePages.md`、根目录 `AGENTS.md`、一次性验收清单 | — |

## 5. 几处技术细节

### 5.1 字体
- `@fontsource/chakra-petch`：500、700、700-italic；`@fontsource-variable/noto-sans-sc`、`@fontsource-variable/jetbrains-mono`（wght 轴）。自带 `unicode-range` 分片与 `font-display: swap`。
- Workbox `globPatterns` 排除 `*.woff2`，另配 `runtimeCaching`：同源 `/assets/*.woff2` → CacheFirst（上限 300 条、1 年）。

### 5.2 动效
- 所有动效参数集中在 `design/tokens.ts`（弹簧 100/20 过冲 1.08、亮帧 16% 180ms、count-up 800ms easeOutCubic、暴击定格 200ms + 印章 2.2→1、经验条 520 / 360+420、结算 ≤1.6s、升级 ≤2s 同日简版、发布 ≤800ms、失败亮度 1/3、打字机 34ms/字）。只动 `transform` / `opacity`；禁线性（lint 规则 + 令牌里不提供 linear）。
- `prefers-reduced-motion`：位移类过渡改淡入淡出、循环动画停、count-up 直接落值；一次性反馈（按压、亮帧）保留但减弱。
- 常驻循环（背景浮尘、底纹、扫光、委托球脉冲）在 `document.hidden` 时暂停（canvas 停 rAF，CSS 动画加 `animation-play-state: paused`）。

### 5.3 LLM 直连与 CORS
- 浏览器里 CORS 拦截和断网都表现为 `fetch` 抛 `TypeError`。区分办法：`navigator.onLine` 为假 → 断网；否则对同一端点发一次 `mode: 'no-cors'` 的 GET，能拿到 opaque 响应 = 服务器通、是 CORS 拦了；也失败 = 网络 / 域名问题。测试连接与正式请求都用这套分类。
- 提示里写清楚：服务商需要允许浏览器跨域（返回 `Access-Control-Allow-Origin`），否则得换支持的服务商或自己加一层代理。
- Key 只存在本机 IndexedDB；构建产物里不出现任何默认 Key / 默认端点。

### 5.4 键盘与输入
- 绑定页 / 聊天的 CTA 跟随 `visualViewport` 高度变化吸在键盘上沿；`compositionstart/end` 期间不计字数、CTA 置灰；超长粘贴截尾并提示。

### 5.5 音效（做到第 7 步时先加载 `build-game-audio-feedback` skill 再细化）
- 单个 `AudioContext`；事件 → 声音映射表带优先级（关键：结算 / 暴击 / 升级 / 失败 > 普通：接单、购买、拒收 > 界面：按下、切换、打字）；同时发声上限（如 8 路），超限丢最低优先级；`onended` 释放节点。
- 首次 `pointerdown` / `keydown` 解锁；`navigator.audioSession.type = 'ambient'`（存在才设）；`visibilitychange` 停底噪、回前台按设置恢复。
- 按下声在 `kit/Button` 里出；业务回调只播结果声。静音开关 + 音量进系统设置；每个有意义的提示音都有对应视觉反馈。
- 素材：重新设计、脚本离线合成（见第 6 节 Q1），接入总线前先给宿主过目清单和试听页。

## 6. 宿主定案（2026-11-21）

> 旧代码和第 00 文、docs/50 都没写死，或者两边对不上的地方，已逐条拍板。

### Q1 音效：重新做一套，脚本离线合成
- 不沿用旧版 135 个 wav，也不照搬参考稿的 Web Audio 参数。按 `build-game-audio-feedback` skill 重新设计事件表和音色。
- 产出方式：`tools/audio/` 下写一个零依赖 Node 合成脚本（同 seed 产出逐字节一致），生成 wav → ffmpeg 转成压缩格式（iOS Safari 能解的 m4a/AAC 或 mp3）放进 `public/audio/`，Service Worker 预缓存。
- 第 7 步动手前先交给宿主过目：**事件 → 声音清单**（含优先级）和一个**试听页**（开发环境下打开，逐条点听）。宿主点头后再接进总线。

### Q2 道具文案：数值不动，文案改成说真话
| 道具 | 原文案 | 新文案 |
|---|---|---|
| 暴击芯片 | 本单暴击率 +25%。暴击时奖励 ×1.5，属性额外 +1。 | 本单暴击率 +25%。暴击时 EXP 与晶核 ×2。 |
| 双倍卡 | 本单 EXP 与晶核 ×2。贪心是第一生产力。 | 本单 EXP ×2，晶核不翻倍。贪心是第一生产力。 |

### Q3 护盾：换成「超时免判负一次」
- 价格 90 晶核、2 级解锁不变；执行中装载，每单限一张，装上即扣库存（与另外两张执行道具同口径）。
- 新文案：「计时单到点时替你挡一次：不判负，再续原时长的一半。」
- 规则：
  - 计时单到点时，若装着护盾 → 护盾碎掉（本单的护盾标记清掉），**不判负**，截止时间顺延 `ceil(时长 ÷ 2)` 分钟；顺延的截止时间记进执行中单据（随档走，杀进程重开照样算）。顺延后再到点 → 正常超时判负。
  - 打卡单不会超时，所以**打卡单不能装护盾**（托盘里护盾置灰：「打卡单用不上」）。
  - 认输时护盾不起作用，也不退还。
  - 评级照旧按目标时长算（顺延不改目标时长）；碎盾那一刻要有视觉反馈 + 她一句台词 + 音效。
- 删掉旧代码里只被护盾影响、没人读的 `failStreak`。

### Q4 断签当场归零，补签券只补「刚断的那一天」
- 换日（或冷启动时发现已换日）检查最近完成日 `lastDoneDay`：昨天一单没完成 → 连胜当场归零，同时记下断之前的值 `brokenStreak` 和断掉的那一天 `missedDay`（= 昨天）。
- 补签券**只在「只断了一天、且就是昨天」**时能用：即 `missedDay` = 昨天，且断之前最后完成的是前天。效果：连胜恢复为 `brokenStreak + 1`（补上昨天），今天若已经完成过一单再 +1；`lastDoneDay` 相应改成昨天 / 今天，之后照常续。
- 其余情况补给页里补签券的【使用】置灰并说明原因：「没断签，用不上」/「断了不止一天，补不回来」/「过了补签的那一天」。
- 断签判定只看「一整天一单都没完成」，认输不影响（与 C6 定案一致）。

## 7. 不做 / 不带过来

- Flutter 老存档迁移、旧色谱、Live2D、口型包络（`voice.dart`）、画质档「省电」开关（由 `prefers-reduced-motion` + 页面可见性替代）、安卓模拟器 Agent 工具、调试桥 `dev/agent_bridge`。
- 账号、云同步、后端代理。
