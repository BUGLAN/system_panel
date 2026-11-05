# AGENTS.md — 宿主 SYSTEM 项目指南

> 本文件供 AI Agent 阅读：任何 Agent 在本项目工作前必读。产品是「网文系统流自我提升 App」——用户是宿主，App 是毒舌但靠谱的系统。
> 最后更新：2026-11-05（清理 `docs/` 只留 45 与 50；按当前代码核对并改掉过时内容：Live2D 已移除、`app/lib` 结构、v3 视觉令牌、双机环境）

---

## 仓库与运行（先看这里）

- **仓库根目录 = 本文件所在目录**（git 仓库，主分支 master）。两台开发机：Windows（`E:\repo\system_panel`，跑 MuMu）与 Mac（`/Users/lansheng/repo/system_panel`，跑 iOS 模拟器/真机）。Flutter 工程在 `app/`；`docs/` 只留两篇（见下方「文档」）。
- **Flutter 工程在 `app/`**：applicationId 与 iOS bundle id 均为 `com.systempanel.app`。
  ```bash
  cd app && flutter run          # Android（Windows 机上的 MuMu 模拟器）
  cd app && flutter run -d 93FBEE17-17E2-4515-B66D-4DA3AD365C19   # Mac：iOS 27 模拟器
  cd app && flutter run -d 00008130-001169D830A1401C   # 真机 iPhone 15 Pro Max
  cd app && flutter analyze && flutter test
  ```
- **原型（历史参考，勿改动）**：`prototype/opus-v2-dir` 是宿主最终选定的那一版全息舞台原型，跑 `cd prototype/opus-v2-dir && node server.mjs` → http://localhost:4925。**它是历史参考，不是实现真源**——实现与验证一律落在 `app/`。
- **原型归档**：`prototype/` 下只留中选的 `opus-v2-dir` 与跨原型真源/证据（`.stitch`、`motion-demo`、`references`、`screens`、`stitch-bridge`）。另外 7 版历史原型在 Windows 机的 `E:\repo\archive\`（不在本仓库内），索引见该目录 `README.md`。
- **动效样机**：`prototype/motion-demo/index.html`，静态服务挂 4920 端口即可。
- 未入库：`.env`（含 Stitch API Key）、`node_modules/`、`prototype/stitch-bridge/results/`

### 当前 `app/lib` 结构

| 目录 | 职责 |
|---|---|
| `main.dart` | 应用入口 + 主壳（3600+ 行）：状态机 `Moment`（boot / lobby / onboard / dispatch / exec / result / fail / sheet / main）、场景切换、拆解任务 `_planJob`、结算与认输编排 |
| `ui/ref/` | **v3 界面（当前在用）**，按参考稿 `宿主养成系统_重设计.html`（仓库根目录）逐页实现：`ref_home`（大厅）、`ref_onboard`（绑定仪式/访谈）、`ref_main`（主线）、`ref_board`（委托板）、`ref_exec`（执行面板）、`ref_verdict`（结算）、`ref_archive`（档案）、`ref_shop`（补给）、`ref_sheet`（系统设置抽屉）、`ref_goal_swap`（换目标）、`ref_loading`（拆解加载卡）、`ref_llm_settings`、`ref_hud`、`ref_tcard`（任务卡）、`ref_kit`/`ref_inputs`（RefButton/RefXButton/RefTextField 等基础件）等 |
| `widgets/` | 18 个共享组件：`card_skins`/`card_table`（卡牌）、`ask_field`、`bg_layer`、`fx_layer`/`fx_particles`、`fail_layer`、`hud`、`line_layer`（台词）、`chat_bar`、`type_text`、`voice_bars`、`rail_base` 等 |
| `agent/` | LLM 接入层：`llm_client`、`llm_gateway`、`llm_telemetry`、`plan_agent`/`plan_brief`/`goal_match_agent`/`mainline_tool`（目标拆解）、`persona`、`copy`、`memory`、`context_adapter`、`tools`、`vision_core`（证据视觉校验）、`settings_store` |
| `state/` | 状态与数据：`quest_flow`（队列/接单/结算唯一真源）、`host_state`、`goal`、`goal_gen`、`quest`、`result`、`plan_failure`、`save_file`、`settings`、`sfx`、`haptics`、`voice`、`app_clock`、`away` |
| `design/` | `ref.dart` = **v3 表现层令牌唯一真源**（`Ref` 色板/字体/缓动，新界面只许读它）；`tokens.dart` = 旧令牌（`C`/`F`/`Motion`/`StageAnchors`/`Pal`，旧组件与历史测试还在用，逐步迁移）；`fidelity`（画质档）、`spring` |
| `data/` | 静态数据表：`rarity`、`attrs`、`items`、`titles`、`rewards`、`content`、`format` |
| `chat/` | 对话面板（`chat_panel`/`chat_service`/`chat_history`） |
| `screens/` | `boot_screen` |
| `dev/` | `agent_bridge`（仅 debug 启用，见下文） |

---

## Agent 操作安卓模拟器（MuMu）

> 完整方案：[`docs/45-安卓模拟器Agent操作方案.md`](docs/45-安卓模拟器Agent操作方案.md)（调研结论、MCP 评估、证据等级）。
> 可复用动作：[`.claude/skills/android-agent/SKILL.md`](.claude/skills/android-agent/SKILL.md)。

- **不要找 MCP**。MuMu 官方 `mumu-control` skill 已装并跑通（`C:/Users/buglan/.agents/skills/mumu-control`，9 文件，MIT，Windows only）。`mumu-cli.exe` 与 `MuMuManager.exe` 是同一二进制（实测同尺寸同时间戳）
- **为什么不用裸 adb**：旧方案 64 次工具调用里至少 40 次在跟「没有 UI 元素模型」搏斗——`uiautomator dump` 出 size:0、Git Bash 改写 `/sdcard` 路径、中文乱码、只能截图猜坐标。改用 skill 后同类任务 2 条命令
- **环境**：设备 `127.0.0.1:16512`（端口用 `"E:/MuMu Player 12/nx_main/MuMuManager.exe" info -v all` 查）｜包名 `com.systempanel.app`｜屏幕 **1170×2532 @480dpi = 390×844dp（DPR 3）**
  - **2026-10-23 起：逻辑尺寸不变（390×844dp），物理面板提到 1170×2532@480 ⇒ DPR 从 2 升到 3**（画面中频清晰度明显提升）
  - ⚠️ **不要再 `wm size`/`wm density` 覆盖**：覆盖会把 SurfaceFlinger 从「1:1」变成「缩放」，实测中频掉 45%。当前 `display_size_forced = null` 就是正确状态
  - MuMu 实例 API 写分辨率的**顺序陷阱**：`resolution_mode` 设成 `custom` 会把三个值清零，且普通键 `key not writable` —— 必须写 `.custom` 后缀键
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
- 状态管理：没有用 Riverpod，状态集中在 `main.dart` 主壳 + `state/quest_flow.dart`；也没有 flutter_animate，动效是手写 `AnimationController` + `design/spring.dart`。依赖以 `app/pubspec.yaml` 为准（现为 flutter_svg / shared_preferences / http / image_picker / path_provider / audioplayers / vibration）
- **Flutter 工具链**：两台机都是 Flutter `3.47.6` stable（Dart 3.13.5）。Windows：装在 `D:\flutter`（已入 PATH），JDK 用 Android Studio 自带 JBR，Android SDK 在 `%LOCALAPPDATA%\Android\Sdk`；Mac：`~/development/flutter`
- **全程国内源、不走代理（硬要求）**：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（已写入用户环境变量）；Gradle 走腾讯云镜像（`app/android/gradle/wrapper/gradle-wrapper.properties`），AGP/Kotlin 走阿里云镜像（`app/android/settings.gradle.kts`、`app/android/build.gradle.kts`）；字体取自 jsDelivr 的 `google/fonts`
- **测试路线**：Windows 机跑 Android 模拟器（MuMu）；Mac 跑 iOS 模拟器与真机（配置脚本 `tools/setup-macos-ios.sh`）。真机 UDID `00008130-001169D830A1401C`
- **iOS 模拟器要用 iOS 27 运行时（2026-10-28 实测）**：本机 Xcode 27 的触摸/按键注入**不支持 iOS 17.5 运行时**——旧的「iPhone 15 Pro Max（iOS 17.5）」上点击、HOME 键都会被静默丢弃（工具还报成功）。用 `iPhone 15 Pro Max (iOS 27)`（UDID `93FBEE17-17E2-4515-B66D-4DA3AD365C19`，与真机同为 430×932pt）；刚开机要等 ~10s 输入通道才就绪
- **iOS 帧率上限 60Hz（2026-10-28 定案）**：`ios/Runner/Info.plist` 的 `CADisableMinimumFrameDurationOnPhone` 为 `false`。常驻循环动画多，开 120Hz 时任何一个 Ticker 都会让引擎每秒合成 120 帧整屏 —— 15 Pro Max 上的卡顿与发热主因之一。别改回 `true`
- **Live2D 已移除（2026-10-27，commit `6f10de1`）**：`flutter_live2d` 依赖、舞台组件、`syncLive2dShaders` 任务、`app/STAGE-OPTIONS.md` 都已删掉，大厅中心现在是眼睛徽标。旧的 Live2D 定案（族尺寸 1.55 超采样、shader 打包等）全部作废；要重新接入先和宿主确认
- **输入态（`#ask` / 换目标）布局纪律**：主 Scaffold 必须 `resizeToAvoidBottomInset: false`，输入框自己用 `AskField.bottomInset: MediaQuery.viewInsetsOf(context).bottom` 抬到键盘之上；「换目标」时主线全景整层退场、字幕让到屏幕中段，输入框/预设词不许和 CTA 或字幕重叠

---

## 已锁定的设计决策

- **视觉基准（2026-11-05 宿主定案：以当前 v3 为准，勿再改回旧版）**：参考稿 `宿主养成系统_重设计.html`（仓库根目录）→ `app/lib/design/ref.dart` 的 `Ref`：底 `#06050C`、主强调 acid `#D6FF3D`（荧光黄绿）、cyan `#3BE8FF`、hot `#FF3B7A`、violet `#8F6BFF`、gold `#FFCC4D`、mint `#3DFFA8`；稀有度色谱 `Ref.rank`
- **字体（已锁定，以 `app/pubspec.yaml` 为准）**：显示/数字 `ChakraPetch`（`Ref.fd`）、中文正文 `NotoSansSC`（`Ref.fc`）、等宽 `JetBrainsMono`（`Ref.fm`），另有 FangYuan / ShuHei / Tektur / KodeMono。NotoSansSC 与 JetBrainsMono 是**可变字重字体**，粗体要写 `fontVariations: [FontVariation('wght', 700)]`，别只靠 `fontWeight`（`refText(wght: …)` 已封装）
- 产品机制以 `app/` 当前代码为准（00~17 编号规则文档不在仓库里，别找）；尚未定案的规则问题记在 `docs/50` 的 C 类
- **动作区用词固定**：【快照记录】【提交任务】【认输】（顶部面板与执行面板同款，勿再用旧黑话）

---

## 文档

`docs/` 只保留两篇，18~49 号历次方案、复盘与提示词文档已于 2026-11-05 删除（需要时从 git 历史找回，**不要据此推断现状**）。旧版本文件引用过的 00~17 编号规则 txt 在本仓库里并不存在：

| 文件 | 内容 |
|---|---|
| `45-安卓模拟器Agent操作方案.md` | **模拟器 Agent 操作方案**（mumu-control / MCP 评估 / 落地步骤），`.claude/skills/android-agent` 引用它 |
| `50-新用户走查问题清单.md` | 2026-11-05 iOS 模拟器新用户走查问题单：A 简单（已修，A23 待复现）/ B 需新 UI / C 困难或需拍板，带修复状态 |

---

## 动效参数（样机 = 真机的唯一标准）

动效真源：`prototype/motion-demo/index.html`（纯 CSS/JS 手写，已在浏览器实测）。Flutter 移植时逐时刻对照此文件，参数不许凭感觉改：

- 弹簧：stiffness 100 / damping 20；过冲到 1.08 再回弹
- 亮帧：全屏白 16% 透明度脉冲 180ms，音效踩这一帧
- EXP count-up：800ms ease-out cubic；暴击：定格 200ms → CRIT 印章 scale 2.2→1 → 续滚双倍
- 经验条上涨：不跨级＝520ms ease-out；跨级＝涨满 360ms → 白闪 + 升级动效 → 归零 → 再涨到余额 420ms
- 结算总时长 ≤1.6s；升级 ≤2s（同日重复只播简版）；发布 ≤800ms
- 失败：更短更暗更安静（成功亮度 1/3）；打字机节奏 **标准 34ms/字**（唯一真源 `AgentSettings.kPaceStandardMs`）
- 8-bit 音效走**离线烘焙音效包**（`tools/audio/` → `app/assets/audio/`，现 135 个 wav）：播放总线在 `app/lib/state/sfx.dart`（池化、永不抛、开关真正生效）
- **按下声由基础组件负责**：`RefButton` / `RefXButton` / `RefSwitch` / tabs / `RefLink` 自带按下声，走 `refPressSound(cue)` → `Sfx.cue`（`SoundRule.cues` 规则表：音量分档 + 防连发）；业务回调只出**结果声**（成功/失败/购买），不要再在调用点补一声 tap
- **等 LLM 的地方必须有加载态**：用 `RefPlanLoading`（分步进度跟着 `_planStageTo` 走），主壳的 `_planJob` 同时是防连点闸门
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

- 端点 `127.0.0.1:8188`（本机 ComfyUI-aki-v2 在线，RTX 5090 32G）
- **工作流在 `tools/comfyui/`**：Qwen-Image 2.1 文生图 + 2x-AnimeSharpV4 放大——`qwen21-game-bg.workflow.json` 可直接拖进 GUI，`gen_game_bg.mjs` 一键重生成（`--seed` 抽卡），参数与坑见该目录 README
- 首件产出：`prototype/opus-v2-dir/img/bg-void.jpg`（垫在 `#bg .sky` 底层）
- 生图：辉光 burst、稀有度框、粒子 sprite、印章纹章、glitch 帧
- 生视频（img2vid）：结算光线 loop、升级光环、扫描线氛围、glitch 转场
- 优先级：纯 CSS/canvas（Flutter 端 CustomPainter）先行，AI 素材只做质感替换

---

## 品牌标识

- LOGO＝「六边核心 + 经验弧」，唯一真源 `brand/build.mjs`（一条命令重生成全部 SVG 母版 + Android/iOS 图标 + 原型 favicon + 规格卡，产物入库）
- **禁手改任何生成的 SVG/PNG**，要改就改参数重跑；细节与落点见 `brand/README.md`

---

## 工作约定

- 规则改动先和宿主确认再动代码；发现的问题与修复状态记进 `docs/50-新用户走查问题清单.md`（或新开一篇同类清单），不要再堆方案长文
- 每次只推进一件事，不超过 500 字的决策粒度
- **【宿主定案 · 2026-11-05】连胜规则**：认输不断连胜；只有一整天一单都没完成才断（docs/50 C6）
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
  - **在 Mac 上（没有 MuMu）**：改为装到 iOS 27 模拟器，同样截图确认：
    ```bash
    cd app && flutter build ios --simulator --debug
    xcrun simctl install 93FBEE17-17E2-4515-B66D-4DA3AD365C19 build/ios/iphonesimulator/Runner.app
    xcrun simctl launch 93FBEE17-17E2-4515-B66D-4DA3AD365C19 com.systempanel.app
    ```
  - 宿主明确说"不要装了/我自己来"时才跳过
- **【宿主指定 · 2026-10-11】iOS 真机**（按需，不与上条冲突）：
  - 真机 UDID：`00008130-001169D830A1401C`（iPhone 15 Pro Max）；`cd app && flutter run -d 00008130-001169D830A1401C`
  - iOS 14+ 的 debug 包**不能从桌面图标启动**，必须由 Flutter 工具链拉起
  - 真机常走无线调试：掉线/unavailable 是常态，先 `xcrun devicectl list devices` 确认 connected 再跑
- **⚠️ 大文件写入纪律**：`app/lib/main.dart`（3600+ 行）**只许 `edit` 靶向替换，永不整体 `write`**——本仓库发生过一次整体 write 导致文件被截断、由 Lead 重建的事故
- `.env`、`results/`、`node_modules/` 永不入库
