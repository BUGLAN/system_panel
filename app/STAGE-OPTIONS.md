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
4. **平台视图外面不能套 `Transform`/`Opacity`**（hybrid composition 走 saveLayer，
   平台视图可能整个不画）。所以原型那套 `_camMul` 不能靠包一层 Transform 复刻。
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

## MuMu · 原生舞台复验（2026-10-09 · T7）—— 结论：止损，默认回 WebView

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

**MuMu/旧 AVD 的「不上屏」结论只对模拟器 emugl GL 转译栈成立**——真机（A17 Pro
硬件 GPU + EAGL）上 flutter_live2d 1.0.2 一次加载成功、渲染、合成、性能全部正常。
原生路线（①）正式转正，WebView（②）退居降级备份。

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
