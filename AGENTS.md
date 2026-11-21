# AGENTS.md · 宿主养成系统（服务器 + SQLite 多用户 PWA）

网文「系统流」风格的自我提升工具：用户是「宿主」，App 是毒舌但靠谱的系统娘「小祥」。用户立一个目标，她把目标拆成一单一单的「委托」；接单、按时完成、交照片证据，她验收、结算经验和奖励。

部署在自己的服务器上，宿主本人 + 少量朋友用（邀请码注册，数据按账号隔离）。**服务端权威**：规则（QuestFlow）、时间、随机数、LLM 调用都在服务端；前端只发「意图」、拿回整份最新状态。

- 全程中文：界面文案、代码注释、提交信息、回复都写中文。
- 旧的 Flutter 版完整保存在 git tag `flutter-final`（产品机制、数值、文案的历史真源，用 `git show flutter-final:<路径>` 读）。main 上不再有 Flutter 代码。

## 技术栈

npm workspaces，全栈 TypeScript 6（strict；typescript-eslint 目前只支持到 6.0）：

- 前端 `apps/web`：Vite 8 + React 19 + vite-plugin-pwa；动效 Motion（`motion/react`）；状态 Zustand；IndexedDB（Dexie）只存偏好与离线只读缓存
- 服务端 `apps/server`：Node 22 + Hono（`@hono/node-server`）；SQLite（better-sqlite3，WAL）+ Drizzle（迁移）；zod 校验；argon2id（`@node-rs/argon2`）；esbuild 打包
- 共用 `packages/core`：纯逻辑，前后端同一份
- 单测 Vitest（三个工作区各一个 project）；服务端接口测试用内存 SQLite + `app.request()`

## 命令

| 命令 | 作用 |
|---|---|
| `npm run dev` | 同时起服务端（`tsx watch`，:8787）和前端（vite，:5173，`/api` 代理到服务端；`API_TARGET` 可改目标） |
| `npm run dev:server` / `npm run dev:web` | 只起一边 |
| `npm run typecheck` | 三个工作区分别 `tsc --noEmit` |
| `npm test` | `vitest run`（core / web / server） |
| `npm run build` | 前端构建到 `apps/web/dist`，服务端打包到 `apps/server/dist`（`main.mjs` + `cli.mjs` + `drizzle/`） |
| `npm run check` | 类型检查 + 单测 + 构建 + 构建产物检查（每次提交前跑） |
| `npm run check:dist` | 只跑构建产物检查（manifest / 预缓存 / SW 不碰 /api / 前端不直连模型 / 前后端无 Key） |
| `npm start` | 跑打包后的服务端（读根目录 `.env`） |
| `npm run admin -- <命令>` | 管理员命令行（开发环境；生产见 docs/02）：create-admin / invite / invites / reset-password / disable / enable / users / backup |
| `npm run db:generate` | 改了 `apps/server/src/db/schema.ts` 后生成迁移（一起提交） |
| `npm run lint` / `npm run format` | ESLint / Prettier |
| `npm run sfx` | 重新合成音效（`tools/audio/gen-sfx.mjs` → `apps/web/public/audio/`，需要 ffmpeg） |
| `npm run icons` | 由 `apps/web/public/app-icon.svg` 重新生成 PWA 图标 |

开发时打开 `/sfx-lab.html` 可逐条试听音效（不进构建产物）。部署见 `docs/02-部署到自己的服务器.md`，验收见 `docs/03-验收清单.md`，全栈改造的来由见 `docs/04`、`docs/05`。

## 目录与分层

```
packages/core/src/      纯逻辑（前后端共用），不碰 DOM / React / Node API / 存储，全部可单测
  data/                   六维、档位、奖励表与暴击率、道具、称号、11 类目与访谈卡、日常池、台词库
  model/                  委托 / 目标 / 宿主 / 执行中单据与证据（数据形状 + 存档读写）
  goal/                   类目查找、计划规则（滚动窗口、阶梯、分段、校验、续拆）、日常派发、拆解失败类型与失败卡文案
  flow/                   QuestFlow（队列 / 接单 / 道具 / 证据 / 换一个 / 补给 / 佩戴 / 补签 / 换日）、settle.ts（结算 / 认输 / 超时护盾）、评级、流水汇总
  save/                   SaveData（版本号、在默认值上合并）、导出包格式与校验
  time/                   日历日（按账号时区）、离开时长问候
  agent/                  人设（BACKSTORY）、护栏与自伤闸门、聊天消息形状、状态摘要
  api/types.ts            前后端接口契约（StateView / FlowEvent / 拆解任务 / 设置 / 证据结论…）
packages/core/tests/      core 单测（含 testing/fixtures、helpers，别的工作区也引用）

apps/server/src/
  config.ts / log.ts      环境变量（生产缺关键项拒绝启动）/ 脱敏日志
  db/                     Drizzle 表结构、打开库（WAL、外键、启动时迁移）；迁移文件在 apps/server/drizzle/
  auth/                   口令（argon2id）、会话（只存 token 哈希）、邀请码、账号
  http/                   依赖与上下文、错误格式、限流、意图去重（x-intent-id）、zod 入参
  flow/                   每用户串行锁、runFlow（锁内 读档 → 换日 → 到点 → 意图 → 写回）、交单编排
  repo/                   存档（主档 / bak / corrupt）、流水、聊天、记忆、同意、模型设置（Key 加密）、用量、导出导入重置
  llm/                    用户的 LLM 入口（服务器默认 / 自己的 + 同意闸门 + 额度闸门）、Key 加密
  agent/                  LLM 客户端（重试 / 超时 / 失败分类）、拆解与匹配代理、工具、视觉校验、长期记忆、聊天
  jobs/                   拆解任务（一人一件、进度推 SSE、落库前核对前提）、首目标落库
  evidence/               证据磁盘存储（data/uploads/<用户>/）、在途校验登记
  events/bus.ts           用户事件总线（SSE）
  routes/                 /api/*：auth、me、state + flow/*、evidence、plan、llm、consent、chat、data、stream、health
  static.ts / main.ts     生产环境托管前端产物 / 入口；cli/ 管理员命令与备份
apps/server/tests/        接口测试（内存 SQLite）+ agent 单测

apps/web/src/
  design/                 设计令牌：tokens.css 是唯一源，tokens.ts 镜像（单测钉住两边一致）、动效参数
  store/                  api.ts（fetch 封装）、game.ts（存档镜像 + intent() + 校时）、stream.ts（SSE）、cache.ts / db.ts（偏好与离线缓存）、
                          services.ts（账号 / 同意 / 模型设置 / 偏好）、uiStore、actions/（开机、登录、绑定、拆解、执行、证据、聊天、换目标、数据、导航、会话时钟）
  audio/                  音效总线（bus.ts）与发声调度（voices.ts，纯逻辑可测）
  ui/                     styles/（参考稿 CSS 原样拆出 + 新增页样式）、kit/、fx/（含结算时间轴）、shell/、scenes/（含登录页）、overlays/
apps/web/tests/           前端单测（设计令牌、音效调度、结算时间轴、数据层）

tools/audio/  音效合成脚本    scripts/  构建产物检查、开发启动    deploy/  Caddyfile
docs/         00 重写提示词 · 01 PWA 实施计划与定案 · 02 部署 · 03 验收清单 · 04 全栈改造提示词 · 05 全栈改造实施计划
```

改存档只走服务端的 `flow/runner.ts` 的 `runFlow`（锁内在副本上跑 QuestFlow，`changed` 才写回，被拒的意图改动作废）；前端只读存档镜像，改动一律走 `store/game.ts` 的 `intent()`。

## 约定

- 单个文件不超过 600 行（生成的数据文件 `packages/core/src/data/categories.ts` 也压在 600 内，已从 Prettier 排除）。
- `packages/core` 不许用 DOM / Node API（tsconfig 只给 ES 库 + `structuredClone` / `btoa` / `atob` 声明）；要「现在几点」「哪一天」一律由调用方传 `now` 与时区。
- 服务端：每个查询都按当前用户过滤（repo 函数第一个参数是 userId）；按 id 取资源「不存在」与「不是你的」一律 404，并写 A/B 交叉测试。写接口校验 Origin；入参都过 zod；错误统一 `{ ok:false, code, message }`，message 是能念给宿主听的中文。
- 服务端权威：时间取服务器、随机数取服务器（密码学随机源）、换日与计时单到点在每个请求进来时懒判定；前端到点只发 `tick` 请求、跨日只拉状态。
- LLM 只在服务端调；前端产物里不许出现模型端点、Bearer、任何 Key（`check:dist` 会扫）。等 LLM 的地方前端走 `store/actions/planJob.ts`（整屏加载卡 + 防连点 + 迟到结果丢弃），服务端走拆解任务（不持锁等 LLM，回来重读存档核对前提再落库）。
- 视觉照仓库根的 `宿主养成系统_重设计.html`：类名原样沿用；参考稿没有的页面（告知、绑定仪式、简报、加载卡、设置、聊天、换目标）用同一套令牌做。
- 颜色只从令牌取；稀有度色谱：F 灰 / E 薄荷 / D 青 / C 紫 / B 金 / A 品红 / S 白；评级色：S 白 / A acid / B cyan / C hot。
- 动效参数在 `design/tokens.ts` 的 `MOTION`，不许凭感觉改：弹簧 100/20 过冲 1.08；亮帧白 16% 180ms（音效踩这一帧）；count-up 800ms ease-out cubic；暴击定格 200ms + CRIT 印章 2.2→1；经验条 520 / 360+420；结算 ≤1.6s（`core/flow/settleTimeline.ts` 单测钉住）；升级 ≤2s，同日简版；发布 ≤800ms；失败亮度 1/3；打字机 34ms/字。只动 transform / opacity，禁线性匀速；尊重 `prefers-reduced-motion`；页面不可见时暂停常驻动画。
- 按下声由基础按钮（`ui/kit/Btn.tsx` 的 Btn / Tap）自己出；业务回调里只播结果声。有意义的提示音都有对应的画面反馈。
- 不提交 `.env`、`data/`、`backups/`、`node_modules/`、`dist/`、任何 Key；密钥只从环境变量读，日志不打印 Key / Cookie / 口令 / 照片。
- 改表结构：改 `apps/server/src/db/schema.ts` → `npm run db:generate` → 迁移文件一起提交。
- 提交：中文 Conventional Commits。

## 定案（改之前先问宿主）

**数值**（`core/data/rewards.ts`，一个都不许改）：EXP F0/E1/D2/C4/B6/A8/S10；晶核 F3/E~C 5/B7/A10/S20；`need(lv) = 12 + lv×6`；暴击 ×2、双倍卡 ×2（可叠 ×4）、补救单 ×0.5 且 EXP 保底 1，晶核吃暴击不吃双倍；暴击率 底 6% + 已校验 7%/张 + 拿不准/未校验 4%/张 + 连胜 1%/天（≤10）+ 芯片 25%，封顶 85%；累计 EXP 单独记、只增不减。「显示 = 结算」有全档位交叉单测。

**评级**：有判真证据 = A；只有拿不准 / 未校验 = B；没证据 = C；计时单用时不到目标 1/4 降一档；暴击 A → S；打卡单不看用时。

**连胜**：当天第一单 +1；只有一整天一单都没完成才断，换日时发现昨天没完成就当场归零；认输不断连胜。旧版漏存的运行时字段（最近完成日、退缩计数、补救单截止…）都在 `SaveData.meta` 里。

**补签券**：只补「只断了一天、且就是昨天」的那一天：连胜恢复为断前 +1（今天已完成再 +1）；其余情况不可用并说明原因。

**护盾**：超时免判负一次——计时单到点时护盾碎掉、不判负、截止顺延 ceil(时长÷2) 分钟；打卡单不能装；认输时不起作用。

**道具文案**说真话：暴击芯片「暴击时 EXP 与晶核 ×2」、双倍卡「EXP ×2，晶核不翻倍」。价格：暴击芯片 45 / 双倍卡 60 / 护盾 90（LV2 解锁）/ 补签券 30。

**认输与补救**：主线认输 → 补救单顶替这一环（继承 goalId / planIndex，当场入队）；交掉 = 这一环过关；补救单再认输 → 原单补回。日常认输补救单只挂在失败页（「先放委托板」才进队列）。

**拆解**：只走 LLM，没有模板兜底；11 类目各 3 张访谈卡；滚动生成每次一个窗口 14 张（总数更少按总数），>12 张两路并行；第一段只出 E~C，之后按位置 E→D→C→B→A，最后一段收 S 兑现单；失败停复核态（错误卡 + 已答卡 +【重试拆解】【换个说法】「改答案」「先跳过」，答案不清空）；「先跳过」记住目标、当天先发日常，大厅给待拆卡；清单走完没续上给【重试拆解】。主线只能接清单里第一张没完成的。

**证据规则**：4 态（verified / unsure / unverified / mismatch），不符拒收并留痕「上一张被拒：…」；入槽即未校验、服务端后台校验，结论经 SSE 推回；交单时服务端最多等 20 秒；视觉校验 30 秒超时不重试；交单即封存，迟到结论丢弃；最多 3 张。

**LLM**：全部由服务端调用。默认用环境变量里的一套（端点 / Key / 文本模型 / 视觉模型）；用户可在设置里「用我自己的」——端点、Key、模型**整套**覆盖（不允许服务器的 Key + 自选模型），温度与视觉校验开关是个人设置。用户 Key 用 AES-256-GCM（`APP_ENCRYPTION_KEY`）加密存库，接口永远不回明文（只回末 4 位）。502/503/504 与断网重试 1 次（800ms），超时不重试；不发 `max_tokens` / `reasoning_effort`，服务商拒温度时去掉温度再试；没同意告知页零请求。限速每人每分钟 10 次（文本 / 视觉分开，自己的 Key 也限）；用服务器默认 Key 的普通用户每日文本 150 / 验图 60 次（管理员不限；都可用环境变量调）。超了是失败类型 `quota`：拆解出失败卡「今天额度用完了」、聊天走兜底台词、验图按未校验照收。

**人设与护栏**：`agent/persona.ts` 的 `BACKSTORY` 原文一字不改、每次系统提示词以它开头；四语气 + 铁律（≤3 句、无 emoji、先吐槽再给下一步、句首 [情绪]，12 种）；减重每周 ≤ 约 1 公斤、不出断食 / 催吐 / 泻药 / 脱水 / 极端热量缺口 / 带伤硬练、违法伤人不拆；目标与聊天发送前过自伤闸门，前端拦一次（即时反馈）、服务端再兜底（命中不调 LLM、不计用量，不写热线号码）。告知页 v2（`CONSENT_VERSION = 2`）：数据存服务器、经服务器转发给模型服务商、管理员技术上能接触数据；同意记录跟账号走。输入上限：目标与访谈「自己写」50 字、聊天 200 字，组字时不计、CTA 置灰。

**存档**：服务端每用户一行（`SaveData` JSON + 结构版本 + 存档版本号），同一用户的写操作串行；写前滚 bak；主档坏了原串存 `save_corrupt`、记日志、用 bak 恢复并告诉前端；两份都坏返回 `save_corrupt`、不清零。冲突按意图语义校验（意图带它针对的单号，不成立回 409 + 最新状态）；写意图带 `x-intent-id` 10 分钟内去重；导入 / 重置要求 `baseVersion` 严格一致。重置清 存档 / 备份 / 聊天 / 流水 / 长期记忆 / 证据照片（磁盘也删）/ 导入前快照，不清账号、LLM 设置、同意、偏好；导出范围与重置一致（照片 Base64，不含 Key、同意、账号），导入先校验格式、版本与每张照片、不合格不动数据、通过后先存快照（`data/snapshots/<用户>/`）再整体覆盖；别人的导出包也能导进自己的账号。不迁移 Flutter 旧存档；旧版 PWA 的数据走「导出 → 登录后导入」。

**账号**：用户名 + 密码（argon2id）；会话 Cookie httpOnly + SameSite=Lax（https 站点加 Secure 与 `__Host-` 前缀），30 天滑动续期，服务端存哈希可吊销；邀请码注册（管理员命令行生成，一次性、7 天）；App 内可改密码（改完其他设备下线），忘了密码由管理员命令行重置；没有找回邮件、第三方登录、管理后台网页。HUD 里的名字仍是存档里的「宿主」。

**时区**：「一天」按账号时区算（注册时取浏览器时区，之后只能管理员改），换日、连胜、补签、日常、每日额度同口径。

**多设备**：服务端通过 SSE 推「版本变了」，其他设备静默同步；演出只在发起操作的那台播，另一台执行页上的单没了就回大厅并提示「另一台设备刚改过存档」。拆解任务在服务端跑完就落库，关掉页面也算数；刷新后能接上在跑的任务。

**证据**：前端压缩（长边 ≤1024、JPEG）后上传；服务端验大小（≤2MB）与文件头，文件名由服务端生成，存 `data/uploads/<用户>/`（不在公开静态目录），只有主人能读。

**音效**：重新做（`tools/audio/gen-sfx.mjs` 合成）；层级 critical（stamp / crit / levelup / fail / shield）> event > ui > texture；8 路上限、按优先级抢占、关键音压低界面音；首次手势解锁、iOS `audioSession.type = 'ambient'`；底噪只在大厅且前台时响，切后台停并挂起；设置里有静音和音量。

**PWA**：Service Worker 预缓存应用壳与音效，字体分片运行时 CacheFirst；`/api/*` 不接管（导航回退排除、不注册缓存路由）；新版本等回到大厅且没有执行中的单才切；第一次进大厅弹「添加到主屏幕」引导。离线：外壳照旧能开，显示最近一次缓存的状态（只读），写操作提示「需要联网」、不排队；计时按服务器的 startAt 推导，断网期间照常走秒，到点由联网后的服务端判。

## 已知事项

- `npm audit` 报的中危都在构建 / 开发期依赖（workbox-build → glob → minimatch；drizzle-kit → @esbuild-kit → 旧 esbuild），不进产物（镜像里只装服务端生产依赖）；等上游升级。
- 视觉判定本身有波动（同一张图可能一次判不符、一次收下），这是模型行为，没有在代码里兜。
- 单进程部署：每用户锁、限流、意图去重、拆解任务、SSE 都在进程内存里；不支持多实例。服务重启 = 在跑的拆解任务丢失（前端按「网络断了」失败卡处理，可重试）。
- `APP_ENCRYPTION_KEY` 换了，用户存的 Key 全部解不开（要重填）；没有密钥轮换工具。
