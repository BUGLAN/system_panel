# 舞台（Live2D 角色）落地路线

> 2026-10-08 调研。除"她"以外，舞台的其余部分（镜头数学、身上的环、环挂签、
> 投影光束、亮帧/震屏）**都已经在 `app/` 里跑起来了** —— 见
> `lib/stage/camera.dart`、`lib/stage/ring_painter.dart`、`lib/widgets/ring_tag.dart`。
> 这一页只解决"人形"这一件事。

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
