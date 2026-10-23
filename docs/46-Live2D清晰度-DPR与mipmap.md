# 46 · Live2D 清晰度：DPR 与 mipmap（Android 已落地 / iOS 待验证）

> 起因：宿主「一直感觉此项目的 Live2D 与原数据的 Live2D 相比不够清晰」，并进一步指出
> **「主要感觉放到 iOS 手机上有点模糊」**。
> 本文记录：① 清晰度如何被拆成可验证维度；② MuMu 侧「保持 390×844dp、提高 DPR」的落地；
> ③ iOS 侧「关掉 mipmap」的完整方案（**本机补丁已写，尚未打**）。
> 最后更新：2026-10-24

---

## 一、结论先行

| 平台 | 瓶颈在哪 | 处置 | 状态 |
|---|---|---|---|
| **MuMu 模拟器** | 面板 1080×1920 只能给到 **DPR 2**，且用 `wm size` 覆盖时 SurfaceFlinger 还在缩放 | 面板改 **1170×2532@480 = 390×844dp @DPR3**，并清掉 wm 覆盖 → **1:1 零重采样** | ✅ **已落地** |
| **iOS 真机** | DPR 恒为 3（`contentScaleFactor`，App 改不了），**瓶颈已换成贴图分辨率**：iPhone 15 Pro Max 上虹膜 ≈47.8px，而贴图里只有 124 texel ⇒ 只用到 38.6% | **关 mipmap**（`GL_LINEAR_MIPMAP_LINEAR` → `GL_LINEAR`，两处） | 📄 **方案已写，未打** |

**一句话**：MuMu 靠「提 DPR」解决了；iOS 的 DPR 已封顶，只能靠「关 mipmap 把贴图细节放出来」。

---

## 二、MuMu：保持逻辑尺寸，把 DPR 从 2 提到 3

### 2.1 为什么不能只写 `adb shell wm size`

`wm size` 是**运行时覆盖**。实测（面板固定 1080×1920 时）：

```
# 覆盖成 780x1688（DPR2，旧配置）
displayFrame=[96 0 983 1920]  sourceCrop=[0 0 780 1688]     ← 887×1920 装 780×1688：**放大 1.137×**
# 覆盖成 1170x2532（DPR3）
displayFrame=[96 0 983 1920]  sourceCrop=[0 0 1170 2532]    ← 887×1920 装 1170×2532：缩小，但仍不是 1:1
```

两条路径都经过 SurfaceFlinger 的一次重采样。**只有把「实例面板」本身设成目标分辨率**，才能拿到
`sourceCrop == displayFrame` 的 1:1 直通。

### 2.2 落地值

```
逻辑尺寸  390 × 844 dp          ← 不变（布局、字号、点击热区全部照旧）
面板      1170 × 2532 px
dpi       480                   ← dp = px/(dpi/160) = 1170/3 = 390dp ✓
DPR       3                     ← 1170/390 = 3
```

**为什么是 1170×2532 而不是别的**：宽高比 1170/2532 = 0.46209，与旧档 780/1688 = 0.46209 **完全一致**
⇒ 换成 DPR3 后**没有任何布局位移**，只是像素密度变高。这一点很关键：换成 1080×2340（同为 19.5:9）
宽高比就成了 0.4615，会引入亚像素级的重新排布。

### 2.3 操作（一条命令）

```bash
bash tools/mumu/set-panel-resolution.sh        # 390x844dp @ DPR3（默认）
bash tools/mumu/set-panel-resolution.sh 2      # 回退到 DPR2（780x1688@320）
bash tools/mumu/set-panel-resolution.sh --show # 只看当前状态
```

脚本做四件事：关机 → 写 `.custom` 面板键 → 启动 → **清 wm 覆盖** → 重启 App。

### 2.4 ⚠️ 两个必须记住的坑

1. **`resolution_mode` 的顺序陷阱**
   `mumu-cli setting --key resolution_width` 直接写会报 `key not writable`。
   必须先把 `resolution_mode` 设成 `custom`，**但这一步会把 width/height/dpi 三个值清零**，
   之后也不能写普通键 —— 只能写 **`.custom` 后缀键**：
   ```
   resolution_mode          = custom      （会清零，正常）
   resolution_width.custom  = 1170        ← 只认这个
   resolution_height.custom = 2532
   resolution_dpi.custom    = 480
   ```
2. **启动后立刻 `wm size reset` 会 `device offline`**
   实例刚起来 adb 常没就绪，`set -e` 会让脚本中断且面板已改、覆盖未清（最糟的中间态）。
   脚本里已加**重连轮询**（最多 40 次 ×2s）。

### 2.5 实测量化（同机、同帧、同表情）

| 指标 | 旧：780×1688 (DPR2) | 新：1170×2532 (DPR3) | 变化 |
|---|---|---|---|
| 虹膜直径 | 21.5 px | **36.0 px** | **1.67×** |
| texel / 屏幕像素 | 5.77 | **3.44** | 贴图利用率 +68% |
| 脸部中频能量 (0.22–0.38) | 0.1013 | **0.2124** | **+109.7%** |
| 高频 (≥0.60) | 0.0886 | 0.0545 | ↓（旧的“高”是放大走样，不是细节） |
| SurfaceFlinger | 780→887 放大 1.137× | **1170→1170 直通** | 消除一次重采样 |
| 窗口链路（PrintWindow） | — | 中频 0.1660，仍比旧配置 **+63.9%** | |

> **高频为什么反而下降**：旧配置是「小图放大」，放大会在原图没有细节的地方造出锯齿高频；
> 新配置是 1:1，高频回落但**中频（真实笔触、发丝、睫毛）翻倍**，观感是“更干净且更利”，不是“更糊”。
> 这也是当初 2× 贴图上采样「高频只 +3%」判据失效的同一个原因 —— **只看高频会被走样骗**。

---

## 三、iOS：关掉 mipmap（方案，未执行）

### 3.1 为什么 iOS 不能靠 DPR

iOS 侧**已经**按 DPR 出图，代码在：

```swift
// flutter_live2d-1.0.2/ios/Classes/Live2DView.swift:379-381
let s = contentScaleFactor            // iPhone 15 Pro Max = 3，系统固定
let w = Int32(bounds.width  * s)
let h = Int32(bounds.height * s)
```

DPR 是屏幕物理属性，App 改不了也不该改。按项目几何常量实算（`cam.s=0.92`、`kViewFamilies=1.05`）：

| 设备 | 平台视图 | 她占屏高 | 虹膜 | texel/px |
|---|---|---|---|---|
| iPhone 15 Pro Max 430×932pt@3x | 978.6dp×3 = **2936 px** | 2572 px | **≈47.8 px** | **2.59** |
| iPhone 15 Pro 393×852pt@3x | 894.6dp×3 = **2684 px** | 2352 px | ≈43.7 px | 2.84 |
| MuMu 旧 780×1688@2x | 1772 px | 1553 px | 28.9 px | 4.30 |

⇒ **iOS 的渲染密度本来就比 MuMu 高 66%**，它的瓶颈**不是 DPR，是贴图**：
虹膜在 `texture_00` 里只有 124 texel，iOS 上摊到 47.8 px ⇒ **只用到 38.6% 的贴图分辨率**。

而插件又开着 mipmap 链 —— GPU 会按缩小倍数**选更小的一级**再采样，等于把这 38.6% 再砍一半。

### 3.2 要改的两个点

`tools/l2d/patch_plugin.py` 已写好，iOS 侧目标是两个文件两处（已核实行号）：

| 文件 | 行 | 现状 |
|---|---|---|
| `ios/Classes/Live2DWrapper.mm` | **808** | `GL_LINEAR_MIPMAP_LINEAR` |
| `ios/CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.cpp` | **1101** | `GL_LINEAR_MIPMAP_LINEAR` |

**两处必须一起改。** 只改第一处会让纹理在绘制时被第二处重设成 mipmap 过滤 ⇒ 纹理不完整 ⇒
**采样返回黑色（黑剪影）**，2026-10-11 实测踩过。

当前状态（`python tools/l2d/patch_plugin.py --check`）：

```
[all] 未打补丁（2/4 处仍是 mipmap）
```

即 **Android 两处已打、iOS 两处未打** —— 这正是本文要补的差。

### 3.3 执行方式

```bash
python tools/l2d/patch_plugin.py --target ios   # 只打 iOS
python tools/l2d/patch_plugin.py --check        # 确认 4/4 已打
python tools/l2d/patch_plugin.py --revert       # 回滚（从 .orig 整文件还原）
```

只改本机 pub 缓存（`%LOCALAPPDATA%\Pub\Cache\...`），**不进仓库、不动 pubspec 锁**。
⚠️ `flutter pub cache repair` 或删缓存后要重跑。

### 3.4 预期效果与风险（**必须有心理准备**）

Android 同款补丁实测：**中频 +29%、运动中高频 +45%**，代价是缩小场景下细线有轻微走样。

但 **iOS 的风险比 Android 高**，原因是 3.1 算过的密度差：

- iOS 上贴图是 **2.59 texel/px**（缩小采样），关掉 mip 后**没有预模糊兜底**，
  睫毛/发丝这类 1px 级线条在**运动**中更容易闪。
- 2026-10-11 在 iOS 真机上宿主已经判过这个补丁**「变差了」**。当时 iOS 渲染更接近 1:1，
  走样更刺眼 —— 这次的画面尺寸没变，所以**很可能重现同样的判断**。

**因此本条不是“修 bug”，是观感取舍，必须真机看运动再定。**

### 3.5 验收步骤（一条一条来）

1. `python tools/l2d/patch_plugin.py --target ios`
2. `cd app && flutter run -d 00008130-001169D830A1401C`
   （iOS 14+ debug 包不能从桌面图标启动，必须由 Flutter 工具链拉起）
3. **静止看**：大厅全身 — 睫毛、发丝、裙格格纹是否更利
4. **运动看**（这一步才是决定性的）：戳她触发动作 / 进出委托板推镜头，盯**发丝边缘有没有蠕动感**
5. 不满意 → `--revert` 回滚；⚠️ 回滚后**必须重新编译重装**（改的是 native C++/ObjC，热重载无效）

### 3.6 如果关 mipmap 仍不满意，剩下两条（按性价比排）

| 方案 | 改动 | 预期 | 备注 |
|---|---|---|---|
| **放大构图** | `camera.dart` 的 `lobby.s: 0.92 → 1.0~1.05` | 虹膜 47.8 → 52~55 px；贴图利用率 38.6% → 42~44% | 改观感构图，要宿主点头 |
| **更高分辨率贴图** | 4096² 或更高，**必须同时关 mipmap** | — | ❌ **单靠加贴图已证伪**：2× Lanczos 上采样高频只 +3%，宿主判“更糊” |

---

## 四、可复用的量测方法（下次排查直接用）

不要靠肉眼，也不要只看单一指标。**四个量一起看**才不会被骗：

| 量 | 怎么算 | 看什么 |
|---|---|---|
| **虹膜像素** | 阈值分割金色虹膜 → 连通域宽度 | 与贴图里虹膜的 124 texel 相比 ⇒ texel/px |
| **中频能量** | FFT 径向谱 0.22–0.38 归一化占比 | **真实笔触细节**，这是主判据 |
| **高频 ≥0.60** | 同上 | ⚠️ 会误报：放大走样也在这里，**不能单独用** |
| **SurfaceFlinger 几何** | `dumpsys SurfaceFlinger` 的 `sourceCrop` vs `displayFrame` | 两者尺寸**相同**才是 1:1；不同就是有一次重采样 |

对比前必须做**几何归一化**：按眼距把两张脸缩放到同一尺寸再比，否则“更大”会被误判成“更清楚”
（宿主给的左右对比图就是这个坑：右栏比左栏大 1.09 倍）。

---

## 五、别做的事（踩过的）

- ❌ **用 `wm size` 提 DPR**：只会在 SurfaceFlinger 多插一次缩放，中频掉 45%
- ❌ **靠 2× 贴图上采样提清晰度**：mipmap 链会按缩小倍数归一化，高频只 +3%
- ❌ **只改 `Live2DWrapper.mm` 一处 mipmap**：绘制时被 shader 重设 ⇒ 黑剪影
- ❌ **只看高频判断清晰度**：放大走样会伪装成“锐”

---

## 六、证据留档

- MuMu 新旧对比：`.verify/l2d-dpr/`（`DPR2_780.png` / `FINAL_1170x2532.png` / `FINAL_window_awake.png` / `f_*.png`）
- 上一轮四路对比：`.verify/l2d-clarity-2/`（`SUMMARY_clarity_4way.png`、`cmp_eyes_1to1.png`）
- 两处目录均在 `.gitignore` 的 `.verify/` 之下，**不入库**
