# 舞台（Live2D 角色）落地路线

> **2026-10-08 结案：她渲染在 App 里了，走路线 ②（WebView），原生 ① 已搁置。**
> 搁置不是"放弃",是"证据够了、不再投入" —— 下面的排查记录就是证据。

## ⚠️ 关于 ② 的代价（必须知道）

用 `dumpsys` 实测（模拟器、虚拟 GPU）：

```
App 主进程 PSS       136 MB
WebView 沙箱进程     225 MB      ← 多出来的一个进程
合计                 约 361 MB
掉帧                 45.6% 的帧 > 16ms
中位帧时间           89 ms       （约 11 FPS）
```

**这个代价不能当最终方案。** ② 只解决"她先出来"这件事 ——
它用的是原型自己的播放器、同一份数据，所以**渲染结果有保证**，适合作为
基线实现与验收参照。真要上产品，还得回到原生（见文末「往后怎么办」）。

## 合成问题的最终结论（挖到底了）

排查顺序与结论：

| 假设 | 实验 | 结果 |
|---|---|---|
| Impeller + 平台视图的老问题 | 关掉 `EnableImpeller` | ❌ 无关 |
| 我转换的模型有问题 | 换标准模型 Hiyori | ❌ 无关（Hiyori 也看不见） |
| `ShakeLayer` 的 `Transform` 压住了 | 不抖时不套 Transform | ❌ 无关（改完还是看不见） |
| **她所在的层序不对** | **`kStageOnTop` 对照：挪到根 Stack 最上层** | ✅ **放上去就看得见**（但压住整个界面）→ **层序一直是好的** |
| 回到原位再验一次 | `kStageOnTop=false` | ✅ **原位渲染正常，字幕/环/HUD 都正确压在她之上** |

**所以：早先"加载成功但看不见"，根因是资产打包与 Content-Type 那几个坑，
不是合成层序** —— 我在错误的方向上查了两轮。

**② 的正确位置**（已验证，见 `.verify/_stageback.png`）：
天幕之后、环场/UI 之前 —— 与原型 `#bg → #stage → #ui` 的层序一致。

**① 的最后一次尝试**（按宿主指示"再试一次"）：
把她也放到根 Stack 最上层 —— `loadModel` 返回 `true`、`插件就绪` 打出来了、
`Live2D-RenderHub` 线程在跑、`dumpsys` 里视图全屏可见，**屏幕上依然什么都没有**。
→ **结论确凿：`flutter_live2d` 的平台视图在这台模拟器上就是不上屏。搁置。**

## 往后怎么办（给以后接手的人）

1. **换个原生插件**（最省事）—— 转换产物已经就绪，直接换渲染实现即可
2. **真机上试 ①** —— 模拟器是虚拟 GPU（`dumpsys` 里有 `vendor.mesa.virtgpu` 痕迹），
   插件在真机上未必有问题。宿主手边有真机时，这是最快见分晓的一步
3. **自己写平台视图** —— Cubism Native SDK 已经被证明能加载、能跑渲染循环
   （`flutter_live2d` 就是证据），缺的只是"把结果合成上屏"这一段

## 还差什么

- **相机标定**：她现在比原型略大、位置略有出入。`scale`/`offset` 已通到
  `Stage.cam()`（就绪时会主动推一次），但还没和 `camera.dart` 的 `Cam` 对齐。
- **表情/动作桥**：`Stage.emote` / `Stage.motion` 还没接（原型 `Stage.emote`
  是查表落到模型参数上）。接上之后，失败时的 `emote('sad')` 这类表演才能恢复。

## ✅ 转换器（`tools/l2d/convert.py`）

### 做成的

| 环节 | 状态 |
|---|---|
| prefab → 标准 Live2D 转换 | ✅ `tools/l2d/convert.py`，产物逐项验过 |
| 插件编译 | ✅ `flutter_live2d 1.0.2`（Cubism Core 支持 moc3 **3.0–5.3**，我们的模型是 5） |
| 资产打包 | ✅ 100 个资产进 APK |
| 原生加载 | ✅ `loadModel` 返回 `true` |
| **渲染** | ❌ **屏幕上看不到她** |

### 排查路上踩掉的坑（都已修）

1. **CMake 版本**：插件把版本写死 `3.10.2`，而 Google 已从 SDK 仓库下架
   （`sdkmanager "cmake;3.10.2"` → Package not found）。`local.properties` 的
   `cmake.dir` **压不过** DSL 里的 `version`。解法：在 `app/android/build.gradle.kts`
   里用反射统一改写子工程的 CMake 版本为 3.22.1 ——
   ⚠️ 那个 `subprojects` 块必须放在 `evaluationDependsOn(":app")` **之前**，
   否则报 "Cannot run Project.afterEvaluate when the project is already evaluated"。
2. **Flutter 声明资产目录不递归子目录**：只写 `assets/live2d/sakiko/` 的话，
   `motions/` `expressions/` `textures/` 全**不进包**（实测包里只有 4 个资产，
   逐个列出子目录后 100 个）。
3. **`Opacity(0)` 会让加载死锁**：插件原生侧把 `loadModel` 排进渲染线程队列，
   而队列**只对 EGL surface 已就绪的视图执行**；surface 来自 `TextureView` 的
   `onSurfaceTextureAvailable`，**必须真的参与绘制**才有。`Opacity(0)` 不画子树
   → surface 不创建 → `loadModel` 永不执行 → `await` 永远不返回。
   症状：日志停在「原生视图已就绪 → loadModel」，之后一片安静。
4. **`Opacity` 不能套在平台视图外**（走 saveLayer，会吞掉平台视图；`Opacity(0)`
   还会让加载死锁，见坑 3）。
   ⚠️ **但 `Transform` 可以** —— 这条 2026-10-11 真机复核**推翻了旧结论**
   （旧写法把 Transform 和 Opacity 一起禁了）。依据两条：
   · Flutter 自己的文档：`UiKitView` 所属的 `_DarwinView`
     （`packages/flutter/lib/src/widgets/platform_view.dart`）写着
     "support for transforms, clips, and opacity similar to any other Flutter widget"；
   · 真机（iPhone 15 Pro Max / iOS 27）实测：舞台用**固定尺寸族 + `Transform.scale`**
     推镜头，中途帧里她按**中间尺寸**正常渲染（截图量到头顶位置落在两端之间）。
   所以「相机靠布局矩形逐帧改尺寸」那套**必须废掉**：插件 iOS 侧 `layoutSubviews()`
   里会 `recreateFramebufferOnMainThread()` + `onSurfaceChanged()`（重建 FBO、排空
   渲染队列），按帧改尺寸 = 每帧重建 —— 推镜头那段她基本不渲染，落点看着就是
   "直接切过去"（宿主 2026-10-11 验收原话）。现在改为：
   **矩形只按"族"定尺寸（`Live2DStage.kViewFamilies` = [1.05, 1.70]），族内缩放/平移
   交给 `Transform`**，并配 `CamSpring.glideTo` 的 1.4s 慢推。
5. **原生加载有竞态**：同一份数据时而 `false` 时而 `true`（实测第 1 次 false、
   第 2 次 true）。已加重试（最多 5 次）。

### 还没解决的

`loadModel` 返回 `true`、`Live2D-RenderHub` 线程在跑（`ps -T` 看得到），
但屏幕上什么都没有。

**排除过的假设（都做了实验，都不是原因）**：

| 假设 | 实验 | 结果 |
|---|---|---|
| Impeller + 平台视图的老问题 | 关掉 `EnableImpeller` | ❌ 照样看不见（开关已撤回） |
| **我转换的模型有问题** | **换成标准模型 Hiyori**（`Live2DStage.useHiyoriControl`） | ❌ **Hiyori 也看不见** → 不是转换的问题 |
| 平台视图没进合成树 | `dumpsys activity top` 查视图树 | ❌ 在：`Live2DTextureView V.ED 0,0-780,1688`（全屏、可见） |
| 视图尺寸为零 | 同上 | ❌ 780×1688，正常 |

于是剩下两种可能，**都指向"插件的平台视图路径在这个 App 里走不通"**：

1. 平台视图被 Flutter 那层压住 / 合成顺序不对 —— 但那样她就得**盖住整个 UI**，
   设计上不能接受；
2. GL 内容本身就是空的（画了，但没进 TextureView）。

⚠️ 一个细节值得记：**Hiyori 的 `loadModel` 第一次就返回 true，sakiko 要两次** ——
说明这个插件的原生加载本来就带竞态。

**结论：不再在这一层继续投入。** 下一步走 **路线 ②**（WebView 跑原型那套播放器）：

- 渲染结果**有保证** —— 用的是原型同一个播放器、同一份数据；
- 转换器做的功**不白费**：标准 Live2D 文件已经躺在 `app/assets/live2d/sakiko/`，
  将来换原生插件、或换真机再试 ① 都能直接用；
- 唯一的新风险是 Android WebView 的 WebGL —— **已经验过了，见下。**

### ✅ 路线 ② 的可行性：已实测（决定性证据）

把宿主上的原型服务跑起来（`node server.mjs`，端口 4925），用**模拟器自己的浏览器**
打开 `http://10.0.2.2:4925/`：

**她完整地渲染出来了** —— 蓝发双马尾、白裙、开机对白「……就你?」、
下面两个宿主选项，一切正常（截图留档 `.verify/_webproto3.png`）。

也就是说：

| | 结论 |
|---|---|
| 模型数据 | ✅ 没问题（同一份数据在这台机器上渲染正常） |
| 这台模拟器能不能渲染她 | ✅ 能（走 WebGL 路径） |
| `flutter_live2d` 的平台视图路径 | ❌ 不行（能加载、能跑渲染循环，就是不上屏） |

**所以路线 ② 是确定可行的**，剩下的只是把它搬进 App 里（一个 `WebView` +
JS 桥，去掉浏览器的地址栏外壳）。

## ✅ 转换器（`tools/l2d/convert.py`）

### 为什么可行 —— 查过数据，不是猜

`sakiko/models/adv_..._01.json` 是一个 Unity 工程序列化：`.moc3`（标准）+ 2 张贴图（标准）
+ 一个 7.4MB 的 prefab。prefab 里 766 个节点带这些组件：

| 组件 | 数量 | 里面是什么 |
|---|---|---|
| `CubismParameter` / `CubismPart` / `CubismDrawable` | 210 / 160 / 389 | 参数、部件、网格 |
| `CubismExpressionData` | 28 | **表情**：`{Type, FadeInTime, FadeOutTime, Parameters:[{Id,Value,Blend}]}` |
| （动作资产） | 64 | **动作**：`{MotionName, MotionLength, FadeInTime, FadeOutTime, ParameterIds, ParameterCurves:[{m_Curve:[{time,value,inSlope,outSlope}]}], ParameterFadeInTimes, ParameterFadeOutTimes}` |
| `CubismPhysicsController` | 1 | **物理**：`_rig.SubRigs[{Name, Input, Output, Particles, Normalization}]` + `Gravity/Wind/Fps` |

也就是说：**表情的字段与 `exp3.json` 几乎同名；动作是 Cubism 的 `CubismFadeMotionData`
（摊平的动作，参数 ID 可读）；物理与 `physics3.json` 字段一一对应。**
这不是逆向工程二进制，是**换一层壳 + 一个标准插值转换**。

### 关键换算：Unity Hermite → Live2D 贝塞尔段

```
c1 = (t0 + dt/3, v0 + outSlope(t0) * dt/3)
c2 = (t1 - dt/3, v1 - inSlope(t1)  * dt/3)
```

⚠️ 那个 `1/3` 是 `--slope-scale`，**不是写死的** —— Unity 各版本对 tangent 的缩放约定
不完全一致。对不上的症状是"动作幅度明显偏大/偏小"。

### 产物（`live2d/sakiko/std/`，在 `.gitignore` 之下）

```
sakiko.model3.json · sakiko.moc3 · sakiko.physics3.json
textures/texture_00.png · texture_01.png
motions/*.motion3.json （64，17 组） · expressions/*.exp3.json （28）
```

### 已验证

| 项 | 结果 |
|---|---|
| moc3 | 魔数 `MOC3`，6,558,656 字节（与清单记的大小一字不差） |
| motion3 | `Version 3` · `ParamAngleX` · `Segments: [1, x0,y0, c1,c2,终点 …]`（贝塞尔段格式正确） |
| exp3 | `Type: "Live2D Expression"` · `Parameters[{Id,Value,Blend}]` |
| physics3 | 28 条 rig · 52 输入 · 57 输出 · 83 顶点 · 名字可读（`前髪揺れ`） |
| model3 | `EyeBlink ['ParamEyeLOpen','ParamEyeROpen']` · `LipSync ['ParamMouthOpenY']` · 17 动作组 · 28 表情 |

**还没做的**：把它真正加载起来渲染 —— 下一步是接 `flutter_live2d`（mocVersion 5，
需要插件里带的 Cubism Core 够新，这是下一个要验的点）。

## 现状：原型里的她是怎么渲染的

```
index.html L27   <div id="stage"></div>
stage.js  L120   document.createElement('ournotes-live2d')   → 播放器自己挂 WebGL 画布
stage.js  L127   document.createElement('canvas').id='ringCv' → 环（已移植）
prototype/opus-v2-dir/live2d/sakiko/                          → 模型数据（gitignore）
prototype/opus-v2-dir/vendor/ournotes-live2d.element.min.js   → 自定义播放器
prototype/opus-v2-dir/vendor/live2dcubismcore.min.js          → Live2D 官方 Cubism Core
```

## 关键发现：两个模型不是一种东西

| | `live2d/Hiyori/` | `live2d/sakiko/`（原型在用的那个） |
|---|---|---|
| 格式 | **标准 Cubism 4** | **bdon.moe 自定义封装** |
| 清单 | `Hiyori.model3.json` | `adv_..._01.json`（hash → 资源表） |
| 模型 | `Hiyori.moc3` 443KB | `...moc3.gz` 1.4MB → **解压后 6.5MB** |
| 贴图 | `texture_00/01.png` | 2 张 `.png`（各约 2MB） |
| 动作 | `motions/*.motion3.json` × 10 | prefab JSON（**非标准**）63 个 |
| 表情 | 标准 | 28 个（非标准） |
| 能否直接喂给 Flutter 包 | **能** | **不能，要先转换** |

sakiko 是"BanG Dream! / Our Notes 游戏数据包原样数据"，由自定义播放器
（`ournotes-live2d.element.min.js`）解压 + 解释 prefab。**它的 `.gz` 里装的确实是
标准 moc3 与 PNG**，但动作/表情/物理都在 prefab 那套结构里，得写转换脚本。

## 三条路

### ① `flutter_live2d` + 转换 sakiko  →  原生性能最好，但要写转换器

pub 上有现成插件：[`flutter_live2d`](https://pub.dev/packages/flutter_live2d)
（Cubism **Native SDK** + OpenGL ES 2，Android API 24+ / iOS 13+，
**默认透明背景**，直接塞进 `Stack` 就能和 Flutter 组件混排）。API 够用：
`loadModel` / `startMotion` / `setExpression` / `setParameter` / `setMotionSpeed`，
还自带触摸跟随（眼睛/头跟手指）。

- ✅ 性能与观感最好，跟"Flutter 跨平台"这条主线一致
- ❌ **sakiko 要先转换**：解压 `moc3.gz`、把 63 个动作与 28 个表情
  从 prefab 转成标准 `motion3.json` / `exp3.json`。这是独立的一块活
- ❌ 插件的 Cubism SDK/Core 归 Live2D Inc. 授权，**上线前要过一遍条款**
- ⚠️ 模型文件已在 `.gitignore`（版权红线），进 app 资源要沿用同样处理

### ② WebView 里跑原型那套播放器  →  零转换、像素级一致

把 `index.html` 的舞台部分单独做成一个 HTML，用 `webview_flutter` 嵌进来，
JS 桥驱动 `setCam` / `emote` / `motion`。

- ✅ **同一个播放器 = 渲染结果天然一致**，不用赌第三方实现
- ✅ 63 个动作、28 个表情、物理、呼吸全都在
- ❌ 多一层 WebView：Android 上是平台视图（混合合成的性能坑）
- ❌ 手势与层叠要自己处理（环和挂签得画在 WebView 之上）
- ❌ 违背"Flutter 单代码库"的初衷

### ③ 先用 Hiyori 标准模型顶上  →  今天就能跑通整条管线

用 ①，但先拿 `live2d/Hiyori/`（标准格式）把链路验证通：装配、定位、镜头联动、
动作/表情调用。**换个模型只是换个目录**，sakiko 转换完成后再替换。

- ✅ 立刻可验证，不阻塞其它页
- ✅ 顺带验证"我的相机数学能否正确驱动一个真实模型"
- ❌ 她的脸不对（但这是"数据问题"不是"架构问题"）

## 建议

**先 ③ 再 ①**：用 Hiyori 打通 `flutter_live2d` 这条链路，量一下她落在屏幕上的
位置/缩放与我的 `camera.dart` 差多少，把偏差吃进参数里；等 sakiko 的转换脚本
（另起一块活）做完，换个目录即可。

**② 作为兜底**：如果 ① 的渲染效果和原型差得远（同一模型不同渲染器会有差异），
再退到 WebView —— 那时也已经有 ① 的定位数据可以复用。

无论走哪条，**先要宿主拍板**：这是"要不要为她的模型写一个格式转换器"的取舍，
不是技术能不能做的问题。

## ⛔ 2026-10-12 复盘 —— 下面那节「MuMu · 原生舞台复验」的结论是**错的**，已被推翻

> **一句话：MuMu 上原生 Live2D 完全能跑。之前的「模拟器 emugl 转译层不兼容」
> 是误判；真因在我们这边 —— 构建没把 Live2D 的 shader 打进 APK。**

### 真因链（每一环都有实证）

| 环 | 事实 | 证据 |
|---|---|---|
| ① 插件不打包 Android shader | `flutter_live2d` 1.0.2 只有 `src/main/cpp/.../Shaders/StandardES/*`，`android/src/main/assets` 目录不存在；`build.gradle.kts` 无 assets 映射、`CMakeLists.txt` 无拷贝任务 | 修复前 APK 里 `.vert/.frag` 只有 Flutter 自带的 2 个（`ink_sparkle.frag` / `stretch_effect.frag`） |
| ② 原生加载器只认 APK 资产 | 相对路径从 `assets/FrameworkShaders/<name>` 读；读不到**静默返回空** | `Live2DPal.cpp` 相对路径分支 |
| ③ 没 shader → program = 0，但没人检查 | `LoadShaderProgramFromFile` 失败返回 0，`loadModel` 仍返回 true（`IsLoaded` 只看模型配置解析成功） | `CubismShader_OpenGLES2.cpp` 加载失败分支 + `Live2DModel::IsLoaded` |
| ④ 于是每帧报 GL 0x501 | program 无效 → `glGetAttribLocation` 返回负值 → 传给 `glEnableVertexAttribArray` / `glVertexAttribPointer` | 与 logcat 里 `emuglGLESv2_enc ... GL error 0x501` 的两条调用完全对应 |
| ⑤ 为什么当时没查出来 | 插件把 SDK 日志回调设成空函数，shader 加载/编译失败**一条日志都没有**；`loadModel=true` 被误当成渲染成功 | `live2d_flutter.cpp` `LogFunction` 空实现 |

**所以「无报错日志 + 有 GL 报错」组合并不指向驱动不兼容** —— 它指向「我们的 GL 调用用了无效 program」。
真机（iOS）能跑，不是因为它不是模拟器，而是因为 **iOS 侧用的是 `.metal` 内嵌着色器路径，压根不读这套 APK shader 资产**。

### 修复（2026-10-12，`app/android/app/build.gradle.kts`）

`syncLive2dShaders` 任务把**插件自带**的 `Shaders/StandardES/*.vert|*.frag`（`#version 100`，
与插件 ES2 上下文匹配）同步到生成 assets 的 `FrameworkShaders/`，挂进 `preBuild`，
并 `check()` 必需文件存在（防将来依赖变更导致再次静默漏包）。文件不进仓库（版权红线同模型）。

### 验证（同一台 MuMu · Android 12 / x86_64 · 127.0.0.1:16512）

- 补包前：原生路径每帧刷 `GL error 0x501`，角色不上屏。
- 补包后冷启动：`[stage] 原生舞台就绪（flutter_live2d）`；**`emuglGLESv2_enc` 匹配数 = 0**；
  开机睡姿、唤醒、眨眼/呼吸正常；UI（HUD/字幕/底栏）照常压在她之上。
- 无 WebView 舞台：logcat 不再出现 `[stage-web]`；进程表里没有本 App 的 WebView 沙箱进程。
- 相隔 3s 两张截图差异像素 254754（她在动，不是定格）。
- debug 与 release 两个 APK 都含 36 个 `assets/FrameworkShaders/` 条目。

### ⚠️ 顺带修正的旧结论

- 「旧 AVD / MuMu 的 emugl 栈渲染不了」——不成立，同因（缺 shader）即可解释旧 AVD 症状。
- 「裸舞台探针在 MuMu 上崩进程 = 插件与 emugl 不兼容」——该探针当时同样是缺 shader 的构建，
  崩溃原因需重新评估，**不要再引用它当证据**。
- 「翻回原生的条件 = 插件升级 / 换真机」——真实条件是**把 shader 打进包**，与 GPU 栈无关。

---

## MuMu · 原生舞台复验（2026-10-09 · T7）—— 结论：止损，默认回 WebView

> ⛔ **本节结论已于 2026-10-12 被上一节推翻，保留作排查过程留痕（看「当时是怎么想错的」）。**
>
> **t7 任务按 docs/18 §1.5.1 五关重试路线①，MuMu（127.0.0.1:16512，Android 12，
> 宿主 GPU 栈与旧 AVD 不同）复验到第 3 关（上屏关）触发硬止损线：**
> **loadModel 成功、视图在树、尺寸正确，但角色不上屏——旧 AVD 同款结论在 MuMu 复现，
> 且拿到比旧 AVD 更深一层的新证据。按纪律默认舞台退回 WebView（`kNativeStage = false`
> 收尾），不再沉没成本。**

### 复验过程（对照 docs/18 §1.5.1 五关）

| 关 | 结果 | 证据 |
|---|---|---|
| ① 编译关 | ✅ | CMake 反射覆盖未触发（无 CXX1300）；`:flutter_live2d` 直接编过 |
| ② 挂载关 | ✅ | `kNativeStage` 编译期开关 + 运行期降级（`_stageFallback`）双保险落地；StagePort 抽象（`lib/stage/stage_port.dart`）两实现等价 |
| ③ 上屏关 | ❌ **止损** | 见下方证据链 |
| ④ 层序关 | （无法验证——她没上屏；挂载点保持原位：天幕之后、环场/UI 之前） | — |
| ⑤ 性能关 | （无法验证——同上；无意义帧 gfxinfo 50th=5ms 无参考价值） | — |

### 上屏关证据链（每一步都核实过）

1. **loadModel 成功**（重试机制生效，正好是它设计时要吃的竞态）：
   `[stage] loadModel 第 1 次 → false (LOAD_FAILED Native loadModel returned false)`
   → `[stage] loadModel 第 2 次 → true` → `[stage] 原生舞台就绪（flutter_live2d）`
2. **视图在树、位置/尺寸正确**（docs/18 §1.5.1-3 的 dumpsys 判据）：
   `com.linh18nd.flutter_live2d.Live2DTextureView{3d47bd4 V.ED..... ......ID 0,0-1080,1080}`
   —— 1080×1080 物理 px = 几何相机矩形（boot 相机 s=.64 → 540 逻辑 × 2 DPR），
   **布局矩形复刻相机（`Positioned.fromRect`）工作正常**。
3. **角色不绘制**：boot/lobby 两态截图均无她（`.verify/t7/01~03`），环场/天幕/HUD 等
   Flutter 层全部正常。
4. **新证据（旧 AVD 没抓到过）**：渲染线程**每帧**刷
   `emuglGLESv2_enc GL2Encoder s_glEnableVertexAttribArray / s_glVertexAttribPointer
   → GL error 0x501 (GL_INVALID_VALUE)` —— 插件的顶点属性提交在 MuMu 的 emugl
   转译层上**每次都失败**。即：不是合成/层序问题（视图在画），是 **GL 调用本身
   被转译层拒绝**（shader attrib 布局/数量与 emugl 的兼容性问题）。这解释了旧 AVD
   的同症状（当时没有这一层日志）。
5. 已排除项：插件模型缓存（`run-as ... rm -rf cache/flutter_live2d_models` 清过再试）、
   模型数据（同一份数据 WebView 路线正常）、Impeller（旧排查已证无关）。

### 止损处置（已落地）

- `main.dart kNativeStage = false` —— 默认走 WebView；原生实现**全量保留**
  （`Live2DStage` 几何相机 + `StagePort` 双实现 + `stage_port_test.dart` 12 例桥接表
  一致性单测），**翻回 = 改一个常量**。
- 恢复 `emote('sad')`（`_beginFail`）与接单 `nod`/结算 tier 情绪/暴击 `surprise` 挂在
  `StagePort` 上——两条路线通用，WebView 走原型播放器自己的同名表。
- 相机标定接口已备好未执行（她没上屏没有标定对象）：`tools/ref/calib_alpha.py`
  （alpha 包围盒/背景亮度阈值法，**禁截图轮廓量测**）↔ `Live2DStage.StageCalib`
  三常数（kSize/dx/dy），`stage_port_test.dart` 已钉死大厅矩形的数学
  （92% 屏高、顶 4.5% 底 96.5%）。

### 翻回原生的条件（给未来的自己）

1. `flutter_live2d` 插件升级（关注其 GL 初始化/attrib 绑定的修复），或
2. 换非模拟器 GPU 栈（真机）验证，或
3. MuMu 更换图形转译模式后复测。

复验动作：`kNativeStage = true` → `adb shell run-as com.systempanel.app rm -rf
cache/flutter_live2d_models`（换数据/清缓存步骤）→ `flutter run -d 127.0.0.1:16512`
→ 大厅截图 + `dumpsys activity top | grep Live2DTextureView` + logcat 查
`[stage]`/GL 0x501 → 上屏则跑 `tools/ref/calib_alpha.py` 标定 `StageCalib`。

### attempt 2 追加（2026-10-09 深挖）—— 二分定案：责任在插件，不在我们

- **裸舞台二分实验**（`SysApp.kStageBareProbe`，诊断开关保留、默认 false）：
  只挂 `Live2DStage` 的裸页（无天幕/环场/ShakeLayer/任何 Flutter 层，
  仅一块对照文字确认 Flutter 在画）→ **依旧全黑，且应用进程退出回桌面**
  （`.verify/t7/05~06`；flutter run 报 "Lost connection to device"）。
  → **合成/层序/我们 App 的树全部排除**：flutter_live2d 1.0.2 在 MuMu 的
  emugl GL 转译层上不仅不渲染，裸跑还会崩进程。
- **插件源码核查**（pub cache 1.0.2）：Android 侧 = `PlatformViewLink` +
  `initExpensiveAndroidView`（HC 混合合成）+ 自建 `Live2DRenderHub` 线程
  （独立 EGLContext GLES2 + TextureView SurfaceTexture）+ C++ 渲染
  （`Live2DBridge.nativeOnDrawFrame`）。GL 0x501 出自 C++ 顶点提交，
  Dart/Kotlin 层无任何开关可绕；Cubism Core 6.0.1 正常加载
  （logcat：`Live2D Cubism SDK Core Version 6.0.1`），无 shader 编译日志。
- **归因定案**：flutter_live2d 1.0.2 的 C++ 渲染管线与 MuMu 的 emugl GL
  转译层不兼容（旧 AVD 同为 emugl，同因）。修它 = 改插件 C++（workspace 外、
  pubspec 锁 1.0.2），**不在任何任务 scope 内**。
- 裸探针开关（`SysApp.kStageBareProbe`）默认 false 且不影响正常路径，保留供复验。

## ✅ iOS 真机轮（2026-10-10 深夜 · Mac + iPhone 15 Pro Max）—— 原生路线复活成功

> 宿主接好 iOS 真机（TK · iPhone 15 Pro Max · iOS 27.0.1 · Developer Mode 开），
> 按本文档「翻回原生的条件 2」（换非模拟器 GPU 栈）复验。**五关全过，`kNativeStage = true`
> 收尾，WebView 降级路径保留未动。** 证据图 `app/.verify/ios-t0/01~05`（未入库）。

### 环境（这台 Mac 从零搭的）

- Flutter 3.47.6 stable（arm64 zip，SHA256 校验过）@ `~/development/flutter`；
  git 上游切 TUNA 镜像（`FLUTTER_GIT_URL`），pub/storage 走 flutter-io.cn —— 与
  Windows 机同版本同源，`~/.zshrc` 已写好（`# >>> flutter-cn` 块）。
- CocoaPods 1.17.0（brew）。Xcode 27.0 本来就有。
- **签名**：`Apple Development (1831353087@qq.com)` 证书在钥匙串，但 Xcode
  Accounts 没登录 → 自动签名报 "No Accounts"。宿主在 Xcode → Settings →
  Accounts 登录一次后，`DEVELOPMENT_TEAM = VH546YKMN4` 已写进 pbxproj
  6 处（Runner×3 + RunnerTests×3 配置），真机描述文件自动生成。
- ⚠️ CLI 坑：`flutter analyze/test` 会在 shell 里隐式 `dart pub get --example`，
  **不带 `PUB_HOSTED_URL` 会卡死在 "Downloading packages..."**（直连 pub.dev 不通）。
  所有 flutter 命令都要带国内源环境变量。

### 五关

| 关 | 结果 | 证据 |
|---|---|---|
| ① 编译 | ✅ | `flutter build ios --no-codesign` 39s；pod install 1.2s（插件走传统 CocoaPods，不支持 SPM，警告无害） |
| ② 挂载 | ✅ | `kNativeStage = true`（main.dart 常量，A/B 开关保留） |
| ③ 上屏 | ✅ | **她完整渲染**：loadModel 第 1 次就 true（模拟器的加载竞态在真机没出现）、`Live2D Cubism SDK Core Version 6.0.1`、Impeller(Metal) 并存无冲突 |
| ④ 层序 | ✅ | 天幕→她→环场/字幕/HUD/底栏，与原型 `#bg→#stage→#ui` 一致（`ios-t0/04_lobby_final.png`） |
| ⑤ 性能 | ✅ | 见下 |

### 相机标定（裸探针 + alpha/亮度阈值包围盒，430×932 逻辑）

- `kStageBareProbe=true` 裸页截屏 → `tools/ref/calib_alpha.py --png ... --logical 430x932 --mask 0,0,140,44`
  （mask 是为了抹掉裸页左上角「FLUTTER OVERLAY」对照字，否则包围盒被它顶到 12,9）。
- 实测：**top 4.5% / bot 96.5% / 占屏高 92.0% / 中心 x=215.0** —— 与原型目标
  （大厅 s=.92、syF=.505）逐项吻合 → **`StageCalib` 保持 kSize=1.0 / dx=0 / dy=0 不动**，
  布局矩形复刻相机的数学在真机上天然成立，无需标定。
- 顺手修了脚本的 dx/dy 公式 bug（比例当像素减，输出大 3~4 个数量级的垃圾值）；
  另加 `--logical` / `--mask` 两个参数。MuMu 旧基准用法不变。

### ⑤ 性能（profile 模式 · VM Service timeline · 稳态 3s 窗口）

| 指标 | 数值 | 对照 |
|---|---|---|
| 帧率 | **60.0 FPS 锁满**（180 帧/3s） | WebView 基线（MuMu 模拟器）中位 89ms ≈ 11FPS |
| UI 线程帧 | p50 **0.52ms** / p95 1.08ms | Dart 侧近乎空闲，动画都在插件渲染线程 |
| 平台视图合成 | `PlatformViewsController::SubmitFrame` p50 **2.2ms** / p95 2.5ms | 她的 EAGL 纹理进 Flutter 帧很便宜 |
| 帧耗时大头 | `WaitForNextDrawable` p95 15.6ms | = vsync 等待（空闲），非算力瓶颈 |
| 进程 | 无 WebView 沙箱进程 | WebView 路线多 225MB |

达标线（≤24ms 中位）远超。⚠️ 备注：iPhone 15 Pro Max 是 ProMotion 120Hz，
Info.plist 有 `CADisableMinimumFrameDurationOnPhone=true`，当前锁 60 是插件
自建 CADisplayLink 渲染循环 + Flutter 帧调度共同节拍的结果，60 已达设计帧率
（原型即 60fps 口径），不必追 120。

### 遗留（不阻塞，记录在案）

1. **profile 冷启语音起播超时**：`[sfx] 起播超时（丢弃这一发）key=syl:pleased`
   ×2 + audioplayers 的 `SWIFT TASK CONTINUATION MISUSE` 警告 —— 首播资源未
   就绪被按设计丢弃，debug 模式未见；后续真机轮再看，非舞台范畴。
2. WebView 降级路线未在 iOS 真机实测过（原生已活，暂时用不上；ATS 放行已配好）。
3. `flutter_live2d` 需要跟进 SPM 支持（Flutter 未来版本会硬性要求）。

### 结论

**（2026-10-12 更正）** 当时写的「MuMu/旧 AVD 的『不上屏』只对模拟器 emugl 转译栈成立」
**是错的** —— 真机（A17 Pro 硬件 GPU + EAGL）能跑是因为 **iOS 侧走 `.metal` 内嵌着色器**，
不依赖 APK 里的 `FrameworkShaders/` 资产；Android 侧缺的是 shader 打包（见本文
「2026-10-12 复盘」节），与 GPU 栈无关。事实是：真机上 flutter_live2d 1.0.2
一次加载成功、渲染、合成、性能全部正常；**MuMu 补齐 shader 后同样正常**。
原生路线（①）转正，WebView（②）退居降级备份 —— 这个结论本身不变。

## iOS 真机轮 · 表演补完（2026-10-11）—— 她为什么是"一张会眨眼的图片"

> 宿主验收：上屏 ✅ 但**不动**——待机动作/呼吸没了，开机也不睡、不睁眼、不打招呼。
> 对照 docs/22 R5「Mac 轮验收项（写死防丢）」逐项补完。根因与修法如下。

### 根因（插件 iOS 侧两处硬编码，全部用**数据层**绕开，不改插件）

`flutter_live2d 1.0.2` 的 iOS wrapper（`Live2DWrapper.mm`）：

1. **待机兜底组名写死 `"Idle"`（大写 I，Hiyori 约定）**：
   `Update()` 里 `if (_motionManager->IsFinished()) StartMotion("Idle", 0, PriorityIdle)`，
   而 sakiko 的 17 个组全小写 → `GetMotionCount("Idle")==0` → **静默 return**。
   且 `SetLoop(true)` 只对字面 `"Idle"` 组生效。
   → 我们 `startMotion('idle')` 播**一遍**就停，兜底每帧找不存在的组无声失败。
   症状：开场动十几秒 → 彻底冻结，只剩眨眼 + 物理余晖（4 秒差分实测仅 0.4% 像素变化，
   躯干 0 变化）。
2. **`SetParam` 单帧即失效**：wrapper 的 Update 是标准 Cubism
   `LoadParameters→motion→SaveParameters` 循环，method channel 进来的 SetParam
   下一帧就被 LoadParameters 覆写 → 开机闭眼/抬眼皮没法靠 param() 持续驱动
   （docs/22 R5 当初假设 param() 可用，实测不成立）。

### 修法（转换器数据层，零插件补丁）

- **`"Idle"` 别名组**：`convert.py` 在 model3.json 的 Motions 里加
  `"Idle": [mtn_idle01_C]` —— 插件的循环与兜底逻辑**按数据对上**：
  加载即播 `Idle`(循环=真) 做常驻基底（对应原型 stage.js L167
  `playMotion(defaultMotion, {loop:true})`）；待机池小动作播完后兜底自动回到基底。
  17 个语义组原样不动（桥接表零影响）。
- **4 个 `exp_sys_*` 合成表情**（转换器生成，Blend=Overwrite）：
  表情在管线里于 eyeblink **之后**应用，可持续覆写眼部/头部参数——
  相当于原型 `faceT` 脸层的原生等价物，绕开 SetParam 单帧失效：
  - `exp_sys_sleep`：眼 0 + 低头 AngleY -16 + Az 2 + 眼球下移 + 脸颊 .1
    （原型 FACES.sleep 原值）+ `speed(0)` 动作停住 —— 开机睡姿
  - `exp_sys_wake`：眼 0 + 头回正（原型 wake() 先抬头 450ms）
  - `exp_sys_lid35` / `exp_sys_lid05`：眼皮 .35 / .05（原型睁眼前颤两下，
    FadeIn 0.06 保证 140/120ms 的拍子不被 0.5s 默认淡入糊掉）
- **SRC 回退**：本机原型目录为空，转换器 SRC 自动落到 `app/assets/live2d/sakiko_orig/`
  （prefab 全套已验证：766 节点/贴图/moc3.gz）。

### 接线（main.dart / stage 层，对照原型 flows.js wake() L71-99 与 _greet）

- boot 舞台就绪且 moment==boot → `port.sleep()`（睡整场）
- `_wakeSequence`：亮帧/音效/震动后插**睁眼编排** —— 抬头 450ms → lid .35 140ms →
  lid .05 120ms → neutral 睁眼 → **欢迎手势 `act('present')`（kime）** → 逐环点亮 →
  问候台词 + `mood(back10m?'smug':'neutral')`（原型 _greet 的情绪档）
- 待机池节奏对齐原型：`rand(7,15)s`（原为固定 ~8.1s）；睡眠期间池子暂停
- WebView 路线：sleep/wakeEyes 在 StagePort 上为 no-op（降级路线行为不变，留档）

### 明确不在本轮（记录防丢）

- 视线跟手指（原生 view 被 IgnorePointer 包着，插件无 drag API，需插件补丁）
- 池子动作的 L/R 变体随机（现固定 index 0，C 向）
- 口型同步（TTS 未接原生路线）

## iOS 真机轮 · 几何与清晰度（2026-10-11 深夜）—— 她被裁 + 有点糊

> 宿主连续两条验收：「头顶以及脚都被截断了，显得太大了」→「有点模糊」。
> 两条都查到底了，结论完全不同：**裁切是真 bug（已修）**，**糊是素材物理上限（无 bug）**。

### 一、裁切/太大：根因是「视图宽高比」，不是矩形大小

插件 iOS 侧把模型塞进视图的规则（`Live2DWrapper.mm` L615 / L658）：

```objc
if (w > h) _model->GetModelMatrix()->SetHeight(2.0f);
else       _model->GetModelMatrix()->SetWidth(2.0f);   // 方形/竖视图走这里
```

即**非宽视图按「画布宽度」塞满视图宽度**。sakiko 的画布是 **6000×9000（宽:高 = 2:3）**，
画布高 = 3.0 个世界单位被塞进只有 2.0 单位高的**正方形**视图 ⇒
**她恒定被上下各裁掉 25% 视图高**。

⚠️ 关键推论（踩了两小时的坑）：**视图是正方形时，矩形调多大都没用** ——
可见的世界范围只由视图**宽高比**决定，与尺寸无关；而且旧标定量到的
「92.0% 完美匹配」是**量了裁剪框本身**（裁掉的内容让可见轮廓恰好填满矩形，
`calib_alpha.py` 量到的就是这个框）—— 又一种「拿噪声当信号」，与 HANDOFF
警告的旧 AVD 轮廓量测同源。宿主眼睛比指标准。

**修法（`Live2DStage.stageRect`）**：舞台矩形保持画布比例（宽 = 高 × 2/3），
此时可见范围 = 整张画布 → 她完整可见；实测 **顶 4.6% / 底 96.5% / 占屏高 92%**，
与原型目标一致，`StageCalib.kSize` 仍是 1.0（无需标定）。
副作用（正向）：她从「被裁掉的 1.5× 放大」变回设计尺寸，脸小了 1.5 倍 →
顺带更清晰（旧版瞳孔横向跨度 198px → 现在 131px）。
`stage_port_test.dart` 新增「矩形必须是画布比例」用例钉死这条。

### 二、糊：不是渲染链路，是素材分辨率上限

排查链（每步都有量化证据）：

| 假设 | 实验 | 结论 |
|---|---|---|
| 显示链路/FBO 分辨率低 | 量边缘过渡宽度：Flutter 文字 **1px**、她的强边也 **1px** | ❌ 排除（FBO 是原生 3×） |
| 贴图被插件降采样 | 贴图 2048² < GL_MAX_TEXTURE_SIZE，无 downscale 日志 | ❌ 排除 |
| 贴图分辨率不够 | 贴图里两眼间距 **71px** vs 屏幕 **111px** ⇒ 放大 **1.56×** 采样（几何修正前是 2.3×） | ✅ **就是这个** |
| 加大贴图能救 | 2× Lanczos 上采样（2048²→4096²，`convert.py --tex-scale 2`） | ⚠️ 高频能量只 **+3%**（插件 mipmap 链按缩小倍数选级，把有效细节归一化）；宿主主观验收「更糊」、显存 4× ⇒ **退回 2048²** |
| mipmap 预模糊 | 打本机补丁关 mipmap（`tools/l2d/patch_plugin.py`，两处：wrapper + `CubismShader_OpenGLES2.cpp:1101`） | ❌ 宿主主观验收「**变差了**」（缩小时无 mip 链 → 走样/噪点感）⇒ **补丁回滚，插件保持原版** |

**定论**：与原型**同一份 2048² 素材**在 2796px 高的大屏上被放大 ~1.56× 采样，
这是素材侧的上限，不是渲染 bug —— 原型当年同样受此限制。真要提升只有两条路：
① **换 AI 放大过的素材**（Real-ESRGAN 等"真加细节"，Windows 机 ComfyUI 现成管线）；
② 把她显示得更小（放弃 92% 屏高框架）。补丁脚本与 `--tex-scale` 选项都留着备用。

### 三、本轮顺带确认/修好的

- **大厅「她不动」**：基底 `mtn_idle01_C` 实测振幅只有 0.3~2.9°（是游戏里的
  「静立呼吸」待机，本来就这么安静）；「活」的感觉来自**待机池动作**
  （`look` 头转 32° / `kime` 抬头 28°，日志已确认每 7~15s 发一次，与原型
  `stage.js` L411 `rand(7,15)` 同拍）⇒ 机制正常。
- **开机睡姿 / 唤醒编排 / 欢迎手势**：全部真机验收通过（宿主：「还没唤醒的时候
  是闭眼的」「看到了这些动作」）。
- 取证手法留档（下次直接用）：`xcrun devicectl device capture screenshot` 截屏；
  `devicectl device copy from --domain-type appDataContainer` 取 App 沙箱文件
  （用它抓出插件缓存里的旧 model3.json，是"她一点没变"的定案证据）。

## iOS 真机轮 · 「她像一个死人」的根因（2026-10-11 凌晨）—— 全部动作都没加载

> 宿主验收：「主界面它像一个死人一样，原型上戳它都有反应的，现在这些反应都没了」。
> 查到底了：**从第一天起，她的 64 个动作文件全部加载失败** —— 她从来没播过任何
> 一个动作，屏幕上只有眨眼（Cubism 眨眼层）与物理余晖。**两个转换器 bug**：

### 一、Segments 布局：类型标记的位置写错了

`CubismMotion::Parse` 与 `CubismMotionJson::HasConsistency` 的约定是
**「初始点 + 每段一个类型标记」**：

```
[x0, y0,  类型, 数据…,  类型, 数据…, …]
```

而旧转换器写的是 `[类型, x0, y0, 数据…]`（类型只写一次、且放在最前面）。
官方样例 `Hiyori_m01.motion3.json` 用同一套算法算得 135/374 = 它声明的
Meta ✅ —— **拿官方文件当尺子**才定位到（我自算的 1+段数 是错的）。

### 二、Cubism 私有 JSON 解析器的脾气：数字后面只能是 `,` 或换行

`CubismJson::ParseNumeric`（`Utils/CubismJson.cpp` L210-283）：

```cpp
case '\n': case ',':  { *outEndPos = i; ...  return CSM_NEW Float(ret); }
default:              { _error = "non-numeric charactor found"; return NULL; }
```

**它不吃 `]` / `}` / `e`**。旧转换器用 `separators=(",",":")` 压成单行 →
每个 `Segments` 数组的**最后一个数字紧跟 `]`** → `IsValid=0` → `Parse` 提前
返回 → `CubismMotion::Create` 回 null → `LoadMotion` 报
`[CSM][E]Failed to create motion from buffer`，**所有动作静默不播**。
（`1e-06` 这类科学计数法同理，physics3 也中招 → 头发物理一直是坏的。）

表情为什么没事：exp3.json 最后一个值恰好是字符串（`"Blend"`），数字后面
都有逗号 —— 所以「闭眼/睁眼/欢迎表情」这些**看起来正常**，掩盖了动作全废。

**修法**：转换器自写序列化（`_json_lines`）—— 与官方同款多行排版、`%.6f`
固定小数位（不吃科学计数法），加 `cubism_json_safe` 自检（数字后必须是
`,`/换行，否则直接 `SystemExit`，不允许再回归）。

### 三、取证链（这次能挖到底靠它，下轮照用）

1. `xcrun devicectl device copy from --domain-type appDataContainer
   --domain-identifier com.systempanel.app --source …` —— 把设备上插件
   解压缓存/产物拉下来逐字节对比（查出过「旧 model3.json 被无限复用」）。
2. **给插件打临时诊断补丁**（改本机 pub 缓存，`fprintf(stderr, …)`）：
   wrapper 的 `StartMotion` 打印**哪个动作**加载失败；框架的
   `CubismMotion::Parse` 打印 `IsValid`、`HasConsistency` 打印
   「算得值/声明值」。日志直接给出答案，比猜快一个数量级。
   ⚠️ 两个缓存目录（`pub.dev` / `pub.flutter-io.cn`）**必须都改**，
   构建用哪个由 `ios/.symlinks/plugins/flutter_live2d` 指向决定；
   改完还要清 `DerivedData/…/Pods.build` 强制重编（否则增量构建不重编）。
   用完从**重新下载的 pub 包**逐字节还原（别手改回去）。
3. `xcrun devicectl device capture screenshot` + 逐带像素差分：
   量化「她到底动没动」——修复前 发/脸 ~1,000 px/2s（眨眼级），
   修复后 **9,143~43,721**、躯干 **71,607~284,904**。

### 四、顺带修好的（宿主另一条验收：「戳它有反应」）

- **戳她**（`main.dart _poke`）：点在她身上 → 越戳越恼（第 1~3 戳 tsun +
  `poke` 动作 → 第 4 戳 annoyed → 第 5 戳起 cold + `fluster`），台词是
  content.js L319 那五句；音效 `poke`（新增烘焙，audio.js L130 原参数）+
  震动 `[8]`；20 秒不戳连戳计数归零。命中判定照抄原型 `Stage.hit` 的
  宽度曲线（头窄→肩宽→裙摆再宽，**故意宽松**，别收紧）。
- **她的头/眼睛跟着手指**（原型 `Stage.pointer` + `look('pointer')`）：
  `Live2DStage` 的 `IgnorePointer` 改成**放行触摸**（插件平台视图自带
  drag 跟随），「戳她」那层改成 **translucent 的 `Listener`** —— `Listener`
  不参与手势竞技场，所以两边都能收到事件；UI（底栏/按钮）在她之上，不受影响。
  ⚠️ 坐标必须用 `e.position`（全局）—— 用 `localPosition` 命中判定永远失败
  （踩过一次：戳她毫无反应）。

## iOS 真机轮 · 待机三修（2026-10-11 凌晨 · 宿主验收三条）

> 宿主：「首页待机的时候不会眨眼睛」「待机动作太少」「从唤醒到主界面转场太过突兀，
> 像是直接切换一样……live2d 是直接过去的, 应该有个转场动画」。三条都落地了。

### ① 不眨眼：表情把眼睑参数钉死了

管线的应用顺序是 motion → drag → **eyeblink** → **expression** → physics
（`Live2DWrapper.mm` 的 Update），表情在眨眼**之后**每帧覆写 —— 而 prefab 里
**27/32 个表情**都把 `ParamEyeLOpen/ROpen` 用 `Overwrite` 钉住（含大厅待机那张
`exp_idle01`，值 1.0）⇒ 眨眼被每帧盖掉，她永远睁着眼。

**修法（转换器，数据侧）**：只剥掉「**值恰好 = 1.0 且 Overwrite**」的钉死 ——
1.0 就是"正常睁眼"，相对眨眼**无操作**，删掉不丢任何表情语义；
cry 的 0（闭眼哭）、smile02 的 0（眯眼笑）、shy 的 0.8、annoyed 的 0.7、
surprised 的 1.5（瞪大）**全部保留**（那些表情生效期间不眨眼是对的）。
修复后仍有 16 个表情带语义眼态、其余恢复眨眼。

### ② 待机动作太少：组内永远只播 index 0

原型 `MOVE[verb].m` 是**数组**（C 中 / L 左 / R 右 三向随机挑），待机池同理；
我方池子里 6 个组固定 `index: 0` ⇒ 实际只出 6 个动作。
**修法**：`Live2DStage.motionCounts`（变体数表，`stage_port_test` 拿转换产物逐项核对）
+ 池子/手势都改成**组内随机取变体** ⇒ 可用变体 **27 个**（4.5 倍）。
日志可见：`待机池动作 → smile[1]`（下标不再恒 0）。

### ③ 唤醒→主界面「直接切换」：三处硬跳 + 平台视图尺寸动画的落点

跳变点（原来全是布尔门控 / 常量切换）：
- `Hud` / `Dock`（底栏）/ 对话入口钮 —— `visible: lobby` 一翻就**硬出现**
- 环场亮度 `dim: boot ? .34 : 1` —— 34% **直接跳**到 100%
- 相机 `CamSpring` 本来就是弹簧（**不是** snap，这条没问题）

**修法**：新增「唤醒过场」进度 `_wakeFade`（900ms ease-out），唤醒那一刻起跑：
界面三层包 `_WakeFade`（0→1 淡入）、环场亮度 `_ringWakeDim = .34 + .66×ease(t)`
连续推上去；并在切页那一拍**补一次 320ms 青蓝过渡**（对应原型 `Stage.glitch(420,1)`
那一拍）—— 因为 Live2D 的平台视图**尺寸一变就要重建 FBO**（插件
`layoutSubviews` → `recreateFramebufferOnMainThread`：排空渲染队列 + 主线程重配
renderbuffer），推镜头那段她渲染会变稀、落点很像"跳"，必须用一拍过渡把落点盖住。
⇒ 「睁眼 → 环亮起 → 界面浮上来 → 落进待机」现在是一段连续推移。

### 本轮验证手法（可复用）

宿主睡着没法点门禁，用 **VM Service 临时挂一个 debug 扩展**远程触发唤醒：

```dart
// 仅本机验证用，验完删（别入库）
developer.registerExtension('ext.sys.wake', (m, p) async {
  _wake(); return developer.ServiceExtensionResponse.result('{"ok":true}');
});
```
```bash
curl "$B/getVM"                                   # 取 isolateId
curl "$B/ext.sys.wake?isolateId=$ISO"             # 触发（⚠️ 必须带 isolateId，
                                                  #    否则 Method not found）
```
配合 `devicectl device capture screenshot` 连拍。⚠️ 宿主离开屏幕会自动调光，
亮度对比要先用「她身上最亮 1% 像素」做标尺归一化（本次 247→149 就是调光，
不是状态坏了）。

### ③ 追加：淡入**必须在 Hud/Dock 内部**做（我踩的 ParentDataWidget 坑）

第一版我把 `Hud` / `Dock` 用外层包装件（`_WakeFade` → `AnimatedBuilder` → `Opacity`）
包起来做淡入 —— 真机直接抛 **`Incorrect use of ParentDataWidget`**（HUD 与底栏各一次）：
这两个组件 `build` 的**顶层就是 `Positioned`**（ParentDataWidget），它要求从自己到
`Stack` 之间**只有不产生 RenderObject 的 widget**，而 `Opacity` 是 RenderObject ✗。

**正确做法**：把动画**传进组件内部**（`Hud(fade: …)` / `Dock(fade: …)`），由它们在
`Positioned` 之内套 `AnimatedBuilder`+`Opacity`；`_WakeFade` 只保留给
「对话入口钮」那处（它的 `Positioned` 在包装件**外面**，安全）。
回归网：`test/lobby_test.dart` 新增用例——在 `Stack` 里挂 `Hud`/`Dock` 跑一遍淡入，
断言「中途出现中间不透明度」且 `takeException()` 为空（框架异常会被 flutter_test 记为失败）。
⚠️ 两条测试细节：Ticker 要先 `pump()` 起跑一帧再 `pump(300ms)`；**别用 `pumpAndSettle`**
（Hud/Dock 有常驻呼吸动画，永远 settle 不了）。

### ④ 追加：键盘两修（2026-10-11 · 宿主：「换出键盘之后, 点击系统内应用,
键盘无法正常收缩回去」）

Flutter 里键盘不会像 web 那样"点空白自然失焦"，必须显式 unfocus：
- **点舞台/空白处**（`_onStageDown`，覆盖大半屏的 translucent Listener）→
  `FocusScope.of(context).unfocus()`；注意**不能**挡 TextField 的焦点
  （translucent Listener 不参与手势竞技场，TextField 在上层照常拿焦点）。
- **开投影面板**（系统/档案/补给）/ **取消换目标** / **提交换目标** →
  同样 unfocus（键盘别压在面板上）。

复现受限说明：远程 `requestFocus` 在 iOS 上**不保证弹出软键盘**
（诊断日志确认焦点已生效但键盘未出现）⇒ 键盘弹起态的复现需要真手点输入框。
修好的行为（点空白收键盘）已并入 `_onStageDown`。

---

## Android（MuMu）· 「比原始数据网页模糊」逐层排查（2026-10-12）

> 宿主原话：「为啥我感觉这个比较模糊，右边是原始数据的网页」——对照图是
> MuMu 窗口里的 App（全身）vs 模型浏览网页里的人脸特写。
> 证据留档：`.verify/l2d-clarity/`（对照图、A/B、量测脚本产物，不入库）。

### 一、先把"她是不是本来就该这么大"钉死（尺寸账）

| 量的是什么 | App（MuMu 780×1688 物理） | 原始播放器（同屏同尺寸复刻） |
|---|---|---|
| 她占屏高 | 1318 px（78%） | 1376 px（81.5%） |
| 两眼间距 | **68.3 px** | ≈ 82 px（同款播放器、同一份数据） |
| 参考网页里两眼间距 | — | **386 px ≈ App 的 5.7×** |

⇒ 参考网页是**人脸特写**：那边把她放大 5.7 倍显示。**尺寸差占了"觉得糊"的一大半**，
这一条不是 bug（她在手机上就该是全身构图）。

### 二、真正的渲染差异：缩小采样 + mip 预模糊

| 环 | 事实 | 证据 |
|---|---|---|
| ① 素材没被压 | App 两张贴图 vs `sakiko_orig/` 原始 PNG | **sha256 完全一致** |
| ② 贴图被缩小采样 | 贴图里虹膜 ≈ 60~77 px，App 里 ≈ 30 px | 缩小 **≈ 2×** |
| ③ 插件强制 mipmap 过滤 | `MIN_FILTER = GL_LINEAR_MIPMAP_LINEAR` | Android 两处：`Live2DTextureManager.cpp:44` + `CubismShader_OpenGLES2.cpp:1113`（**绘制时每张 drawable 重设**，只改前者会纹理不完整→黑剪影） |
| ④ 原始数据自己的采样配置 | `mipCount: 1` / `m_FilterMode: 1`（= LINEAR，**没有 mip 链**） | `sakiko_orig` prefab 的贴图节点 |
| ⑤ 于是缩小 2× 时 GPU 选到 **mip1**（1024²） | 等于先把贴图糊一半再采样 | ①②③ 的直接推论 |

**同机 A/B（只改这两处，其余不动）**：

| | 静态面膜窗口高频能量 | 运动中 8 帧均值 | 观感 |
|---|---|---|---|
| 现状（mipmap） | 23.96 | 11.2（13.9→8.9） | 柔和、无锯齿 |
| 关 mipmap（LINEAR） | **30.94（+29%）** | **16.3（+45%）** | 明显更利，细线（睫毛/发丝）有轻微锯齿 |

（运动对照产物：`.verify/l2d-clarity/motion_strip_mip_vs_linear.png`、
`motion_ab.gif`；两段都是「戳一下 → 连拍 8 帧」，帧号对齐并排，不是同一段动作，
看的是**质感**不是逐帧对齐。）

⇒ 这就是"我们的原生路径 vs 原始播放器"的**唯一实质差异**：原始数据本来就没开 mip 链，
我们这条路径开了；在**缩小**场景下 mip1 会把笔触吃掉。**放大**场景（例如宿主参考的
那个网页、或把她推近的 `talk` 机位）两边都不选 mip，所以那时看不出差别。

### 三、怎么切（一条命令）

`tools/l2d/patch_plugin.py` 现在两端都能打（默认 `--target all`）：

```bash
python tools/l2d/patch_plugin.py --target android   # 关 mipmap → 更利（当前状态）
python tools/l2d/patch_plugin.py --revert           # 还原原版 → 更柔、更稳
```

- 只改本机 pub 缓存，**不入库**（版权红线同模型数据）；`flutter pub cache repair`
  后要重跑。
- 改完 `flutter build apk --debug --target-platform android-x64` + 安装即可（增量约十几秒）。

### 四、取舍（待宿主定）

- **LINEAR（当前）**：与游戏原始数据一致、明显更利；代价是**缩小 2× 时细线会走样**，
  运动（呼吸/转头）时可能有轻微蠕动感 —— 2026-10-11 iOS 上宿主曾判过「变差了」，
  彼时 iOS 渲染尺寸更接近 1:1，走样更刺眼；Android 这边还被 1.14× 超采样摊薄了一点。
- **mipmap（原版）**：稳、不闪，但比原始数据软一档。
- ⚠️ 这条**不是"哪个对"的技术题，是观感取舍** —— 交给宿主在真机上看运动中的表现再定。

**同段编排的录屏对照（2026-10-12 补，产物 `.verify/l2d-clarity/`）**：
`record.sh` 录同一段「唤醒 → 待机 → 【委托】推近(talk) → 【等会儿】拉回」，
只换过滤、其余（数据 v9 / 编排 / 机位）完全一致：

| 产物 | 看什么 |
|---|---|
| `face_zoom_ab.mp4` | 待机段**脸部 2× 并排**：左=mipmap、右=LINEAR → 差别最清楚的地方 |
| `full_ab.mp4` | 整段编排**原生分辨率并排**（1560×1688）：看推近/拉回时各自的稳定度 |
| `closeup_ab.png` | talk 机位（推近）定格并排 → **两边几乎一样** |

⇒ 结论坐实：**差别只在"她小的时候"**（缩小采样）；推近到 talk 机位时贴图在放大，
mip 链不参与，两种设置**看不出区别**（格纹裙线条的锐度完全一致）。所以取舍的本质是
"大厅全身那一档，你要利还是要稳"。

### 五、顺带查实：blend-mode 离屏 FBO 那条**对本模型不成立**（已排除）

原怀疑：SDK 在 `model.IsBlendModeEnabled()` 为真时会把整个模型先画进
`_modelRenderTargets[0]`，而那张 FBO 的尺寸来自 `CreateRenderer(w,h)`
（= **加载那一刻的视图尺寸**）；插件 `nativeOnSurfaceChanged` 只改 viewport/投影/
模型矩阵、**不调 `SetRenderTargetSize`** —— 若成立，切族（1.05↔1.70）后模型就是
用旧尺寸 FBO 放大贴上去的（越推越糊）。

**实测（2026-10-12 · MuMu）：在 `CubismRenderer_OpenGLES2::BeforeDrawModelRenderTarget`
里打一次性日志（打完即撤，不留痕）：**

```
SysL2DProbe: [probe] viewport=1181x1772 target=1181x1772 fboCount=0 blendMode=0 offscreenCount=0
```

- `blendMode=0` ⇒ `IsBlendModeEnabled()` 为假，`fboCount=0` ⇒ **离屏 FBO 路径根本没走**，
  模型直接画进平台视图 ⇒ 这条隐患对 sakiko **不成立**（那条"FBO 尺寸不更新"仍是真的
  代码事实，只是没触发；将来换用带 blend mode 的模型要重验）。
- 顺带钉死了几何账：**平台视图 = 1181×1772 物理像素**（= 逻辑 590.5×885.8 × DPR 2），
  与 `family 1.05` 的推算**完全一致**；`Transform.scale(0.876)` 之后她占屏 1552 px。
  即整条链路只有**一次**重采样（贴图→视图），合成那一步是超采样缩小、不是放大。
  ⇒ 「糊」这件事**只可能来自贴图缩小采样**，与合成/FBO 无关（这也解释了为什么
  1.14× 超采样没能救回细节：mip1 已经把细节吃掉了）。

---

## 六、「默认这张脸不对 / 眼睛弄错了」—— 表情 Blend 枚举映射错位（2026-10-12 已修）

> 宿主原话：「我认为默认的这个眼睛好像弄错了」，并给出数据来源
> <https://github.com/StarMoe-org/moenotes>。

### 根因（一句话）

`tools/l2d/convert.py` 把 prefab 的 `Blend` 整数**当成与 exp3.json 同序**直接搬，
但两者**不是同一套枚举**：

| 语义 | prefab（Unity `CubismParameterBlendMode`） | exp3.json（SDK `csmExpressionBlendType`） |
|---|---|---|
| Override / Overwrite | **0** | 2 |
| Add | **1** | 0 |
| Multiply | **2** | 1 |

**证据不是推断**——上游播放器自己的实现就在仓库里
（`app/assets/live2d/vendor/ournotes-live2d.element.min.js`）：

```js
if (m && (m.blend===1 ? d=m.v : m.blend===2 ? y=m.v : _=m.v)) …   // d=add, y=mul, _=ov
… e.override(i.i, (add + override) * multiply, weight)
```

即 prefab 的 `1→Add`、`2→Multiply`、其余`→Override`，最终值 `(add + override) × multiply`。
prefab 里 28 个表情共 2018 条参数，Blend 整数只有 `{1: 1962, 2: 56}`。

### 错位之后发生了什么

- prefab 的 **`Additive 0`**（1962 条，语义 = "加 0" = 什么都不做）被写成
  **`Multiply 0`** ⇒ **参数被清零**。而 `exp_idle01` 正是大厅待机那张脸：
  `ParamCheek=0`（**腮红没了**）、`ParamEyeLHighlight/RHighlight=0`（**瞳孔高光没了**）、
  `ParameyelidL/R=0`（眼皮形变参数钉死）、`ParamMouthForm=0`（嘴形）……
  ⇒ 默认这张脸与原数据**不是同一张脸**（宿主一眼看出"眼睛不对"）。
- prefab 的 **`Multiply 1.0`**（`ParamEyeLOpen/ROpen`）被写成 **`Overwrite 1.0`**
  ⇒ 表情每帧覆写眼睑 ⇒ **眨眼被盖死** —— 这正是 v8「剥掉眼睑 = 1.0 的 Overwrite
  钉死」补丁的由来；映射修正后同一条变成 `Multiply 1.0`（乘 1 = 空操作），
  **眨眼天然恢复，补丁作废并已删除**。

### 修复

1. `convert.py`：`BLEND = {0:"Overwrite", 1:"Add", 2:"Multiply"}` + 长注释留证据链；
   删掉 v8 的剥参数逻辑（**不要再删任何参数**，删了就与原数据不一致）。
2. 重跑 `python tools/l2d/convert.py`（64 动作 / 32 表情 / 18 组，产物一致）。
3. `app/lib/stage/live2d_stage.dart`：`modelDataVersion` **8 → 9**（触发重新解压，
   绕开插件那份无内容指纹的资产缓存）。
4. 代码级检查：`flutter analyze` 无问题、`flutter test test/stage_port_test.dart` 26/26 通过。

### 验收（MuMu，与原始播放器同屏同尺寸、按眼距归一后对照）

- `exp_idle01` 条目：72 条 = **70 个 `Add 0` + 2 个 `Multiply 1.0`**（全是空操作，
  不再清零任何参数）；对照旧版是 70 条 `Multiply 0`（清零）。
- 截图对照 `.verify/l2d-clarity/v9_default_vs_web.png`：**腮红、瞳孔高光、眼皮/嘴形
  全部回来了**，与原始播放器的默认脸一致。
- 眨眼回归：连拍 16 帧，「金色虹膜」像素数 `[…, 0, …]` —— 有整帧全闭 ⇒ **眨眼正常**
  （证明删掉 v8 补丁没有副作用）。

### 教训（写给下一次）

**"枚举同序"是一种假设，不是事实。** 两份数据之间的任何整数枚举，都要拿**对方的
实现**（仓库里的 vendor JS / 官方 SDK 头）对照，而不是凭名字猜。这次错的代价是：
每个表情的所有参数都在悄悄走错分支，而**画面看起来"只是有点不对"**，很容易被
归到"糊""渲染问题"上去 —— 宿主两次都先怀疑渲染，直到拿原始网页并排才暴露。

---

## 七、删除 WebView 降级路线（2026-10-12 · 宿主拍板）

**宿主原话**：「既然我们已经能够切换到原生了, webview的逻辑就可以删除了吧」；
触发这句的是上一轮实测：「现在点击和拖动 没有动作了」——那正是切到 WebView
路线（`kNativeStage=false`）之后的现象。

### 为什么这条路线该删（两条硬理由）

1. **它触摸是断的**（就是宿主踩到的那个）。`live2d_web.dart` 里 WebView 包在
   `IgnorePointer` 内（"平台视图会吃掉触摸，交给上面那层 Flutter UI"），而
   `assets/stage/stage.js` **从来没有把指针事件转发给播放器**（只有
   `error/unhandledrejection/progress/ready/error` 四个监听）。
   于是"她的眼睛/头跟着手指"和拖动反馈在这条路线上**根本不存在**。
   原生那条能拿到触摸：`Live2DStage` 里 `IgnorePointer(ignoring: false)`，
   插件的平台视图自带 DragManager（2026-10-11 宿主验收"主界面像死人一样"时改的）。
2. **当初保留它的归因已被推翻**。留降级路线的理由是「MuMu 的 emugl 转译层与插件
   不兼容」→ 真因是 `flutter_live2d` 不打包 Android shader 资产（`docs/35`、
   本文件「2026-10-12 复盘」）。shader 已由 `build.gradle.kts` 的 `syncLive2dShaders`
   在构建期补包并 `check()`，漏了会**构建失败**而不是"静默黑屏"。

### 删了什么 / 留了什么

| 处置 | 内容 |
|---|---|
| **删** | `lib/stage/live2d_web.dart`；`stage_port.dart` 里的 `WebStagePort`；`main.dart` 的 `import`、`kNativeStage`、`_stageFallback`、`Live2DWeb(...)` 分支 |
| **不再打包** | `pubspec.yaml` 里 `assets/stage/`、`assets/live2d/vendor/`、`assets/live2d/sakiko_orig/{models,assets}/` 四条声明（APK 少 ~6.2 MB） |
| **文件留在磁盘** | `app/assets/live2d/sakiko_orig/` = **`tools/l2d/convert.py` 的输入**（删了就没法重新生成 `sakiko/`）；`vendor/` + `stage/` = 原始播放器与舞台页，作为"原始渲染长什么样"的**参照真源**（Blend 枚举那条结论就是从 vendor 里读出来的） |
| **失败降级改成** | `Live2DStage` 自己收掉平台视图 → 露出天幕下的**全息剪影**（`onFailed` 只打日志，不再切路线） |

### 验证

- `flutter analyze`：无 error（3 条 info 在别人未提交的 `main_view.dart` / `terminal_ui.dart` 里）。
- `flutter test`：**+653 -3**；那 3 条是 `onboard_test.dart` 的输入框布局用例
  （期望 810 / 实际 822），**把本轮改动 stash 掉后同样失败** ⇒ 存量问题，与本轮无关。
- 装到 MuMu 实测：原生上屏、`舞台按下 … 命中她=true`、戳她有反应（宿主可直接复看）。

### 代价（宿主已知情）

没有第二条渲染路线兜底了：若某台设备上原生加载失败，她只剩全息剪影。
原生侧此前已知的失败模式都已被构建期 `check()` 或加载重试覆盖。
