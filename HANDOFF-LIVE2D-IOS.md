# 交接：Live2D 原生渲染合成问题（iOS）

> 写给下一个 Agent。上一段工作：把 `prototype/opus-v2-dir` 原型逐页复刻进 Flutter 工程 `app/`（60 轮，全部已提交，最新 `22dc2bd`）。
> 本次焦点（宿主指定）：**在 iOS 上解决 Live2D 的原生渲染合成问题**，替换掉目前承担角色渲染的 WebView（性能不达标）。
>
> **本文档入库随仓库走** —— 但⚠️ 模型/播放器数据因版权**不在 git 里**（见下「数据搬运」），
> 换机时除了 clone 仓库，那一部分仍要单独拷。

## 一句话现状

- App 其余部分（12 个页面、环场、HUD、字幕、底栏）全部是**原生 Flutter**，已完成并验证（各页与原型差异 1.7–3.5%）。
- **只有"她"（sakiko 角色）目前跑在 WebView 里**：`webview_flutter` + App 内本机 http 服务 + 原型自己的播放器。能用但重（实测多 225MB 沙箱进程、中位帧 89ms ≈ 11 FPS，模拟器数字）。
- 原生路线（`flutter_live2d 1.0.2` + 转换好的标准 Live2D 数据）**加载成功但在这台 Android 模拟器上不上屏**，已按宿主指示搁置。**你的任务是在 iOS 上把它做成。**

## 必读（按顺序，别跳）

1. `app/STAGE-OPTIONS.md` —— 完整决策与排查记录：为什么走 ②、① 在 Android 上的证据链、9 个坑、往后三条路。
   **不要重查已经实验排除的假设**：Impeller、我转换的模型数据（标准模型 Hiyori 对照）、`ShakeLayer` 的 Transform、Stack 层序 —— 全部排除过了。
2. `app/lib/stage/live2d_stage.dart` —— **原生舞台组件还在，只是没被 main.dart 引用**：内含 5 次加载重试（原生加载有竞态，实测第 1 次 false 第 2 次 true）、28 个表情名表（与转换产物 model3.json 的字母序一致）、idle 动作组。切回原生 = main.dart 里把 `Live2DWeb` 换成它（A/B 期间就是这么切的，一两行）。
3. `app/lib/stage/live2d_web.dart` —— WebView 基线，**保留作降级与验收参照**（原型同一个播放器，渲染结果有保证）。
4. `tools/l2d/convert.py` —— prefab → 标准 Live2D 转换器（已验证：64 动作 / 28 表情 / 物理 / moc3 v5）。

## iOS 待办（建议顺序）

0. **环境**：iOS 模拟器在 **Mac Air**（Windows 机不接 iOS/真机），配置脚本 `tools/setup-macos-ios.sh`。`flutter_live2d 1.0.2` 声称支持 iOS（UiKitView，各自 GL context；bundled Cubism Core 支持 moc3 3.0–5.3，我们的模型是 v5）。
1. **数据搬运（git 里没有，版权红线）**：以下全部被 gitignore —— 原始 prefab（`prototype/opus-v2-dir/live2d/sakiko/`）、转换产物（`app/assets/live2d/sakiko/`）、播放器（`app/assets/live2d/vendor/`）、Hiyori 对照（`app/assets/live2d/hiyori/`）。Mac 上**从这台机器直接拷**（别走 git），或拷原始数据后跑 `python tools/l2d/convert.py`。pubspec 的资产声明都在了；⚠️ **Flutter 声明目录不递归**，子目录必须逐个列（已列好，别"清理"掉）。
2. **先过编译**：`flutter build ios --no-codesign` 或直接模拟器 run。Android 那边的坑是插件把 CMake 版本写死 3.10.2 且 Google 已下架（解法在 `app/android/build.gradle.kts` 的反射覆盖，注释有 Why）；iOS 走 CocoaPods，坑会不一样，先看 podspec。
3. **跑原生舞台**：main.dart 切回 `Live2DStage`，iOS 模拟器截图看她在不在。**能上屏 → ① 复活。**
4. **层序**：她必须在天幕之后、环场/UI 之前（= 原型 `#bg → #stage → #ui`）。这个位置的层序已在 Android 上验证完全正确（留痕 `.verify/_stageback.png`，未入库）。⚠️ `ShakeLayer`（`lib/widgets/fx_layer.dart`）已改成"不抖就不套 Transform"（平台视图吃不了任意变换，`test/fx_test.dart` 的注释写了为什么）—— 别"顺手"改回去。
5. **相机**：大厅里她应占屏高 **92%**（原型 `js/stage.js` L250-260 相机表，注释自带标定依据；现有 scale 1.132 是几何反推）。⚠️ **别用"量截图里她的轮廓"来标定** —— 底部会吃到委托按钮与地面光晕，bot 恒为 807，等于拿噪声当信号（我栽过，迭代两轮越调越偏）。正道：接 `_fitGeo` 等价接口向渲染器要 alpha 包围盒（原型 `stage.js` L183-222 就是这么做的），接上后相机自适应任意模型。
6. **表情/动作桥**：`Stage.emote` / `Stage.motion` 两边（原生与 WebView）都还没接。接上后把 main.dart `_beginFail` 里被拿掉的 `emote('sad')` 恢复（那里留了注释说明原因）。

## WebView 路线的坑（如果 iOS 上还要跑它做对照）

全文在 `live2d_web.dart` / `assets/stage/stage.js` 注释里，速记：
- Content-Type 必须按**资产 key** 取扩展名（URL `/` 没有扩展名 → octet-stream → WebView 不当网页渲染，症状是只收到 `GET /` 后一片安静）
- 播放器是 **ES Module**：不能当普通 `<script src>` 挂（解析阶段就失败、且报错早于 onerror 注册、零信号），必须动态 `import()` 后手动 `defineOurnotesLive2D()`（照抄原型 `stage.js` L112-115）
- 清单里的 `assets/xxx` 相对**页面根**解析（不是相对清单目录），服务端要兜 `/assets/...` 路由
- iOS 的 ATS：本机 http 需要 Info.plist 的 NSAllowsLocalNetworking（Android 侧已有 `res/xml/network_security_config.xml`，只放行 127.0.0.1/localhost，iOS 是另一套）

## 验证纪律（项目惯例）

- `flutter analyze` 必须 "No issues found!"、`flutter test` 246 个全绿，才准提交
- 对照原型：`cd prototype/opus-v2-dir && node server.mjs`（端口 4925），浏览器或 agent-browser 驱动截图
- 已知系统性残差：Flutter 渲染文字比 Chrome 墨量重 63–83%、字宽约 +1.5% —— **不要**为了像素差去伪造字重/字距
- 回归流程：`tools/ref/drive.ps1 -Only <pages>` 重抓 → `python tools/ref/regress.py`（阈值 4%）

## Git 纪律

- 只 `git add app`（+ 明确指定的 tools 路径）。工作区里**宿主自己的改动永远不提交**：`.gitignore`、`AGENTS.md`、`prototype/opus-v2-dir/css/app.css`、`dev-dashboard/`、`prototype/opus-v2-dir/img/`、`tools/comfyui/`
- 模型/播放器数据**永不入库**（版权：Bushiroad/Craft Egg/Ishimori；`app/assets/live2d/.gitignore` 管，嵌套否定规则的写法见该文件注释）
- 提交信息：中文 Conventional Commits；近期提交链：`22dc2bd`（相机标定）→ `f0e53cc`（①搁置/②就位结案）→ `d9befe1`（ShakeLayer 测试跟随）→ `e117b28`（WebView 打通）→ `b0703e6`（②可行性实测）

## 建议调用的 skills

- **`bug-fix`** —— 合成问题本质是"排查→修复→验证"循环，按它的流程走，避免再出现"方向错了查两轮"
- **`research`** —— 查 flutter_live2d 的 iOS 已知 issue、Cubism iOS 平台视图合成的已知坑（Android 侧的结论不能直接平移）
- **`commit-with-chinese`** —— 项目提交惯例（中文 Conventional Commits）
- **`agent-browser`** —— 需要驱动原型（localhost:4925）做对照截图时

## 本机环境速记（Windows 机，Android 侧对照时用）

- Flutter 3.47.6 @ `D:\flutter`（Dart 3.13.5）；国内源已配（`PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` = flutter-io.cn）
- Android 模拟器 `emulator-5554`，强制 390×844 @2x（`wm size 780x1688` + `wm density 320`）；截屏 780×1688 记得缩到 390×844 再量
- PowerShell 坑：`-replace` 大小写不敏感、会吃 `${}` 插值与反引号；CRLF 与中文引号会让字符串替换**静默失败** —— 改 Dart/带中文的文件一律用 edit 工具
- 原生路线换数据后要清插件缓存：`adb shell run-as com.systempanel.app rm -rf cache/flutter_live2d_models`；WebView 路线的本机服务无缓存问题
