# 舞台（Live2D 角色）落地路线

> **2026-10-08 结论：她已经渲染在 App 里了 —— 走的路线 ②。**
> 排查全过程、以及为什么放弃原生插件 ①，都在下面。
> 剩下的活是**相机标定**与**表情/动作桥**，见文末「还差什么」。

## ✅ 最终结果

`[stage-web] 播放器就绪`，屏幕上她完整渲染（`.verify/_g11.png`），
Flutter 那层的环正确定位在她身上，HUD/底栏/字幕合成正常。

**做法**：App 内起一个只服务 APK 资产的迷你 HTTP 服务，WebView 加载
`assets/stage/stage.html`，那里用**原型自己的播放器**（`ournotes-live2d.element.min.js`）
渲染**原始 prefab 数据** —— 渲染结果与原型的**保证一致**。

## 为什么不是原生插件（① 走过、放弃了）

试过 `flutter_live2d 1.0.2`：能编译、能加载（`loadModel` 返回 `true`）、
`Live2D-RenderHub` 线程在跑、`dumpsys` 里视图也在（全屏、可见），
**但屏幕上什么都没有**。

**决定性对照**：换成**标准模型 Hiyori** 也画不出来 —— 所以**不是**"我转换出来的
模型有问题"（转换器是好的：64 动作 / 28 表情 / 物理 / moc3）。
同期用**模拟器自己的浏览器**打开原型，她渲染完全正常 —— 所以也不是模拟器不能渲染。

结论：**是插件的平台视图路径在这台机器上不上屏**（原因没查到底，但已无继续投入的价值）。

### 排查路上踩掉的坑（全都写进代码注释了）

| # | 坑 |
|---|---|
| 1 | CMake 版本被插件写死 `3.10.2`，而 Google 已从 SDK 仓库下架；`cmake.dir` 压不过 DSL 的 `version` → 在 `app/android/build.gradle.kts` 用反射改写为 3.22.1（块必须在 `evaluationDependsOn` **之前**） |
| 2 | **Flutter 声明资产目录不递归子目录** → 必须逐个列子目录 |
| 3 | **`Opacity(0)` 让原生加载死锁**（surface 不创建 → `loadModel` 永不执行） |
| 4 | 平台视图外面套 `Transform`/`Opacity` 会让它整个不画 |
| 5 | **`ShakeLayer` 是 `Transform` 且包住整个 App** → 不抖时也不能留（已改为不抖就直通） |
| 6 | 播放器用 `fetch` 读资源，`file://` 会被 CORS 拦掉 → 必须走本机 http |
| 7 | **Content-Type 要按资产 key 取**，不能按 URL 路径取（`/` 没有扩展名 → 回落成 `application/octet-stream` → WebView 不当网页渲染） |
| 8 | **播放器模块是 ES Module，不能当普通 `<script>` 挂** —— 它只导出不自注册，必须动态 `import()` 后手动 `defineOurnotesLive2D()`（照抄原型 `stage.js` L112-115）。用普通 script 会在**解析阶段**失败，且报错早于 `onerror` 注册，**毫无信号** |
| 9 | 清单里的 `assets/xxx` 是**相对页面根**解析的，服务端要兜住 `/assets/...` |

## 还差什么

- **相机标定**：她现在比原型略大、位置略有出入。`scale`/`offset` 已经通到
  `Stage.cam()`（就绪时会主动推一次），但还没和 `camera.dart` 的 `Cam` 对齐。
- **表情/动作桥**：`Stage.emote` / `Stage.motion` 还没接（播放器那边有动作与表情，
  原型 `Stage.emote` 是查表落到模型参数上的）。接上之后，失败时的 `emote('sad')`
  这类表演才能恢复。
- 原生路线 ① 的记录留在这里，真机或有更多时间时可以再收。

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
