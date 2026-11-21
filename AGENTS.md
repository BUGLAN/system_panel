# AGENTS.md · 宿主养成系统（PWA）

网文「系统流」风格的自我提升工具：用户是「宿主」，App 是毒舌但靠谱的系统娘「小祥」。用户立一个目标，她把目标拆成一单一单的「委托」；接单、按时完成、交照片证据，她验收、结算经验和奖励。

- 全程中文：界面文案、代码注释、提交信息、回复都写中文。
- 旧的 Flutter 版完整保存在 git tag `flutter-final`（产品机制、数值、文案的历史真源，用 `git show flutter-final:<路径>` 读）。main 上不再有 Flutter 代码。

## 技术栈

Vite 8 + React 19 + TypeScript 6（strict）+ vite-plugin-pwa；动效 Motion（`motion/react`）；状态 Zustand；本地存储 IndexedDB（Dexie）；单测 Vitest。TypeScript 停在 6.0：typescript-eslint 目前只支持到 6.0。

## 命令

| 命令 | 作用 |
|---|---|
| `npm run dev` | 开发服务器（Service Worker 不启用） |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | `vitest run` |
| `npm run build` | 构建到 `dist/`（可直接部署 Cloudflare Pages） |
| `npm run check` | 类型检查 + 单测 + 构建 + 构建产物检查（每次提交前跑） |
| `npm run check:dist` | 只跑构建产物检查（manifest / 预缓存 / 无 Key） |
| `npm run lint` / `npm run format` | ESLint / Prettier |
| `npm run sfx` | 重新合成音效（`tools/audio/gen-sfx.mjs` → `public/audio/`，需要 ffmpeg） |
| `npm run icons` | 由 `public/app-icon.svg` 重新生成 PWA 图标 |

开发时打开 `/sfx-lab.html` 可逐条试听音效（不进构建产物）。部署见 `docs/02-部署到CloudflarePages.md`，验收见 `docs/03-验收清单.md`。

## 目录与分层

```
src/
  design/   设计令牌：tokens.css 是唯一源（颜色 / 稀有度色 / 字体 / 缓动 / 布局），tokens.ts 镜像（单测钉住两边一致）、动效参数
  core/     纯逻辑，不碰 DOM / React / IndexedDB，全部可单测
    data/     六维、档位、奖励表与暴击率、道具、称号、11 类目与访谈卡、日常池、台词库
    model/    委托 / 目标 / 宿主 / 执行中单据与证据（数据形状 + 存档读写）
    goal/     类目查找、计划规则（滚动窗口、阶梯、分段、校验、续拆）、日常派发、拆解失败类型
    flow/     QuestFlow（队列 / 接单 / 道具 / 证据 / 换一个 / 补给 / 佩戴 / 补签 / 换日）、settle.ts（结算 / 认输 / 超时护盾）、评级、流水汇总、结算时间轴
    save/     SaveData（版本号、在默认值上合并）、导出包格式与校验
    time/     日历日、离开时长问候
  agent/    LLM：客户端（重试 / 超时 / 失败分类 / CORS 探测）、人设、护栏、拆解与匹配代理、工具、视觉校验、长期记忆、聊天、台词入口
  store/    Zustand 与编排：gameStore（存档）、uiStore（场景 / 叠层）、services（设置 / 同意 / 偏好 / 客户端工厂）、
            saveRepo / dataRepo（主档 / 备份 / 坏档 / 重置 / 导出导入）、autosave、actions/（开机、绑定、拆解、执行、证据、聊天、换目标、导航）
  audio/    音效总线（bus.ts）与发声调度（voices.ts，纯逻辑可测）
  ui/       styles/（参考稿 CSS 原样拆出 + 新增页样式）、kit/（基础组件）、shell/（设备壳 / HUD / 转场）、scenes/、overlays/
tests/      Vitest：core / agent / store / audio / design
tools/audio/  音效合成脚本
scripts/      构建产物检查
docs/         00 重写提示词 · 01 实施计划与定案 · 02 部署 · 03 验收清单
```

改存档只走 `store/game.ts` 的 `runFlow`（在深拷贝上跑 QuestFlow，`changed` 才提交 → 自动存档）；界面层不直接改 game。

## 约定

- 单个文件不超过 600 行（生成的数据文件 `core/data/categories.ts` 也压在 600 内，已从 Prettier 排除）。
- 视觉照仓库根的 `宿主养成系统_重设计.html`：类名原样沿用；参考稿没有的页面（告知、绑定仪式、简报、加载卡、设置、聊天、换目标）用同一套令牌做。
- 颜色只从令牌取；稀有度色谱：F 灰 / E 薄荷 / D 青 / C 紫 / B 金 / A 品红 / S 白；评级色：S 白 / A acid / B cyan / C hot。
- 动效参数在 `design/tokens.ts` 的 `MOTION`，不许凭感觉改：弹簧 100/20 过冲 1.08；亮帧白 16% 180ms（音效踩这一帧）；count-up 800ms ease-out cubic；暴击定格 200ms + CRIT 印章 2.2→1；经验条 520 / 360+420；结算 ≤1.6s（`core/flow/settleTimeline.ts` 单测钉住）；升级 ≤2s，同日简版；发布 ≤800ms；失败亮度 1/3；打字机 34ms/字。只动 transform / opacity，禁线性匀速；尊重 `prefers-reduced-motion`；页面不可见时暂停常驻动画。
- 按下声由基础按钮（`ui/kit/Btn.tsx` 的 Btn / Tap）自己出；业务回调里只播结果声。有意义的提示音都有对应的画面反馈。
- 等 LLM 的地方都走 `store/actions/planJob.ts` 的 `withPlanJob`：整屏加载卡 + 防连点 + 迟到回包丢弃。
- 不提交 `.env`、`node_modules/`、`dist/`、任何 Key；前端代码和产物里不允许出现默认 Key / 默认端点（`check:dist` 会扫）。
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

**证据**：4 态（verified / unsure / unverified / mismatch），不符拒收并留痕「上一张被拒：…」；选图后压缩（长边 ≤1024、JPEG）入库、后台校验；交单最多等 20 秒；视觉校验 30 秒超时不重试；交单即封存，迟到结论丢弃；最多 3 张。

**LLM**：用户自填端点 / Key / 文本模型 / 视觉模型 / 温度，存在本机 IndexedDB；502/503/504 与断网重试 1 次（800ms），超时不重试；CORS 与断网用 no-cors 探测区分；不发 `max_tokens` / `reasoning_effort`（推理模型会 400），服务商拒温度时去掉温度再试；没同意首启告知页零请求。

**人设与护栏**：`agent/persona.ts` 的 `BACKSTORY` 原文一字不改、每次系统提示词以它开头；四语气 + 铁律（≤3 句、无 emoji、先吐槽再给下一步、句首 [情绪]，12 种）；减重每周 ≤ 约 1 公斤、不出断食 / 催吐 / 泻药 / 脱水 / 极端热量缺口 / 带伤硬练、违法伤人不拆；目标与聊天发送前过本地自伤闸门（命中不发 LLM，不写热线号码）。输入上限：目标与访谈「自己写」50 字、聊天 200 字，组字时不计、CTA 置灰。

**存档**：任何改动合并到同一拍串行写；写前滚 bak，主档坏了另存 corrupt 再从 bak 恢复；重置清 存档 / 备份 / 聊天 / 流水 / 长期记忆 / 证据照片 / 导入前快照，不清 LLM 设置、同意、偏好；导出范围与重置一致（照片 Base64，不含 Key 与同意），导入先校验格式与版本、不合格不动数据、通过后先存快照再整体覆盖。不迁移 Flutter 旧存档。

**音效**：重新做（`tools/audio/gen-sfx.mjs` 合成）；层级 critical（stamp / crit / levelup / fail / shield）> event > ui > texture；8 路上限、按优先级抢占、关键音压低界面音；首次手势解锁、iOS `audioSession.type = 'ambient'`；底噪只在大厅且前台时响，切后台停并挂起；设置里有静音和音量。

**PWA**：Service Worker 预缓存应用壳与音效，字体分片运行时 CacheFirst；新版本等回到大厅且没有执行中的单才切；启动调 `navigator.storage.persist()`；第一次进大厅弹「添加到主屏幕」引导。

## 已知事项

- `npm audit` 报 4 个中危，都在构建期的 workbox-build → glob → minimatch，不进产物；等上游升级。
- 视觉判定本身有波动（同一张图可能一次判不符、一次收下），这是模型行为，没有在代码里兜。
- 浏览器直连 LLM 依赖服务商放行 CORS；不放行的服务商用不了（测试连接会明确报「跨域被拦」）。
