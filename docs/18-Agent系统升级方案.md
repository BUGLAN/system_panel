# 18 · Agent 系统升级方案

> 状态：**施工真源**（下游实现任务按本文档施工）。
> 范围：`app/`（Flutter 客户端）升级为 Agent 驱动系统；平台目标 **Windows + MuMu 模拟器（Android）**，iOS 相关内容**忽略**（`HANDOFF-LIVE2D-IOS.md` 只取其中与 Android/MuMu 共享的事实）。
> 编写纪律：先文档后代码（AGENTS.md 工作约定）；本文档只写 `docs/`，不改 `app/` 代码。

## 0 · 真源声明（必读）

1. **`docs/00~17` 编号规则文档在当前工作树上不存在**：`docs/` 目录为空、`git ls-files docs` 无记录（从未入库）。AGENTS.md 中的《规则文档索引》表是它们仅存的**摘要**。因此：
   - 凡本文档引用「docs/07 四种语气」等处，**以 AGENTS.md 摘要 + 原型代码（`prototype/opus-v2-dir/js/*`）为真源**；
   - 00~17 的缺失不阻塞本升级；若日后找回原件，冲突处以原件为准并回改本文档。
2. 视觉/动效真源仍是 `prototype/opus-v2-dir`（原型即规格）；行为真源是 `prototype/opus-v2-dir/js/store.js`、`flows.js`、`ui.js`、`stage.js`。
3. 平台事实真源：`HANDOFF-LIVE2D-IOS.md`、`app/STAGE-OPTIONS.md`、`app/BEHAVIOR-GAPS.md`、`app/COVERAGE.md`。
4. **环境基线真源：`.verify/agent-upgrade/ENV.md`**（队长实测钉死）：MuMu=`127.0.0.1:16512`（Android 12），已校准 780x1688@320；`flutter analyze`=No issues found!、`flutter test`=**246/246 绿**（改动前基线，任何任务 verify 变红都是自己引入的）；**Live2D 数据自 `41576dd` 起已随仓库分发**（取消 gitignore，换机 clone 即得，无需搬运）；master @ `41576dd`。
5. 验证纪律（项目惯例，见 HANDOFF）：`flutter analyze` 必须 "No issues found!"、`flutter test` 全绿才准提交；提交只 `git add app`（+明确指定的 tools 路径），宿主自己的改动（`.gitignore`、`AGENTS.md`、`prototype/opus-v2-dir/css/app.css`、`dev-dashboard/`、`prototype/opus-v2-dir/img/`、`tools/comfyui/`）**永不提交**。

---

## 一 · 现状审计

### 1.1 工程结构盘点

```
app/
├── lib/
│   ├── main.dart            # AppShell：单壳多时刻（Moment 枚举 9 态），1089 行，所有页面的装配点
│   ├── data/                # 纯数据表（无行为）
│   │   ├── rarity.dart      #   F~S 稀有度：颜色/exp/coin/pt/min（exp、coin 将被 2.3 的 Rewards 取代）
│   │   ├── items.dart       #   ITEMS 表：dbl60 / crit45 / shield90 / swap30（沿用，不改）
│   │   ├── attrs.dart  content.dart  format.dart  titles.dart
│   ├── state/               # 状态与存档
│   │   ├── host_state.dart  #   宿主档案（demo/empty 两档 + fromJson 合并迁移）
│   │   ├── goal.dart        #   主线链 Goal/GoalRing（demo 8 环）
│   │   ├── save_file.dart   #   SharedPreferences 存档（key=opus-v2/save/v1，合并式迁移+冻结语义）
│   │   ├── quest.dart       #   Quest 数据模型 + Quest.demo（静态常量！）
│   │   ├── result.dart      #   QuestResult 数据模型 + demo（静态常量！）
│   │   ├── app_clock.dart / away.dart / voice.dart / settings.dart（AppSettings 仅数据，未持久化）
│   ├── stage/               # 舞台
│   │   ├── live2d_web.dart  #   路线②：本机 HTTP 服务 + WebView 跑原型播放器（main.dart 当前在用）
│   │   ├── live2d_stage.dart#   路线①：flutter_live2d 原生（**已存在、未被 main.dart 引用**）
│   │   ├── camera.dart      #   Cam/CamSpring/RingGeom + StageAnchors（实测锚点 hair .4386 / feet −1.5114）
│   │   ├── ring_painter.dart / spring.dart
│   ├── widgets/             # 27 个组件（plate 1235 行 / sheet 1031 行最大）
│   ├── screens/boot_screen.dart
│   └── design/tokens.dart
├── test/                    # 24 个测试文件（quest/result/save/onboard/…）
├── android/build.gradle.kts # 含 CMake 3.22.1 反射覆盖块（L33-45，见 1.5.2）
├── pubspec.yaml             # flutter_live2d ^1.0.2 / webview_flutter ^4.14.1 / shared_preferences / flutter_svg
└── assets/live2d/           # sakiko(64 motions/28 expressions) + hiyori + vendor + sakiko_orig
                             #   ⚠️ 自 41576dd 起已随仓库分发（不再 gitignore）——下游无需跨机搬运
```

关键结论：

- **UI 层完成度高**：原型 103 个 id 已移植 95、缺失 0（COVERAGE.md）；除"她本人"与证据拍照外界面元素一个不落。
- **行为层是壳**：`main.dart:107-114` 用 `HostState.demo` / `static const Quest _quest = Quest.demo` / `static const QuestResult _result = QuestResult.demo` 三份**静态演示数据**撑起全部流程——接单不扣队列、结算不改档案、不生成新单。BEHAVIOR-GAPS.md 的 A2/A3（每秒 tick 业务、换日）未做，C 组对白只剩插话调度。
- **没有网络层、没有 LLM、没有相机**：pubspec 无 http/image_picker；`AppSettings` 未持久化；`data/content.dart` 的 LINES 是纯文案表。
- 存档已有**合并式迁移**机制（`HostState.fromJson`/`Goal.fromJson` 在 fallback 上合并，`save_file.dart:122-144`），新增字段天然兼容老档——2.8 的迁移方案沿此惯例。

### 1.2 「提交任务卡死」根因定位

**症状**：执行页点【提交 · 让她验收】后进入结算页，此后界面**永远停在结算页**，任何操作都无法离开（唯一按钮无响应）。

**根因链（全部已在代码中核实）**：

| # | 位置 | 事实 |
|---|---|---|
| ① | `app/lib/main.dart:575-593`（ExecPanel `onSubmit`） | 提交只做了 `_clock.stopFast()` + 特效 + `setState(() => _moment = Moment.result)`。**没有任何结算计算**：不加工经验/金币/六维、不推进主线环、不消耗队列、不存档 |
| ② | `app/lib/main.dart:108-109` | `_quest`/`_result` 是 `static const ... demo`——结算页展示的永远是同一份 C 级第 5 环演示数据，与实际执行无关 |
| ③ | `app/lib/main.dart:626`（ResultPanel `onSave: () {}`） | 结算页**唯一交互**「保存战报」回调为空（原型 `flows.js:440` 是 `shareCard(res, ...)`） |
| ④ | `main.dart:732-738` + `widgets/choices.dart:52` | `Choices` 组件本身支持 `onPick`，但 main.dart **没传**；且结算态根本没有 Choices——原型 `flows.js:462` 结算演出收尾必弹 `choose()`：【再来一单。/先歇会儿。】（队列空时【收工。】），选完 `ResultUI.hide()` → `dispatch()/lobby()`。Flutter 侧把这条**唯一退出路径**丢了 |
| ⑤ | `main.dart:254-287`（`_onSecond`） | 每秒时钟在 result 态只处理插话收尾，无任何超时/自动返回逻辑 |

**同型病灶（一并修）**：失败态也是死局——`main.dart:981` `_beginFail()` 置 `Moment.fail` 后，`Choices(items: ['……接。','今天算了。'], visible: fail)` 同样没传 `onPick`（原型语义 `flows.js:609`：接 → `takeRemedy(true)` 派补救单；算了 → 回大厅）。

**修复思路**（落实到 2.2/三 的任务 T2）：

1. 新建 `lib/state/quest_flow.dart`，移植 `store.js` 的队列/接单/结算/认输/补救核心（`bind/newGoal/rollDay/head/accept/useItem/critChance/settle/fail/takeRemedy/buy/equip/checkTitles/reasonFor`，见 `prototype/opus-v2-dir/js/store.js:9-425`），成为**唯一业务真源**；
2. `onSubmit` → `QuestFlow.settle()` 产出真实 `QuestResult`（含 `ups` 升级、`ringClear`、`titles`、`empty`），应用到 `_host`/`_goal` 后 `_persist()`；
3. `ResultPanel` 增加演出收尾回调 `onDone`（timeline 播完触发），main.dart 此时展示 Choices【再来一单。/先歇会儿。|收工。】，`onPick` → 清 result 态进 `Moment.dispatch`（取队首新单）或 `Moment.lobby`；
4. 失败态 Choices 接 `onPick`：接 → `takeRemedy(true)` 后进派单；算了 → 回大厅；
5. `保存战报` 最小可用版：把结算数据渲染成文本战报写入剪贴板/系统分享表（`Share` 语义；不引重依赖，先 `Clipboard.setData` + toast 式插话）。

### 1.3 死按钮 / 死交互清单（逐个）

以下 12 项全部在代码核实过（组件有无回调 + main.dart 有无传）。**「应补什么」列即下游施工要求**。

| # | 位置 | 控件 | 现状 | 应补的功能 |
|---|---|---|---|---|
| D1 | `main.dart:626` → `result_panel.dart:250-275` | 结算页「保存战报」 | `onSave: () {}` 空回调 | 生成战报（任务名/等级/EXP/金币/连击/一句话）→ 系统分享/剪贴板；失败时插话告知 |
| D2 | `main.dart:732-738` | 结算后退出选项 | 无此 UI | 演出完弹 Choices【再来一单。/先歇会儿。|收工。】→ dispatch / lobby（即 1.2 修复④） |
| D3 | `main.dart:732-738` | 失败页「……接。」「今天算了。」 | `onPick` 未传，点了没反应 | 接 → `takeRemedy(true)` 补救单入队并进派单；算了 → 回大厅（`flows.js:609`） |
| D4 | `main.dart:685-688` → `plate.dart:1162-1235` | 派单板下「换一个」「等会儿」 | `PlateAlt` **没有回调参数**，纯展示 | 换一个 → `QuestFlow.retreat`（降一档；F 级还退=换一张别的 F；当日累计 3 次强制佩戴「口头巨人」）；等会儿 → 单子留在队列、回大厅（`flows.js:307,315`、`store.js:235-250`） |
| D5 | `main.dart:781-790` → `main_view.dart:317-345` | 主线页「换目标」 | `onNewGoal` 存在但未传 | 唤起小祥对话（2.7）：以「换目标」为上下文开聊天层，走访谈流换新主线；旧主线环清空、队列中主线单移除（`store.js:170-176` newGoal 语义） |
| D6 | `sheet.dart:456-491` | 档案「称号 · 点一下挂上」 | `_titleChip` 无手势 | 点已解锁称号 → `equip(id)` 挂上（`mouth` 强制佩戴期间禁止，`store.js:385`） |
| D7 | `sheet.dart:680-705` | 补给页各行「◈ 价格」购买钮 | `_buy` 无手势（只有 afford 变灰逻辑） | 点 → `buy(id)`：金币够则扣币加道具并存档，不够插话嘲讽 |
| D8 | `sheet.dart:802-835` | 系统页 4 个分段开关（音效/她的声音/震动/全息描边） | `_seg` 无手势；`AppSettings` 未持久化 | 点段 → 切换 `AppSettings` 并持久化（新增 key，见 2.8）；新增「LLM / 视觉校验」设置组（2.4）也放这里 |
| D9 | `exec_panel.dart:284-381` | 执行页证据槽 3 格（含 + 号） | `evidenceCount` 固定 0，槽无手势 | 点 + → `image_picker` 拍照/选图 → 可选 LLM 视觉校验（2.4）→ 计入证据，暴击率联动（`store.js:271`：`min(.85, .06 + .06*n + streak*.01 + crit道具 .25)`） |
| D10 | `main.dart:390` | 天幕大字 | 硬编码 `'半马'` | 改绑 `_goal.short`（绑定/换目标后自动跟随） |
| D11 | `main.dart:660-662` | 失败页记录时间/补救单 | 硬编码 `'20:02'` + `Remedy.demo` | 绑真实认输时间与 `QuestFlow.fail()` 生成的补救单 |
| D12 | `main.dart:177-190` | 接单计时起点 | 演示档写死「已执行 7 分钟」 | 接单时记 `startAt`，计时由它推导（原型 `Store.accept`，`main.dart:164-166` 注释本来就是这个意图） |

另有两项「按钮活着但数据是死的」一并纳入 T2：大厅 HUD `queue` 读数恒为 demo 的 4（`main.dart:107`）；执行页暴击率写死 `.12`（`main.dart:567`）→ 改 `QuestFlow.critChance()`。

### 1.4 MuMu 模拟器接入要点

宿主指定 Windows + MuMu（替代原 `emulator-5554` AVD）。要点如下（端口规则来自 [MuMu 官方 ADB 文档](https://mumu.163.com/help/20240807/40912_1073151.html)）：

1. **adb connect 端口**：
   - **本机实测（钉死，见 ENV.md）：MuMu = `127.0.0.1:16512`**（Android 12）。命令：`adb connect 127.0.0.1:16512` → `adb devices`；`flutter run -d 127.0.0.1:16512`。adb 用 `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`（1.0.41/37.0.1）。
   - 通用规则（换实例/换机时用，来自 [MuMu 官方 ADB 文档](https://mumu.163.com/help/20240807/40912_1073151.html)）：MuMu 12 本体（多开器序号 0）=16384，多开每实例 +32（16416、16448…），端口被占则基数 +1；**以模拟器「右上角菜单 → 问题诊断」或多开器 ADB 图标显示为准**（动态端口，诊断信息优先）。旧 MuMu 5.0：首个 5555、+2 递增（仅识别用，本方案不针对）。
   - **adb 版本冲突**：MuMu 自带 adb（`%MuMu%\shell\adb.exe`）与 platform-tools 版本不同会互踢。统一用 SDK 的 adb；遇到 `offline`/反复掉线，`adb kill-server` 后重连。多设备时一律 `adb -s 127.0.0.1:16512 <cmd>`。
2. **wm size / density 惯例**（沿用 HANDOFF 既定基准，让 MuMu 呈现与原型参照一致的 390×844 @2x 逻辑屏；**ENV.md 已实测校准过**）：
   ```
   adb -s 127.0.0.1:16512 shell wm size 780x1688
   adb -s 127.0.0.1:16512 shell wm density 320
   ```
   - 截图 `adb exec-out screencap -p` 为 780×1688，**量测/比对前缩到 390×844**（既有惯例）。
   - MuMu 自身「设置中心 → 显示」选**手机版竖屏**；**`wm` 覆盖值在 MuMu 重启后会丢**——每次起 MuMu 先重跑上面两条再干活（可写进 `tools/ref/drive.ps1` 前置步骤）。
   - 回归比对沿用 `tools/ref/drive.ps1 -Only <pages>` → `python tools/ref/regress.py`（阈值 4%），设备目标统一 `-s 127.0.0.1:16512`。
3. **换机必查**：MuMu 与旧 AVD 是两套 GPU 栈（旧机是 `vendor.mesa.virtgpu` 虚拟 GPU，见 STAGE-OPTIONS）。**此前"flutter_live2d 能加载不上屏"的结论只在旧 AVD 上成立**——MuMu 上是否复现正是 1.5 要先验证的第一件事；不要把旧结论平移。
4. 包名 `com.systempanel.app`；清缓存命令（换模型数据后）依旧：`adb -s 127.0.0.1:16512 shell run-as com.systempanel.app rm -rf cache/flutter_live2d_models`。
5. **模型数据无需搬运**：`41576dd` 起已随仓库分发（sakiko/hiyori/vendor/sakiko_orig 全在 `app/assets/live2d/`，本机已核实 64 motions + 28 expressions 在位）——HANDOFF 里「换机要单独拷数据」的告诫已成为历史，clone 即得。

### 1.5 live2d_web（WebView 基线）→ live2d_stage（原生）切换方案

> ▸ **2026-10-12 收尾（后话）**：本节作为历史方案保留，但它要的"双实现 + `kNativeStage`
> 编译期开关"已经**结束**——宿主拍板把 WebView 这一整条路线删掉（`live2d_web.dart`、
> `WebStagePort`、`kNativeStage`、`pubspec` 里 `assets/stage/` 与 `assets/live2d/vendor/`、
> `sakiko_orig` 的打包声明全删；文件仍留在磁盘上作参照，`sakiko_orig` 还是转换器的输入）。
> 两条理由：① 下面这套"止损线"依据的归因**已被推翻**（真因是 shader 资产没打进 APK，
> 见 `app/STAGE-OPTIONS.md`「2026-10-12 复盘」、`docs/35`）；② 那条路线在 App 里
> **触摸是断的**（WebView 包在 `IgnorePointer` 里、`stage.js` 不转发指针），
> 宿主实测"点击和拖动没有动作"。现在的舞台只剩原生一条，加载失败就退回全息剪影。

背景事实（STAGE-OPTIONS 结案 + HANDOFF）：路线① 在旧 AVD 上「`loadModel=true`、渲染线程在跑、视图树里全屏可见，但屏幕上什么都没有」→ 搁置；路线② WebView 已上屏但代价大（多 225MB 沙箱进程、中位帧 89ms≈11FPS）。宿主指令：**在 MuMu 上重试①，替换②**。`live2d_stage.dart` 已存在且完整（5 次加载重试、28 表情名表、idle 组），main.dart 只在 `import`（L19）与挂载点（L434-466）引用 `Live2DWeb`。

#### 1.5.1 切换步骤（按序，每步有验证）

1. **编译关**：MuMu 上 `cd app && flutter run -d 127.0.0.1:16512`。若 `:flutter_live2d:configureCMakeDebug` 报 `CXX1300 CMake '3.10.2' was not found`，说明反射覆盖失效，按 1.5.2 处置；默认应直接过（插件与覆盖块都在，见 1.5.2 核实）。模型数据已随仓库分发，无需任何搬运步骤。
2. **挂载关（一两行切换，A/B 留开关）**：main.dart 把 `import 'stage/live2d_web.dart'` 换成 `stage/live2d_stage.dart`、`Live2DWeb(...)` 换成 `Live2DStage(...)`。**保留双实现**：加 `static const bool kNativeStage = true;`（编译期开关），false 时回 WebView——WebView 版保留作降级与验收参照（HANDOFF 明示）。
3. **上屏关**：MuMu 上 `adb exec-out screencap` 看她在不在。三层判据（按序）：
   - 屏幕上有她 → 继续 4；
   - 屏幕上没有 → `adb shell dumpsys activity top | grep -A2 Live2DTextureView`（视图在树里吗、尺寸对吗）→ 看 `[stage] loadModel 第 N 次 → true/false` 日志 → 若 `loadModel` 恒 false，先 `run-as` 清插件缓存重试。**若以上全正常仍不上屏，即旧 AVD 同款结论在 MuMu 复现**：按 STAGE-OPTIONS 纪律「证据够了不再投入」——**默认舞台退回 WebView（kNativeStage=false 收尾），把复现证据（截图+dumpsys+日志）记入 STAGE-OPTIONS 增补节**，不沉没成本。此为**硬止损线**，写进 T3 任务卡。
4. **层序关**：她必须在 天幕之后、环场/UI 之前（现 Stack 位置不动，`main.dart:434` 注释已验证）。验法：开大厅截图，字幕/环/HUD 应压在她之上（对照 `.verify/_stageback.png` 的判据）。
5. **性能关**：`adb shell dumpsys gfxinfo com.systempanel.app` 采样：对比 WebView 基线（中位 89ms）。原生达标线：中位帧 ≤ 24ms（≈40FPS+，模拟器口径），无 45%+ 掉帧。

#### 1.5.2 CMake 3.10.2 反射覆盖：现状核实

- **覆盖块仍在且仍在生效路径上**：`app/android/build.gradle.kts:33-45` 的 `subprojects { afterEvaluate { ... setVersion("3.22.1") } }` 反射块原样在位；`app/pubspec.yaml:12` 仍依赖 `flutter_live2d ^1.0.2`；块在 `evaluationDependsOn(":app")`（L47-49）**之前**——顺序约束满足（注释写明：放后面会报 "Cannot run Project.afterEvaluate when the project is already evaluated"）。
- **结论**：只要插件版本不动（1.0.2）且 AGP 不换大版本，覆盖**继续生效**，无需改动。MuMu 首跑若报 CXX1300 再按序降级处置：① 确认本机 SDK 有 `cmake;3.22.1`（`sdkmanager --list | grep cmake`）；② 反射目标值改成本机实际有的版本；③ 最后手段 `dependency_overrides` 本地补丁插件（不入库，需在 STAGE-OPTIONS 记录）。

#### 1.5.3 相机：固定尺寸族 + Transform 慢推 + alpha 包围盒标定（勿用截图轮廓量测）

> **▸ v2 修订（2026-10-11 真机验收「换目标 UI 重合 / 小 live2d 到正常大小是硬切」）**
> 本节原来写的是「用布局矩形逐帧复刻相机」，理由是"平台视图外不能套 Transform"。**这两条都被推翻了**：
> - `Transform` 在 `UiKitView` 上是**支持**的（Flutter 文档：`_DarwinView` "support for transforms, clips, and opacity"），真机实测她按中间尺寸正常渲染；只有 `Opacity` 不行（saveLayer，STAGE-OPTIONS 坑 3/4）。
> - 逐帧改**布局尺寸**会让插件 iOS 侧 `layoutSubviews()` 每帧 `recreateFramebufferOnMainThread()` + `onSurfaceChanged()`（重建 FBO、排空渲染队列）→ 推镜头那段她基本不渲染 → 落点像"直接切过去"。
>
> **现行做法**：矩形只按**族**定尺寸（`Live2DStage.kViewFamilies = [1.05, 1.70]`，族内所有 cam 共用同一块布局矩形 → 不触发 FBO 重建），族内缩放/平移交给 `Transform.scale(cam.s / 族尺寸)`（几何上与"把矩形改成 cam.s 那么大"完全等价，测试 `stage_port_test.dart` 有等价性断言）；换景别再走 `CamSpring.glideTo(..., ms: 1400)` 的 **easeInOutCubic 慢推**（弹簧约 0.5s 到位，配上亮帧/界面淡入就是"硬切"观感）。真机证据：相机逐帧轨迹连续（0.92↔0.68，每段 13~14 个采样、单调不过冲），连拍帧里头顶位置出现两端之间的中间值。

- **插件没有相机矩阵 API**（live2d_stage.dart 注释 L19-21 明示），所以相机的缩放/平移只能靠"布局矩形 + `Transform`"两条腿走路（见上面的 v2 修订）。
- **方案**：`Live2DStage` 从 `Cam`（camera.dart）算出她的**逻辑**矩形 `stageRect`（中心 `Cam.screenCenter`、高 = 屏高 × `cam.s`，命中层与环位数学仍吃这个）；**平台视图**则吃 `viewRect(族尺寸)` + `Transform.scale`。切页推镜头 = `_cam` ValueNotifier 驱动（弹簧在 main.dart `_onCamTick` 跑，环场与舞台同一数据源）。
- **标定（alpha 包围盒，正道）**：`StageAnchors`（camera.dart:26-41）已有原型 `_fitGeo` 实测值（hair .4386 / feet −1.5114，同模型同数据，直接沿用）。若 MuMu 上她的大小/位置与原型基准图有出入，重标定流程：
  1. 进**标定模式**（debug-only 开关：隐藏 dock/HUD/环场/字幕/底栏，纯色背景——隐藏 UI 是关键，防止旧 AVD 上「底部吃到委托按钮与地面光晕、bot 恒为 807」的噪声复现）；
  2. `adb exec-out screencap` 取 PNG，用 **alpha 通道阈值**（如 α>8 的行列范围）算包围盒——这是 alpha 包围盒法，**不是**旧坑的"轮廓/边缘量测"；
  3. 由 top/bot 反解 `scale/dy`（方法论同 `.verify/probe_cal.py`，脚本升级为 `tools/ref/calib_alpha.py`）；
  4. 常量写回 `StageAnchors`，删标定开关。
- 她的目标占屏高：大厅 92%（`stage.js` 相机表注释，原型 `CAMS.lobby` 系数），即顶约 4.5%H、底约 96.5%H。

#### 1.5.4 Stage.emote / Stage.motion 表情动作桥接线

原型语义（stage.js）：`emote(name)` = 12 情绪表 `FACES`（L27-40）+ 情绪→表情文件 `EMO_EXP`（L73-77）；`motion(verb)` = 动词→动作文件 `MOVE`（L45-65）。原生插件 API：`setExpression(index)`（只收下标）+ `startMotion(group, index, priority)`（收**组名**）。转换产物 `sakiko.model3.json` 的 17 个动作组：`idle/smile/nod/cry/angry/look/surprised/question/sad/serious/denial/check/bye/misc_tear/maskoff/kime/thinking`（本机已核实）。

桥接表（写进 `live2d_stage.dart` 静态表，配单测核对名表一致性）：

| 情绪 emote | 表情文件（EMO_EXP 原值） | 动作组（MOVE→组名映射） |
|---|---|---|
| neutral | exp_idle01 | idle |
| smug | exp_bsmile01 | smile |
| cold | exp_serious01 | serious |
| annoyed | exp_angry02 | angry |
| pleased | exp_smile01 | smile |
| tsun | exp_shy01 | denial（fluster 用） |
| joy | exp_bsmile02 | kime |
| proud | exp_smile02 | kime |
| surprised | exp_surprised02 | surprised |
| sad | exp_sad02 | sad |
| focus | exp_serious02 | check |
| sleep | exp_idle04 | idle（speed 0） |

MOVE 动词→组：present/cheer→kime · nod/nod2→nod · surprise→surprised · fluster/deny→denial · down→sad · think→thinking · happy→smile · poke→check（+exp_shy01）· lookAway→look · ask→question · bye→bye · check→check · serious→serious · angry→angry · cry→cry · maskoff→maskoff。

`Live2DStageHandle` 已具备 motion/expression/param/speed 四个方法——补一层 `mood(String name)` / `act(String verb)` 语义包装 + 情绪→表情下标查表。接线点（原型 flows.js 对照）：
- 派单落定 `present`（flows.js 钤印处）· 接单 `nod`（accept）· 执行态 `focus`（exec）· 结算 `focus→pleased/tsun`（settle L372/394）· 暴击 `surprised`+`surprise`（L395）· **失败 `sad`+`down`——`main.dart:981-1000 _beginFail` 里被拿掉的 `emote('sad')` 在桥接完成后恢复**（那里注释明示等这个）· 待机池按心情 `IDLE_POOL`（cold/pleased/neutral 三池，stage.js:67-71）。
- 双实现等价：`Live2DWeb` 侧经 JS 桥补同名 `Stage.emote/motion`（stage.js 本来就有，`_pushCam` 同通道 `runJavaScript` 即可），把手统一为抽象接口 `StagePort`，main.dart 只认接口——这是**新增小接口文件**，两实现各自适配。

---

## 二 · 新功能设计

> 总原则：**LLM 一切调用必须可兜底**——无网/无 Key/超时/解析失败时回退到现有 LINES 模板与本地规则，App 永不因 LLM 不可用而卡住（与「提交卡死」同类事故零容忍）。所有新文案走 `SystemCopyProvider`，所有新数据有迁移默认值。

### 2.1 绑定流 + 卡片式访谈（首目标 3 天）

**流程**（改造 `Moment.onboard`，现只有第 4 幕输入框，BEHAVIOR-GAPS G4）：

```
开机 → 询问目标（现有 AskField：presets + 自由输入）
     → 【卡片式访谈】3~5 张信息卡（按目标类型出题，见下）
     → 生成 3 天首目标（烟花动效沿用原型语义）
     → 进大厅（首单已钉在队列）
```

- **询问语气**（绑定首句）：「说吧，你最近的目标是什么？我帮你变强。」（沿用 LINES.askGoal 基调，SystemCopyProvider 可润色）。
- **卡片式访谈**：目标 → 类型识别（关键词表 `goal_gen.dart`，原型 `CATS`/`CAT_ORDER` 移植：run/slim/fit/lang/exam/sleep/make/code/bold/gen 十类）→ 出 3~5 张卡。每张卡 = 一个问题 + 3~4 个选项 chip + 「自己写」自由输入。**卡组数据本地模板为真源，LLM 可加卡/改措辞（可兜底）**。
  示例（早睡早起 / sleep 类）：
  1. 「现在几点起、几点睡？」：0 点前睡 7 点前起 / 0-1 点睡 8 点起 / 1-2 点睡 9 点后起 / 没有固定 —— 自己写
  2. 「最近几天作息如何？」：基本规律 / 偶尔熬夜 / 天天熬夜
  3. 「愿意做怎样的坚持？」：每天早睡 15 分钟 / 固定起床闹钟 / 午休不超 30 分钟 / 睡前不碰手机
  （run 类示例：现在能跑多远 / 一周跑几次 / 愿意每周留几个时段）
- **答案三用**：① 定制首目标 3 环的参数（难度起点/时限/证明方式，如「天天熬夜」则第 1 环从 E 级「比昨天早睡 15 分钟」起）；② 选定日常任务池（该类 `CATS.daily` 优先）；③ 写入小祥长期记忆（「宿主通常 1-2 点睡」）——**访谈即第一批记忆**。
- **依据等级设定合适内容**：等级（及是否首次立目标）决定环数/档位：
  - **首次新目标 = 3 天 3 环**：`E / D / C`，每天一环，验证「能坚持」再展开长链（对齐 docs/05 摘要「前 10 任务必胜」的精神：3 环全部低门槛高胜率）；
  - 3 天完成后（或老用户换目标）：按目标时长词解析环数（原型 `makeGoal`：一周/两周=5、两月=7、三个月+=8）生成 5~8 环长链（LLM 拆解优先，关键词模板兜底，即 docs/13 摘要的双轨）；
  - 等级越高档位上限越高（沿用 `genDaily` 的 lv4/lv8 提档逻辑，store.js:112-114）。
- 绑定完成仍发「见面礼 双倍卡 ×1」（原型 `bind()`，store.js:160-169）。

### 2.2 周期任务生成（每日 1~2 个）

- **每日常规**：每日 1~2 个（取代原型 `dailyCount=clamp(1+⌈lv/3⌉,2,4)`）：`n = (lv >= 5 || 连击 >= 3) ? 2 : 1`；清晨首次进入 App 时补发（`rollDay`，store.js:179-196 语义：隔夜日常作废、主线单重钉、连击跨天判定）。
- **按目标类型生成数个**：从当前目标类型的 `CATS.daily` 池 + 通用池 `DAILY_COMMON` 里**先生成候选 4~6 个**，再按「一单专治最弱维、一单贴主线、其余随缘」（store.js:108 的 plan 策略）挑 1~2 个——即"生成数个、用 1~2 个"。
- **换任务入口**（与 2.7 联动）：候选中未被选中的单子不丢弃，小祥手里可见，用户可经聊天换（换单券语义沿用 D4）。
- **日上限**：6（docs/01 摘要沿用）；主线单不占日常配额。

### 2.3 E~S 奖励数值（新表，落地为 `lib/data/rewards.dart`）

| 档位 | EXP | 金币 | 六维 pt | 建议时限 min | 备注 |
|---|---|---|---|---|---|
| F | 0 | 3 | 1 | 10 | **兼容档**：新生成任务不再出 F；仅老存档/补救残单结算用 |
| E | 1 | 5 | 1 | 15 | |
| D | 2 | 5 | 2 | 20 | |
| C | 4 | 5 | 2 | 30 | |
| B | 6 | 7 | 3 | 40 | |
| A | 8 | 10 | 4 | 60 | |
| S | 10 | 20 | 6 | 90 | |

- **暴击 ×2、双倍卡 ×2、可叠 ×4；补救单 ×0.5**——沿用原型结算规则（store.js:281-283）。
- **升级曲线**（配套新 EXP 量级，替换 `need=60+lv*40`）：`need(lv) = 12 + lv × 6`（lv1=18 … lv5=42 … lv10=72）。校验：首目标 3 天得 1+2+4=7 EXP + 3 天日常约 2~8 → **第 3~5 天升 LV2**，节奏对齐「首目标 3 天」的正反馈；此为**单一可调常数**，验收后可微调。
- **道具沿用现有 ITEMS 表**（dbl 60 / crit 45 / shield 90 / swap 30，`items.dart` 不改）：新金币量级下约 3~10 天攒出一件——成长感保留，不返利。
- 金币唯一去处仍是补给页（D7 购买接线后生效）。

### 2.4 LLM 视觉校验（拍照打卡 → 多模态识别）

**链路**：

```
执行页证据槽 +（D9）→ image_picker 拍照/选图（最多 3 张）
  → 压缩至 ≤1280px、JPEG q80 → base64
  → 视觉校验（设置开=默认开）：OpenAI 兼容 POST {base}/chat/completions
      messages=[system 校验人设, user{任务名+证明要求+图片(data URL)}]
      model = 设置页配置（首发 deepseek-v4.1flash）
  → 期望 JSON：{"match": true|false|unsure, "note": "≤40字"}
  → match=true   证据标「已校验 ✓」；false/unsure 标「存疑」并附 note
  → 暴击率联动：已校验证据每张 +7%，未校验每张 +4%（替代原 .06/张），封顶 .85 不变
```

- **兜底铁律**（任一环节失败：无 Key/超时 12s/非 200/JSON 解析失败）：证据照收、标「未校验」、按未校验加成计——**校验失败永不阻塞提交**。这就是「模板兜底」在视觉侧的形态。
- **设置页**（系统 Sheet 新分组「LLM · 视觉校验」，随 D8 一并接线）：
  - 开关：视觉校验 开/关（关=纯信任模式，全部按未校验计）
  - Base URL（默认 `https://api.deepseek.com`）/ API Key（掩码显示）/ 模型名（默认 `deepseek-v4.1flash`，自由填写）
  - 「测试连接」按钮：发一条最小请求，回显 成功/失败原因
- 实现：`lib/agent/llm_client.dart`（**OpenAI 兼容统一客户端**，2.4/2.5 共用：chat + vision + function calling，http 超时/重试 1 次）+ `lib/agent/vision.dart`；依赖新增 `http`、`image_picker`、`path_provider`（照片落 App 文档目录，存档只存相对路径，见 2.8）。
- 隐私与合规注：Key 只存本机 SharedPreferences；照片仅在开启校验时上行；设置页文案明示。

### 2.5 小祥：人设 + 长期记忆 + agent 工具注册表 + SystemCopyProvider

**人设（宿主钦定，写死在 `lib/agent/persona.dart` 系统 prompt 首段）**：

> 你是「小祥」，绑定宿主的系统娘。你曾是养尊处优的大小姐，家道中落，意外沦为系统。你毒舌、爱吐槽、嘴上不饶人，但永远靠谱：宿主的每一条记录你都当真，每一个承诺你都盯着兑现。你不卖萌、不道歉式客服腔；吐槽完一定给出可执行的下一步。你只在「系统说话」的四个时机开口，句短、冷、准。

- **四种固定语气沿用 docs/07（摘要）**：**发布**（钉单时的说明与理由）/ **结算**（按档位 tier：low/mid/high/top）/ **毒舌**（连败/退缩/空证据时，引用真实数据）/ **追问**（访谈与换任务时的提问）。四语气即 SystemCopyProvider 的四个入口函数。
- **SystemCopyProvider（`lib/agent/copy.dart`）**：`dispatchLine(quest, ctx)` / `settleLine(result, tier)` / `roastLine(ctx)` / `probeLine(ctx)`。每个入口：先试 LLM（人设 prompt + 语气模板 + 上下文：等级/连击/最近 3 条历史/相关记忆，≤120 token 约束、temperature 0.8、**300 字符长度钳制**），失败/超时/未配 Key → **逐字回退现有 LINES 对应模板**（content.dart 原样保留，它就是兜底真源）。发布/结算/毒舌三处现有调用点（`_sayAside`/LineLayer text）在 T5 接线。
- **长期记忆（`lib/agent/memory.dart`）**：
  - 存储：独立 key `opus-v2/memory/v1`（SharedPreferences，JSON list；见 2.8）。条目 `{id, text, at, source: interview|chat|tool, weight}`，上限 200 条，满时按 weight+新旧淘汰。
  - 写入：访谈答案（2.1）必写；聊天中用户明确「记住…」类语句经工具 `remember` 写入（2.5 工具表）；结算里程碑（首胜/升级/断连击）自动写。
  - 读取：每次 LLM 调用注入**最相关 8 条**（关键词命中 + 最近 5 条兜底；**第一版不做 embedding**）。
  - **重启仍在**：随存档持久化，验收用例「说一句话 → 杀进程重启 → 她还记得」。
- **agent 工具注册表（`lib/agent/tools.dart`）**：`AgentTool{name, desc, schema, run(args)}`，注册表可扩展，首发 6 个：
  | 工具 | 作用 | 对应实现 |
  |---|---|---|
  | `get_status` | 查状态：LV/EXP/金币/连击/队列/主线进度 | 读 HostState+QuestFlow |
  | `swap_quest` | 换任务（换掉队首日常/换目标，主线环走 newGoal 语义） | QuestFlow.retreat/swap/newGoal |
  | `adjust_plan` | 调整计划：改时限/降档/顺延 | QuestFlow 队列单字段修改 |
  | `remember` | 记住宿主说的话 | MemoryStore.add |
  | `recall` | 查记忆 | MemoryStore.query |
  | `summarize_progress` | 总结近 7 天执行情况 | 读 history 聚合 |
  LLM 侧走 OpenAI function calling（tools 数组）；**无 LLM 时工具仍可用**——聊天面板提供快捷 chip（「查状态」「换任务」「调整计划」）直调工具，输出走模板文案。这就是「可扩展到应用内任何操作」的注册表形态：后续任何页面操作注册一个 AgentTool 即可被对话驱动。
- 安全钳制：工具只改队列/计划，**不直接改经验金币**（数值只能经结算）；每次工具调用写聊天历史并在 UI 上以系统条目可见。

### 2.6 首页与 Live2D 对话（文本先行，语音预留）

- **入口**：大厅 HUD 增「对话」按钮（`sys_icons.dart` 新增 glyph；位置在菜单键左侧）。点击升起**对话层**（从底部滑入，占屏高 72%，背景半透明压暗，她在后面仍可见——层序在 Live2D 之上、亮帧之下）。
- **对话层（`lib/widgets/chat_panel.dart`）**：
  - 顶部：小祥名牌（名字 + 「系统娘 · 在线」状态点）；
  - 中部：**可滚动历史**（ bubbles：她=左+青框，宿主=右；时间分组头「今天/昨天/M月D日」）；
  - 底部输入栏：**两个入口并排**——【文本输入框 + 发送】【🎤 语音】。**语音按钮本期禁用态**（置灰 + 「语音 · 预留」角标，点击弹插话「语音模块还没装配。先用打的。」）；文本框回车/发送均提交。
  - 消息流：发送 → 追加历史 → 「思考中…」占位 → `persona + memory + tools` 的 LLM 回复（2.5）→ 失败回退固定 5 句毒舌之一。
  - 演出联动：她开口时 `StagePort.mood(映射情绪)`（LLM 回复带 emotion 标签：neutral/smug/pleased/…，解析失败回 neutral）+ 打字机沿用到 bubble（`TypeText` 复用）。
- **历史持久化**：独立 key `opus-v2/chat/v1`，滚动窗口 200 条（满删最旧），**杀进程重启可查**。验收用例：「发 3 条 → 重启 → 历史可见可滚」。
- 首页字幕（LineLayer）不动——对话层是叠加，不替换。

### 2.7 任务评价处唤起小祥换任务

- 入口 A（结算页）：`ResultPanel` 头部区加次级按钮「找小祥说说」→ 打开对话层并预置上下文（当前任务 + 结算结果注入），快捷 chip 首位即【换下一单的类型】→ `swap_quest`。
- 入口 B（派单板）：D4「换一个」长按 0.6s（短按仍走降档 retreat）→ 同 A。**保底**：不想接 LLM 时，入口 A/B 的快捷 chip 直调工具，全部本地可用。
- 换任务规则钳制：主线当前环不可换（她直接拒绝，原型 store.js:254 语义）；日常换=换单券或当日 retreat 计数；换目标=走 2.1 访谈迷你流（3 卡快速版）。

### 2.8 存档迁移与老数据兼容

**原则：沿用 `save_file.dart` 既有的「在 fallback 上合并」惯例——新增字段必带默认值，老档缺字段自动补默认，永不要求用户清档。**

| 数据 | 存储 key | 迁移策略 |
|---|---|---|
| 宿主档案 + 主线（现有） | `opus-v2/save/v1` | **结构不动、只加字段**（SaveData 增 `queue/active/history/remedyOffer/interview` 子对象，fromJson 全部带默认空值） |
| LLM/视觉设置 | `opus-v2/settings/v1`（新） | 缺省 = 视觉开、deepseek-v4.1flash、空 Key |
| 长期记忆 | `opus-v2/memory/v1`（新） | 缺省 = 空表；首次升级自动从现有 goal.text 写入一条「宿主的目标是 X」 |
| 聊天历史 | `opus-v2/chat/v1`（新） | 缺省 = 空表 |
| 证据照片 | App 文档目录 `evidence/<questId>/n.jpg`（新） | 存档只存相对路径；文件丢失时证据计数照旧、图标降级为「已丢失」 |
| **demo 档清洗** | — | 老用户若处于「demo 态」（`ringIndex>=0` 且 `goal.rings` 非空但无队列）：升级首启**不重置档案**，补生成队首主线单 + 当日日常（`rollDay` 幂等），等级/金币/称号原样保留 |

- **版本策略**：不换 save/v1 的 key（换 key=弃档，禁止）；结构演进只做**加法合并**。`SaveFile.selfTest()` 启动自检继续保留。
- **冻结语义保持**：wipe 后回绑定仪式、`unfreeze()` 在重新绑定时调用（既有坑，勿回归，见 BEHAVIOR-GAPS 附录）。

---

## 三 · 文件级分工表

### 3.0 单写者纪律（硬约束）

- **同一文件在同一时刻只允许一个会话写**（仓库有并行写坏先例，AGENTS.md「单文件原型的写入纪律」）。下表把每个文件指派给**唯一**负责任务；需要同文件改动的任务**必须串行**（时序见 3.2），并行只允许发生在**互不相交的文件集**上。
- 热点文件 `main.dart`、`pubspec.yaml`、`quest_flow.dart` 是冲突高发区：设计上已把绝大多数逻辑下沉到新文件，`main.dart` 只留装配改动，且按 3.2 串行。

### 3.1 任务 → 可写文件清单

| 任务 | 内容 | 新建文件（可写） | 修改文件（可写） | 说明 |
|---|---|---|---|---|
| **T2 · 提交卡死修复 + 结算链路** | 1.2 全部根因：真实结算、结算/失败退出路径、保存战报 | `lib/state/quest_flow.dart`；`test/quest_flow_test.dart` | `lib/main.dart`（onSubmit→settle、result/fail Choices、onSave、queue 计数、暴击率）；`lib/state/result.dart`（补 ups/titles/empty 字段）；`lib/state/save_file.dart`（SaveData 加 queue/active/history，默认空）；`test/result_test.dart` | 纯本地业务，无 LLM 依赖；先行任务，其余任务依赖它的 quest_flow |
| **T3 · Live2D 原生切换（MuMu）** | 1.5 全部：切换+止损线、相机矩形、emote/motion 桥、标定脚本 | `lib/stage/stage_port.dart`（StagePort 抽象 + 情绪/动作映射表）；`tools/ref/calib_alpha.py`；`test/stage_port_test.dart` | `lib/stage/live2d_stage.dart`（几何相机 + mood/act 接口 + idle 池）；`lib/stage/live2d_web.dart`（JS 桥补 emote/motion，适配 StagePort）；`lib/main.dart`（**仅**舞台挂载与 `_beginFail` emote 恢复，与 T2 串行）；`app/STAGE-OPTIONS.md`（MuMu 实测结论增补） | Android 侧验证；CMake 覆盖只核实不改 |
| **T4 · LLM 客户端 + 视觉校验 + 面板接线** | 2.4 全部 + D6/D7/D8 死按钮 | `lib/agent/llm_client.dart`；`lib/agent/vision.dart`；`lib/agent/settings_store.dart`；`test/llm_client_test.dart`；`test/vision_test.dart` | `lib/widgets/sheet.dart`（buy/equip/seg 接线 + LLM 设置组）；`lib/widgets/exec_panel.dart`（证据槽手势）；`pubspec.yaml`（+http/image_picker/path_provider，**集中一次加齐**）；`test/sheet_test.dart` | 与 T2/T3 文件集不相交（除 main.dart 不碰） |
| **T5 · 小祥 Agent + 对话层 + 文案接管** | 2.5 + 2.6 + 2.7 全部 | `lib/agent/persona.dart`；`lib/agent/memory.dart`；`lib/agent/tools.dart`；`lib/agent/copy.dart`；`lib/widgets/chat_panel.dart`；`test/persona_test.dart`；`test/memory_test.dart`；`test/copy_test.dart` | `lib/main.dart`（HUD 对话按钮、结算页「找小祥说说」入口、SystemCopyProvider 接线——**排在 T2/T3 之后**）；`lib/widgets/sys_icons.dart`（对话 glyph）；`lib/widgets/result_panel.dart`（次级按钮，与 T2 同文件串行） | 依赖 T2 的 quest_flow（工具实现）与 T4 的 llm_client |
| **T6 · 绑定流 + 访谈卡 + 首目标 3 天 + 日常生成 + 奖励表** | 2.1 + 2.2 + 2.3 全部 | `lib/state/goal_gen.dart`（CATS 移植 + LLM 拆解 + 3 天首目标 + 日常候选池）；`lib/data/rewards.dart`；`lib/widgets/interview_deck.dart`；`test/goal_gen_test.dart`；`test/rewards_test.dart` | `lib/main.dart`（onboard 多幕装配——**排在 T2/T5 之后**）；`lib/state/quest.dart`（rewardText 改读 Rewards）；`lib/state/goal.dart`（plan 元数据字段：类型/访谈答案引用）；`test/quest_test.dart` | 依赖 T2 quest_flow（genDaily/rollDay 挂点） |
| **T7 · 回归与验收** | 全量验证 + MuMu 截图证据 | `.verify/agent-upgrade/`（截图与 dumpsys 留痕，不入库） | 无源码（发现问题开返工卡，回对应任务） | 最后执行：analyze/test 全绿 + 本文第四章逐项核对 |

### 3.2 共享文件时序（串行约束图）

```
T2（main.dart、result.dart、save_file.dart）
 ├─→ T3（main.dart 舞台段：在 T2 合入后开工）
 ├─→ T5（main.dart 对话段：在 T2、T3 合入后开工）
 └─→ T6（main.dart onboard 段：在 T2、T5 合入后开工；last）
T4 与 T2/T3 并行（文件集不相交）；T4 的 pubspec.yaml 全程唯一写者
T7 收尾（全部合入后）
```

- T3 与 T2 都改 `main.dart` 但**区段不同**（舞台挂载 vs 结算链）；仍要求**先后合入**（T2 先），后开工者基于最新 main.dart。
- `quest_flow.dart` 由 T2 独建；T5/T6 只**读**它（工具实现/生成挂点经其公开 API），不改其文件；若必须改，开返工卡回 T2 名下处理。
- `sheet.dart` 唯一写者 = T4；`exec_panel.dart` 唯一写者 = T4；`chat_panel.dart` 唯一写者 = T5。

### 3.3 新增依赖与平台配置（集中在 T4，一次到位）

| 依赖/配置 | 用途 | 备注 |
|---|---|---|
| `http` | LLM OpenAI 兼容调用 | 纯 Dart，无平台代码 |
| `image_picker` | 证据拍照/选图 | Android 无需额外 manifest 权限（MediaStore 路径）；iOS 部分忽略 |
| `path_provider` | 证据照片目录 | 文档目录 `evidence/` |
| AndroidManifest `INTERNET` 权限 | **release 构建必需**（debug/profile 模板已带，main manifest 没有）——LLM/视觉上行需要 | T4 在 `app/android/app/src/main/AndroidManifest.xml` 加一行；`network_security_config.xml` 只放行回环明文，**外网 LLM 走 https，无需放宽** |

---

## 四 · 逐项验收核对表

> 每任务完成后按对应行核对；T7 全量跑一遍。命令基准：`cd app && flutter analyze`（No issues found!）&& `flutter test`（全绿，对照 ENV.md 基线 246+新增）；MuMu 目标 `127.0.0.1:16512`。

### T2 · 提交卡死修复

- [ ] 执行→提交→结算演出完整（扫描线/砸印/跳数/涨条/筹码，现有测试不回归）
- [ ] 结算数字来自真实计算：E 级单 EXP +1、金币 +5；暴击 ×2、双倍卡可叠（quest_flow_test 断言）
- [ ] 经验/金币/六维/连击落到档案（面板页数值变化），升级走 need=12+lv×6
- [ ] 结算演出结束弹出【再来一单。/先歇会儿。】；队列空时【收工。】；点击后正确离开结算页
- [ ] 失败页【……接。】生成补救单并进派单；【今天算了。】回大厅
- [ ] 「保存战报」可点：产出战报文本入剪贴板/分享，插话确认
- [ ] 主线环在结算后点亮，队首补下一环主线单；大厅 queue 读数随真实队列
- [ ] 卡死复测：连做 3 单（提交→再来一单循环），无任何一步停留 >5s 无出口
- [ ] 存档：结算后杀进程重启，档案与队列保持

### T3 · Live2D 原生切换（MuMu）

- [ ] MuMu 上 `flutter run` 编译过（CMake 反射覆盖未报 CXX1300；若报，处置记录进 STAGE-OPTIONS）
- [ ] `kNativeStage=true` 时她**上屏**；若触发 1.5.1-3 止损线：默认回 WebView、证据留痕、结论写入 STAGE-OPTIONS 增补节
- [ ] 层序：字幕/环/HUD 压在她之上（截图对照 `.verify/_stageback.png` 判据）
- [ ] 相机：大厅她占屏高约 92%（顶 ~4.5%、底 ~96.5%），切页推镜头平滑（弹簧驱动矩形）
- [ ] emote/motion 桥：失败触发 `sad`+`down`（`_beginFail` 恢复）；结算/派单/接单各有表情动作；stage_port_test 核对 12 情绪与 17 组名表完整
- [ ] 标定脚本 `tools/ref/calib_alpha.py`：alpha 阈值法可复跑；**无任何「截图轮廓量测」路径**
- [ ] gfxinfo 中位帧 ≤24ms（对比 WebView 基线 89ms）

### T4 · LLM 客户端 + 视觉校验 + 面板接线

- [ ] 设置页：视觉校验开关/BaseURL/Key/模型名（默认 deepseek-v4.1flash）/测试连接，全部持久化（重启保留）
- [ ] 证据槽可拍照/选图，≤3 张，缩略图入槽；删档不残留孤儿照片
- [ ] 配 Key 时：拍照→校验请求发出→「已校验 ✓/存疑+note」标记正确；暴击率按 7%/4% 联动（vision_test 断言）
- [ ] **兜底**：无 Key/断网/超时/坏 JSON 四种情形，提交流程照常、证据标「未校验」，App 无卡顿无崩溃
- [ ] 补给页购买：扣币加道具、余额不足变灰+插话；档案页点称号可挂上（口头巨人期禁止）
- [ ] 系统页四个开关可切且持久化；release manifest 含 INTERNET 权限
- [ ] `flutter analyze`/`flutter test` 全绿（新增 mock 测试不打真网）

### T5 · 小祥 Agent + 对话层

- [ ] 大厅 HUD 对话按钮 → 对话层升起；文本可发、回复毒舌但靠谱（人设 prompt 生效）；**语音按钮置灰带「预留」标识**
- [ ] 历史：发 3 条 → 杀进程重启 → 历史在、可滚动、时间分组正确
- [ ] 记忆：访谈/聊天「记住 X」→ 重启后新对话能引用 X；条目上限淘汰生效
- [ ] 工具：快捷 chip「查状态/换任务/调整计划」无 LLM 也可用；LLM 开启时 function calling 正确调用并回执
- [ ] SystemCopyProvider：发布/结算/毒舌/追问四处接 LLM 文案；断网回退 LINES 原句（逐字，content_test 不回归）
- [ ] 结算页「找小祥说说」入口打开即带当前任务上下文；换任务钳制（主线当前环拒换）生效
- [ ] 钳制：任何工具不可直接改经验/金币（测试断言）

### T6 · 绑定流 + 访谈 + 生成 + 奖励

- [ ] 新档绑定：问目标 → 3~5 张访谈卡（选项+自由输入）→ 生成 **3 天 3 环（E/D/C）** 首目标 → 见面礼双倍卡 → 大厅首单在队列
- [ ] 访谈答案生效：「天天熬夜」起环更轻；答案进记忆（T5 验收联动）
- [ ] 日常：每日 1~2 个（lv≥5 或连击≥3 为 2），清晨补发、隔夜作废；按目标类型出候选池再挑
- [ ] 奖励表：E1/D2/C4/B6/A8/S10 与金币 5/5/5/7/10/20 落地（rewards_test 逐档断言）；道具价格未动
- [ ] 老档升级：demo 态老用户不丢等级金币，队列自动补齐；无任何要求清档的路径
- [ ] 换目标（D5）：经小祥走迷你访谈 → 新链替换、旧主线单移除

### T7 · 回归与验收（全量）

- [ ] `flutter analyze` = No issues found!；`flutter test` 全绿（原 246 + 新增全部）
- [ ] MuMu 全页截图 vs 原型回归：`tools/ref/drive.ps1` → `regress.py` 阈值 4%（设备 `127.0.0.1:16512`；`wm size 780x1688` + `wm density 320` 前置，MuMu 重启后需重跑）
- [ ] 本文 1.3 死按钮清单 12 项逐个点过：每一项有真实行为
- [ ] 全链路冒烟：新档→绑定→访谈→3 天目标→执行→拍照→提交→结算→换任务→次日补单（可用调试快进时钟）
- [ ] LLM 全断网冒烟：以上链路在无 Key/断网下完整可玩（全部走兜底）

---

## 附 · 与既有文档/纪律的关系

- 本文档不推翻 00~17（缺席）与原型；视觉规格冲突时以原型截图比对为准。
- 提交纪律沿用 HANDOFF「Git 纪律」节；中文 Conventional Commits。**Live2D 数据政策已变**：`41576dd` 起宿主主动取消 gitignore、模型/播放器随仓库分发（见 ENV.md）——旧文档里「版权红线、换机单独拷」的告诫已作废，但**宿主自有改动清单**（.gitignore、AGENTS.md、dev-dashboard/ 等）仍永不提交。
- STAGE-OPTIONS 的「证据够了不再投入」纪律在 T3 中体现为硬止损线（1.5.1-3）。
