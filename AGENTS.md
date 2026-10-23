# AGENTS.md — 宿主 SYSTEM 项目指南

> 本文件供 AI Agent 阅读：任何 Agent 在本项目工作前必读。产品是「网文系统流自我提升 App」——用户是宿主，App 是毒舌但靠谱的系统。
> 最后更新：2026-10-23（整体重写，只保留与当前 Flutter 工程一致的内容）

---

## 仓库与运行（先看这里）

- **仓库根目录：`E:\repo\system_panel`**（git 仓库，主分支 master）。规则文档在 `docs/`，Flutter 工程在 `app/`。
- **Flutter 工程在 `app/`**：applicationId 与 iOS bundle id 均为 `com.systempanel.app`。
  ```bash
  cd app && flutter run          # Android（MuMu 模拟器）
  cd app && flutter run -d 00008130-001169D830A1401C   # 真机 iPhone 15 Pro Max
  cd app && flutter analyze && flutter test
  ```
- **原型（历史参考，勿改动）**：`prototype/opus-v2-dir` 是宿主最终选定的那一版全息舞台原型，跑 `cd prototype/opus-v2-dir && node server.mjs` → http://localhost:4925。**它是历史参考，不是实现真源**——实现与验证一律落在 `app/`。
- **原型归档**：`prototype/` 下只留中选的 `opus-v2-dir` 与跨原型真源/证据（`.stitch`、`motion-demo`、`references`、`screens`、`stitch-bridge`）。另外 7 版历史原型在 `E:\repo\archive\`（不在本仓库内），索引见 `E:\repo\archive\README.md`。
- **动效样机**：`prototype/motion-demo/index.html`，静态服务挂 4920 端口即可。
- 未入库：`.env`（含 Stitch API Key）、`node_modules/`、`prototype/stitch-bridge/results/`

### 当前 `app/lib` 结构

| 目录 | 职责 |
|---|---|
| `main.dart` | 应用入口、状态机（`Moment`：boot / lobby / onboard / dispatch / exec / result / fail / sheet / main） |
| `agent/` | LLM 接入层：`llm_client`、`llm_gateway`、`llm_telemetry`、`mainline_agent`、`mainline_tool`、`persona`、`copy`、`memory`、`context_adapter`、`vision`、`settings_store`、`tools` |
| `state/` | 状态与数据：`host_state`、`goal`、`goal_gen`、`quest`、`quest_flow`、`result`、`save_file`、`settings`、`sfx`、`haptics`、`voice`、`app_clock`、`away` |
| `widgets/` | 35 个 UI 组件：`card_skins` / `card_table`（卡牌）、`hud` / `dock`（HUD 与底栏）、`main_view`（主线页）、`exec_panel` / `exec_pill`（执行面板）、`result_panel`、`plate`（派单板）、`radar`、`sheet`、`chat_bar`、`line_layer`（台词）等 |
| `design/tokens.dart` | 视觉与动效令牌唯一真源（颜色 `C`、字体 `F`、`Motion`、`StageAnchors`） |
| `data/` | 静态数据表：`rarity`、`attrs`、`items`、`titles`、`rewards`、`content`、`format` |
| `stage/` | Live2D 舞台 |
| `screens/` | `boot_screen` |
| `chat/` | 对话面板 |

---

## Agent 操作安卓模拟器（MuMu）

> 完整方案：[`docs/45-安卓模拟器Agent操作方案.md`](docs/45-安卓模拟器Agent操作方案.md)（调研结论、MCP 评估、证据等级）。
> 可复用动作：[`.claude/skills/android-agent/SKILL.md`](.claude/skills/android-agent/SKILL.md)。

- **不要找 MCP**。MuMu 官方 `mumu-control` skill 已装并跑通（`C:/Users/buglan/.agents/skills/mumu-control`，9 文件，MIT，Windows only）。`mumu-cli.exe` 与 `MuMuManager.exe` 是同一二进制（实测同尺寸同时间戳）
- **为什么不用裸 adb**：旧方案 64 次工具调用里至少 40 次在跟「没有 UI 元素模型」搏斗——`uiautomator dump` 出 size:0、Git Bash 改写 `/sdcard` 路径、中文乱码、只能截图猜坐标。改用 skill 后同类任务 2 条命令
- **环境**：设备 `127.0.0.1:16512`（端口用 `"E:/MuMu Player 12/nx_main/MuMuManager.exe" info -v all` 查）｜包名 `com.systempanel.app`｜屏幕 **1170×2532 @480dpi = 390×844dp（DPR 3）**
  - **2026-10-23 起：逻辑尺寸不变（390×844dp），物理面板提到 1170×2532@480 ⇒ DPR 从 2 升到 3**，Live2D 中频清晰度 **+110%**（详见 [`docs/46-Live2D清晰度-DPR与mipmap.md`](docs/46-Live2D清晰度-DPR与mipmap.md)）
  - ⚠️ **不要再 `wm size`/`wm density` 覆盖**：覆盖会把 SurfaceFlinger 从「1:1」变成「缩放」，实测中频掉 45%。当前 `display_size_forced = null` 就是正确状态
  - MuMu 实例 API 写分辨率的**顺序陷阱**：`resolution_mode` 设成 `custom` 会把三个值清零，且普通键 `key not writable` —— 必须写 `.custom` 后缀键（见 docs/46 §2）
- **三条命令覆盖 80% 场景**：
  ```bash
  SKILL="C:/Users/buglan/.agents/skills/mumu-control"
  cd "$SKILL" && python scripts/uiscan.py -s 127.0.0.1:16512 --save-json   # 截图+OCR+无障碍树 → 元素表+标注图
  python scripts/tap.py --text "档案" -s 127.0.0.1:16512                   # 按文字点，不用算坐标
  python scripts/uiscan.py -s 127.0.0.1:16512                              # 验证
  ```
- **脚本分工**：`uiscan.py`（双源识别）/ `tap.py`（按文字或坐标、长按）/ `swipe.py`（方向滑动）/ `input_text.py`（**支持中文**，裸 adb 不支持）/ `keyevent.py` / `screenshot.py` / `common.py`
- **高频动作封装**（`.claude/skills/android-agent/scripts/`）：`ui_snapshot.py`（快照 + `--compare` 基线对比）/ `dismiss_overlay.py`（关弹层：X → 空白 → 返回键，每步验证）/ `go_back.py`（逐级返回，退到桌面会自动拉回）/ `goto_lobby.py`（回大厅）/ `wait_stable.py`（等界面稳定）
- **依赖必须用腾讯源**：默认源与清华源不通、阿里云 27KB/s、腾讯云 60MB/s —— `pip install -r "$SKILL/requirements.txt" -i https://mirrors.cloud.tencent.com/pypi/simple/`
- **推荐循环**：`uiscan.py` → 读标注图找编号 → `tap.py` → `uiscan.py` 验证 → 循环
- **已知坑**：① 面板 X 关闭按钮**第一次点不生效**，要点两次；② 返回键在部分态会直接退 App（P0 待修），`go_back.py` 会检测前台包名并自动 `am start` 拉回；③ 多个 serial 可能指向同一台设备，只留一个
- **Flutter 端可被 Agent 看见**：`app/lib/dev/agent_bridge.dart`（仅 debug / `--dart-define=AGENT_BRIDGE=true` 启用）——全局 `Semantics` 包裹让 `dump_hierarchy` 读到中文；`AgentTag` 给关键 UI 打 `agent:<id>` 标签；`AgentBridge.dumpTree()` 导出组件树 JSON；`AgentBridge.screenshot()` 写 PNG 到 `/sdcard/agent/`。不开时 release 包零影响

---

## 技术栈（已拍板，勿再摇摆）

- **Flutter 跨平台框架**（Dart），目标 iOS + Android 双端高效运行
- 选型理由：Impeller 渲染引擎对大量动画友好（着色器预编译、无 jank），单代码库双端
- 动画实现约定：优先 `Transform`/`Opacity`（对应 web 端 transform/opacity 铁律）；弹簧用 `SpringSimulation(stiffness: 100, damping: 20)`；数字滚动用 count-up 补间；禁用线性匀速
- 状态管理建议 Riverpod；动效库建议 flutter_animate + 自定义弹簧
- **本机 Flutter 工具链**：Flutter `3.47.6` stable（Dart 3.13.5）装在 `D:\flutter`（已入 PATH），JDK 用 Android Studio 自带 JBR，Android SDK 在 `%LOCALAPPDATA%\Android\Sdk`，`flutter doctor` 全绿
- **全程国内源、不走代理（硬要求）**：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（已写入用户环境变量）；Gradle 走腾讯云镜像（`app/android/gradle/wrapper/gradle-wrapper.properties`），AGP/Kotlin 走阿里云镜像（`app/android/settings.gradle.kts`、`app/android/build.gradle.kts`）；字体取自 jsDelivr 的 `google/fonts`
- **iOS 测试路线**：本机跑 Android 模拟器；iOS 模拟器在 Mac Air（配置脚本 `tools/setup-macos-ios.sh`）。真机 UDID `00008130-001169D830A1401C`
- **Live2D 舞台几何**：平台视图的**布局尺寸按「族」固定**（`Live2DStage.kViewFamilies = [1.55, 1.70]`；2026-10-24 小族由 1.05 提到 1.55 = **超采样**（大厅 1.68×，已在 ~1.7× 饱和：再大只是 LOD 撞 mip0 烧显存），见 [`docs/46`](docs/46-Live2D清晰度-DPR与mipmap.md) §3.9/§3.10 —— 别再改回 1.05，那是「软」的根因），缩放/平移交给 `Transform.scale(cam.s / 族尺寸)` —— 逐帧改布局尺寸会让插件 iOS 侧 `layoutSubviews()` 每帧重建 FBO。换景走 `CamSpring.glideTo(..., ms: 1400)` 的 easeInOutCubic 慢推。**`Opacity` 禁套平台视图**（saveLayer），`Transform` 可以。细节：`app/STAGE-OPTIONS.md` 坑 4、`docs/18` §1.5.3
- **原生 Live2D shader 打包（2026-10-12 定案，勿删）**：产品路线是**原生**（WebView 降级路线已删除）。`app/android/app/build.gradle.kts` 里的 `syncLive2dShaders` 任务把 `flutter_live2d` 自带的 `Shaders/StandardES/*` 同步进 APK 的 `assets/FrameworkShaders/` —— **插件自己不打包这些文件，漏了就不上屏，且每帧刷 `GL error 0x501`**。排查全文 `docs/35-MuMu原生Live2D排查.md`
- **输入态（`#ask` / 换目标）布局纪律**：主 Scaffold 必须 `resizeToAvoidBottomInset: false`，输入框自己用 `AskField.bottomInset: MediaQuery.viewInsetsOf(context).bottom` 抬到键盘之上；「换目标」时主线全景整层退场、字幕让到屏幕中段，输入框/预设词不许和 CTA 或字幕重叠

---

## 已锁定的设计决策

- 主题色（已锁定，勿再改）：深蓝虚空 `#0A0E1A` + 电光青 `#38E1FF`（主强调）+ 稀有度色谱（F灰 `#9AA3B2` / E绿 `#4ADE80` / D蓝 `#38BDF8` / C紫 `#A78BFA` / B金 `#FBBF24` / A橙 `#FB923C` / S红 `#FF4D5E`）
- 字体：Rajdhani（标题/大数字）+ Noto Sans SC（中文正文）+ JetBrains Mono（等宽数值/系统日志）；禁止 Inter/衬线；数字禁止用正文字体
- 字体已落位 `app/assets/fonts/` 并在 `pubspec.yaml` 声明：Rajdhani 四档静态字重（400/500/600/700）；NotoSansSC 与 JetBrainsMono 是**可变字重字体**，粗体要在代码里写 `fontVariations: [FontVariation('wght', 700)]`，别只靠 `fontWeight`
- 视觉基准唯一来源：`.stitch/DESIGN.md`（GAME HUD EDITION v2）——玻璃面板、辉光、斜切角、网格+扫描线
- 产品机制唯一来源：`docs/` 下 `00~17` 编号规则文档（自然语言，一次定一事的工作方式，修改规则先改文档）
- **动作区用词固定**：【快照记录】【提交任务】【认输】（顶部面板与执行面板同款，勿再用旧黑话）

---

## 规则文档索引

| 文件 | 内容 |
|---|---|
| `00-核心规则.txt` | 宿主/系统关系、核心循环、任务只由系统发布 |
| `01-任务规则.txt` | 四种任务、F~S 难度、日上限 6、等级越高任务越多 |
| `02-面板与奖励规则.txt` | 单字六维（**力/敏/体/智/知/魅**）、三种奖励、无血条 |
| `03-惩罚规则.txt` | 毒舌即惩罚、连击/称号/评价、永远有补救 |
| `04-验证规则.txt` | 截图统一验证（可多张+文本备注），信任不查岗 |
| `05-新手开局规则.txt` | 【v3 激活流】六幕绑定仪式、开局三件套已删除、前 10 任务必胜 |
| `06-目标拆解规则.txt` | 一句话目标 → 5~8 环主线链、长期/短期轨道分离 |
| `07-文案规则.txt` | 毒舌但靠谱人格、四种固定语气（发布/结算/毒舌/追问） |
| `08-核心动效规则.txt` | 六大时刻逐帧编排 |
| `09-动效场景全集.txt` | 19 场景 S/A/B 分级 + ComfyUI 素材分工 |
| `10-无处不在游戏化清单.txt` | 四层包裹（常驻/微交互/环境/声音）+ 主题色锁定 |
| `11-精力系统规则.txt` | 【已冻结 · v3】精力随执行流删除，仅存档 |
| `12-毒舌升级规则.txt` | 连败计数三档毒舌（引用真实数据）、金牌豁免嘴不豁免记录 |
| `13-LLM拆解接入方案.txt` | 本地代理 /api/plan、OpenAI 兼容、客户端钳制、关键词模板兜底 |
| `14-系统形象与表演规则.txt` | 系统拟人化（全息系统体·冷感少女）、12 个表演预算 |
| `15-今日场景与手感规则.txt` | 今日页=全息委托板、三动词（拔单/撕单/轻点）、主线卷轴、金币拾取 |
| `16-执行与时间轴规则.txt` | 专注执行流：AI 访谈立主线、周期计划、唯一执行中、证据时间轴、认输 |
| `17-主线时间轴与执行轴规则.txt` | 主线=左右交错时间轴、状态零文字纯样式、节点点击=顶部面板三态 |
| `24-待机与动作表情绑定清单.md` | 待机动作 + 各指令的动作/表情绑定 |
| `25-表情动作预设总表.md` | **预设 = 动作 × 表情**：预设 47 条、动作组 18、表情 32 的总表 |
| `39-首页与主线UIUX真机走查与组件修改方案.md` | 真机走查出的 4 组结构性缺陷与 P0/P1/P2 三批施工方案 |
| `40-卡牌视觉系统重设计.md` | 卡牌从玻璃组件重做成「系统铸造的委托契据」 |
| `41-卡牌手感与音效设计.md` | 卡牌手感三拍、音效组、触觉波形 |
| `45-安卓模拟器Agent操作方案.md` | **模拟器 Agent 操作方案**（mumu-control / MCP 评估 / 落地步骤） |
| `46-Live2D清晰度-DPR与mipmap.md` | **清晰度四维量测法**；MuMu 面板 1170×2532@480（DPR3，中频 +110%）；**iOS 定案 = 超采样 1.68×**（族 1.55）+ 贴图预锐化（中频 +64~69%、无锯齿，§3.10）；`关 mipmap`（锯齿）与 shader LOD bias（模型不渲染）都已实测证否 |
| `47-Live2D清晰度修复全过程.md` | **同类问题的过程复盘**：五个阶段（MuMu 提 DPR → 关 mipmap 被证否 → 贴图密度量死 → 查开源定超采样 → 拉满+预锐化）、量测五条纪律、踩过的坑与死路、下一步清单。遇到「糊/锯齿」先看这篇 |

---

## 动效参数（样机 = 真机的唯一标准）

动效真源：`prototype/motion-demo/index.html`（纯 CSS/JS 手写，已在浏览器实测）。Flutter 移植时逐时刻对照此文件，参数不许凭感觉改：

- 弹簧：stiffness 100 / damping 20；过冲到 1.08 再回弹
- 亮帧：全屏白 16% 透明度脉冲 180ms，音效踩这一帧
- EXP count-up：800ms ease-out cubic；暴击：定格 200ms → CRIT 印章 scale 2.2→1 → 续滚双倍
- 经验条上涨：不跨级＝520ms ease-out；跨级＝涨满 360ms → 白闪 + 升级动效 → 归零 → 再涨到余额 420ms
- 结算总时长 ≤1.6s；升级 ≤2s（同日重复只播简版）；发布 ≤800ms
- 失败：更短更暗更安静（成功亮度 1/3）；打字机节奏 **标准 34ms/字**（唯一真源 `AgentSettings.kPaceStandardMs`）
- 8-bit 音效走**离线烘焙音效包**（`tools/audio/` → `app/assets/audio/`，84 件）：播放总线在 `app/lib/state/sfx.dart`（池化、永不抛、开关真正生效）
- **动效令牌**：`app/lib/design/tokens.dart` 的 `Motion` 类（Touch 0/120 · Respond 140 · Scene 320/520 · Payoff 600/280/780 · heartMs 2400 · 弹簧 120/ζ.9 与 70/ζ.95 · 过冲 ≤1.08 · 退场 60%）—— 组件里不许再写裸时长

---

## Stitch 生成管线（屏幕设计稿）

- 官方 CLI：`@google/stitch`（npm，Google LLC 出品）。npmmirror 不同步新包，安装需 `--registry=https://registry.npmjs.org`
- 认证：`STITCH_API_KEY` 环境变量（key 在 `prototype/stitch-bridge/.env`，已 gitignore，勿提交勿外传）
- 项目 ID：`9824844031085818014`（https://stitch.withgoogle.com/projects/9824844031085818014）
- 设计系统 ID：v1=`5203883926288910671`（弃），v2 GAME HUD=`119134925411475183`
- 生成：`npx stitch generate screen --project <id> --device MOBILE --title <t> --prompt (Get-Content prompts\Sx.txt -Raw) --json`
- **已知坑：连续生成同类提示词会串台**——必须用 "SCREEN CONTENT LOCK" 式提示词，生成后用 `stitch get screen` 核对 title
- 本地预览：`npx stitch serve -p <id> --port 8788`
- v2 屏幕清单与正确 screen ID 见 `prototype/README.md`

---

## ComfyUI 素材管线

- 端点 `127.0.0.1:8188`（本机 ComfyUI-aki-v2 在线，RTX 5090 32G）；素材需求清单见 `09-动效场景全集.txt` 底部
- **工作流在 `tools/comfyui/`**：Qwen-Image 2.1 文生图 + 2x-AnimeSharpV4 放大——`qwen21-game-bg.workflow.json` 可直接拖进 GUI，`gen_game_bg.mjs` 一键重生成（`--seed` 抽卡），参数与坑见该目录 README
- 首件产出：`prototype/opus-v2-dir/img/bg-void.jpg`（垫在 `#bg .sky` 底层）
- 生图：辉光 burst、稀有度框、粒子 sprite、印章纹章、glitch 帧
- 生视频（img2vid）：结算光线 loop、升级光环、扫描线氛围、glitch 转场
- 优先级：纯 CSS/canvas（Flutter 端 CustomPainter）先行，AI 素材只做质感替换

---

## 品牌标识

- LOGO＝「六边核心 + 经验弧」，唯一真源 `brand/build.mjs`（一条命令重生成全部 SVG 母版 + Android/iOS 图标 + 原型 favicon + 规格卡，产物入库）
- **禁手改任何生成的 SVG/PNG**，要改就改参数重跑并同步 `docs/23`；细节与落点见 `brand/README.md`

---

## 工作约定

- 先文档后代码；规则改动先改编号 txt，代码跟随文档
- 每次只推进一件事，不超过 500 字的决策粒度
- **【宿主指定】不要参考、也不要在 `prototype/` 下的 HTML 原型上做验证或改动**：原型早已过时，只作历史参考；实现与验证都落在 Flutter 工程 `app/`。旧约定「动效/视觉改动必须先在样机验证手感，再移植 Flutter」**作废**
- **【宿主指定 · 2026-10-11】非必要不要自己测试，宿主就在屏幕前，他就是测试员**：
  - 改完直接交给宿主看，**不要**为了"验证"去跑模拟器 / 真机截图 / 连拍量像素 / 写临时探针 / 反复 build-install 那一套
  - 允许保留的只有**代码级**检查：`flutter analyze` + 与改动直接相关的 `flutter test`（秒级）。**不要**主动扩测
  - 宿主明确说"你去验/你测一下"时才走真机验证流程
  - 需要宿主确认的验收点，**一次列清楚**（要做什么、看哪里、预期什么），别来回问
- **【宿主指定 · 2026-10-23】只要这一轮改动了 `app/`，会话最后必须构建并安装到 MuMu，交付"能跑的新包"**：
  - **不是**只跑 `flutter analyze` / `flutter test` 就算完 —— 那是代码级检查，宿主看不到
  - 标准收尾三步（缺一不可）：
    ```bash
    cd app && flutter build apk --debug
    adb -s 127.0.0.1:16512 install -r build/app/outputs/flutter-apk/app-debug.apk
    adb -s 127.0.0.1:16512 shell am force-stop com.systempanel.app \
      && adb -s 127.0.0.1:16512 shell am start -n com.systempanel.app/.MainActivity
    ```
  - **验收标准**：截图确认新界面真的上来了（改了什么就看什么），再交给宿主
  - ⚠️ 若这次改动涉及**已落到存档里的数据**（任务清单、目标文本等），要主动说明
    "旧存档不会自动重生"，并给出重生路径（换目标 / 重置存档）
  - 宿主明确说"不要装了/我自己来"时才跳过
- **【宿主指定 · 2026-10-11】iOS 真机**（按需，不与上条冲突）：
  - 真机 UDID：`00008130-001169D830A1401C`（iPhone 15 Pro Max）；`cd app && flutter run -d 00008130-001169D830A1401C`
  - iOS 14+ 的 debug 包**不能从桌面图标启动**，必须由 Flutter 工具链拉起
  - 真机常走无线调试：掉线/unavailable 是常态，先 `xcrun devicectl list devices` 确认 connected 再跑
- **⚠️ 大文件写入纪律**：`app/lib/main.dart`、`app/lib/widgets/main_view.dart`（1700+ 行）**只许 `edit` 靶向替换，永不整体 `write`**——本仓库发生过一次整体 write 导致文件被截断、由 Lead 重建的事故
- `.env`、`results/`、`node_modules/` 永不入库
