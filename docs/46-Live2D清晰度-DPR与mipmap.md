# 46 · Live2D 清晰度：DPR、mipmap 与超采样（Android 提 DPR / iOS 超采样，均已真机实测）

> 起因：宿主「一直感觉此项目的 Live2D 与原数据的 Live2D 相比不够清晰」，并进一步指出
> **「主要感觉放到 iOS 手机上有点模糊」**。
> 本文记录：① 清晰度如何被拆成可验证维度；② MuMu 侧「保持 390×844dp、提高 DPR」的落地；
> ③ iOS 侧先试「关 mipmap」（§3.7/§3.8 三点实测 + 采样仿真，结论：那只是拿混叠换锐利）；
> ④ **最终方案 = 超采样**（§3.9，2026-10-24 真机定案：清晰且无锯齿）。
> 最后更新：2026-10-24 深夜（SSAA 1.68× + 贴图预锐化；LOD bias 实测不可用）

---

## 一、结论先行

| 平台 | 瓶颈在哪 | 处置 | 状态 |
|---|---|---|---|
| **MuMu 模拟器** | 面板 1080×1920 只能给到 **DPR 2**，且用 `wm size` 覆盖时 SurfaceFlinger 还在缩放 | 面板改 **1170×2532@480 = 390×844dp @DPR3**，并清掉 wm 覆盖 → **1:1 零重采样** | ✅ **已落地** |
| **iOS 真机** | DPR 恒为 3（App 改不了）；贴图相对屏幕**本来就 1:1**（虹膜 96×112 texel ↔ 屏上 34~41px，LOD 1.07~1.22)⇒ 采样器没有可榨的油水 | **超采样**：平台视图族 1.05→1.40，按 1.52× 像素渲染再缩回屏幕；**mipmap 保持原版** | ✅ **已落地**（§3.9）：中频 +50~53%、无走样；`关 mipmap` 那条已被宿主观感否掉（§3.7「锯齿太多」） |

**一句话**：MuMu 靠「提 DPR」；iOS 的 DPR 已封顶，所以靠**超采样**——多渲染像素再缩回屏幕（不是关 mipmap：那只是拿锯齿换锐利，宿主 2026-10-24 当场否掉）。

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

## 三、iOS：关掉 mipmap（已执行 · 2026-10-24 真机三点实测）

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

⇒ **iOS 的渲染密度本来就比 MuMu 高 66%**。

> ⚠️ **2026-10-24 实测修正（详见 §3.8）**：**瓶颈不是贴图**。虹膜在 `texture_00` 里是 **96×112 texel**
> （旧数 124 / 60~77 / 「47.8 px」都不是虹膜：47.8px 是眼裂、60~77 是高光椭圆）；真机 lobby 上虹膜
> **34~41 px** ⇒ texel/FBO px **2.10~2.34** ⇒ GPU 选 **LOD 1.07~1.22** ⇒ **正好 1:1**。
> 即 mip 没有「把 38.6% 再砍一半」，它砍掉的正是屏幕表现不了的部分 —— 这一条决定了 §3.2 的补丁
> 只能是**观感取舍**，不是修 bug。

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
[all] 部分补丁（2/4 已打，2 处仍是 mipmap）
```

即 **iOS 两处已打（2026-10-24）、Android 两处仍是原版**。
⚠️ 补丁只落在**本机 pub 缓存**，换机器 / `flutter pub cache repair` 后都要重跑；
所以「Mac 上 iOS 已打、Windows 上 Android 已打」是**两台机器的各自状态**，不是同一份缓存。

### 3.3 执行方式

```bash
python tools/l2d/patch_plugin.py --target ios                  # 只打 iOS（默认 linear = 彻底关 mip）
python tools/l2d/patch_plugin.py --target ios --variant nearest # 折中：保留 mip 链、只取最近一级
python tools/l2d/patch_plugin.py --check                        # 看每个缓存当前是哪个口径
python tools/l2d/patch_plugin.py --revert                       # 回滚（从 .orig 整文件还原）
```

`--variant` 是 2026-10-24 真机三点实测后加的（见 §3.7）：`linear` 最锐但会有点状噪光；
`nearest` 只是把「跨级三线性混合」换成「取最近一级 mip」，走样代价小得多。
两种口径可以来回切（脚本一律以 `.orig` 原版为基准重写），每次切换 ≈1 分钟增量构建。

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

### 3.7 真机三点实测（2026-10-24 · iPhone 15 Pro Max · iOS 27.0.1）

§3.4 里预判「很可能重现 2026-10-11 的『变差了』」。这次不再靠肉眼单点判断，而是把三种口径
**各构建一次、装到同一台真机、在同一个大厅机位截帧**，再按 §4 的量测法做对齐比较。

**三点口径**

| 记号 | `MIN_FILTER` | 含义 |
|---|---|---|
| ① 原版 | `GL_LINEAR_MIPMAP_LINEAR` | 跨级三线性（现状） |
| ② mip 近邻 | `GL_LINEAR_MIPMAP_NEAREST` | 保留 mip 链，只取最近一级 |
| ③ 关 mip | `GL_LINEAR` | §3.2 的老方案 |

**命令链**（每次切换 ≈1 分钟：Xcode 增量只重编那 2 个文件）

```bash
python tools/l2d/patch_plugin.py --target ios --variant linear|nearest
cd app && flutter build ios --release
xcrun devicectl device install app --device 00008130-001169D830A1401C build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device 00008130-001169D830A1401C com.systempanel.app
xcrun devicectl device capture screenshot --device 00008130-001169D830A1401C --destination shot.png
```

**量测结果**（1290×2796，固定绝对窗口 ⇒ 几何天然归一化；三帧虹膜质心相差 ≤5px）

| 窗口 | 频段 | ① 原版 | ② mip 近邻 | ③ 关 mip |
|---|---|---|---|---|
| 脸 360×300 | 中频 0.22–0.38 | 0.80% | 0.67%（−17%） | **2.55%（+219%）** |
| | 高频 ≥0.60 | 0.01% | 0.01%（−12%） | **0.03%（+133%）** |
| | 梯度 RMS | 0.0331 | 0.0341（+3%） | **0.0476（+44%）** |
| 领口 260×230 | 中频 | 0.71% | 0.81%（+14%） | **1.97%（+178%）** |
| | 高频 | 0.02% | 0.02%（−2%） | 0.03%（+48%） |
| 发丝 180×300 | 中频 | 0.25% | 0.36%（+44%） | **0.93%（+270%）** |
| | 高频 | 0.01% | 0.01%（+0%） | 0.01%（+60%） |

并排放大图（3× 最近邻）：`.verify/l2d-clarity-ios/lead/ABC_lobby_{face,hair,full}.png`
截图：`BEFORE_home.png`（①）/ `NEAR_boot_13.png`（②）/ `LIN_25.png`（③）

**肉眼结论（与数字一致）**

- ③ 关 mip：**确实明显更利** —— 睫毛、发丝边缘、缎带折线都出来了，但**腮红、发梢、缎带上出现
  点状噪光**（走样）。§3.4 担心的那件事可以复现，2026-10-11 判「变差了」的原因也就对上了。
- ② mip 近邻：发丝窗口量到 **+44% 中频**、高频几乎不动；人脸窗口的 −17% 属**帧间姿态/表情噪声**
  （三帧眼型、嘴角本来就不同，谱能量对内容很敏感）。观感是「更利，但没有噪点」。
- ① 原版：最干净，也最软。

**量出来的另一条规律（比选哪个口径更重要）**

同一台机器上，**她越小、关 mip 的走样越重**：开机页（`s=0.64`，贴图缩小 ≈3~4×）关 mip 后
高频 **+550%**；大厅（`s=0.92`，缩小 ≈2.6×）只有 **+133%**。⇒ 真要在大厅关 mip，
「让她显示得更大」（§3.6 第一条：构图放大）永远是更划算的那一半。

**给宿主的切换口径**（都只动本机 pub 缓存，仓库零改动）

```bash
python tools/l2d/patch_plugin.py --target ios --variant nearest   # 推荐折中
python tools/l2d/patch_plugin.py --target ios --variant linear    # 最锐（2026-10-24 装机验收用的就是这个）
python tools/l2d/patch_plugin.py --revert --target ios            # 回原版
# 之后都要：cd app && flutter build ios --release && 重装（改的是 native，热重载无效）
```

### 3.8 贴图密度裁决 + 采样仿真（2026-10-24 · 决定 §3.2 值不值得打）

§3.1 的数字互相矛盾（124 texel / 60~77 texel），真机上又只有主观判断。这一轮先把
**贴图密度**量死，再用**受控重采样仿真**回答「关 mip 到底能换到多少真实细节」。

**① 贴图里虹膜到底多少 texel**（`texture_00`，HSV 金色阈值 + 连通域，阈值全扫一遍最大行宽恒 96）

| 对象 | bbox | 尺寸 |
|---|---|---|
| **金色虹膜**（两眼共用一份） | x[1712,1808) y[7,119) | **96 × 112 texel** |
| 虹膜深色上缘（渲染里“瞳孔感”的来源） | x[1712,1808) y[7,86) | 96 × 79 |
| 眼白（薰衣草） | x[1526,1720) y[1694,1820) | 194 × 126 |
| 睫毛（深蓝弧） | x[1506,1694) y[1653,1728) | 188 × 75 |
| 金色高光椭圆 ×2 | (1591,1874)、(1524,1971) | 64 × 33 |

旧数全部对不上：**124** 最接近“眼白短边 126”、**47.8 px** 是眼裂宽度、**60~77** 是高光椭圆。
方向结论不变（比值仍 ≈2.5），但「只用到 38.6%」应改成 **37.5%**，且**它不是瓶颈**（见下）。

**② texel/px 与 GPU 会选的 mip LOD**

| 相机 | 族 | FBO 高 px | 屏上占高 | 虹膜屏 px | texel/FBO px | **LOD** |
|---|---|---|---|---|---|---|
| lobby 0.92 | 1.05 | 2935.8 | 2572 | 34~41 | 2.10~2.34 | **1.07~1.22** |
| talk 1.70（派单） | 1.70 | 4753.2 | 4753 | 66.5 | 1.44 | **0.53** |
| boot 0.64 | 1.05 | 2935.8 | 1789 | 25 | 2.34 | 1.22 |
| MuMu DPR3 | 1.05 | 2658.6 | 2329 | 32.6 | 2.58 | 1.37 |
| MuMu 旧 DPR2 | 1.05 | 1772.4 | 1553 | 21.7 | 3.87 | 1.95 |

LOD 1.22 ⇒ mip 通带 0.214 c/texel，而屏幕能表现的上限是 0.1875 ⇒ **现状通带比屏幕上限还高 14%**：
**iOS 现状是“略偏锐”，不是“被砍一半”**。这也解释了为什么 Android（LOD 1.37~1.95）打补丁收益大、
iOS 打完只觉得“有噪点”。

**③ 受控采样仿真**（真实贴图 patch 重采样，含 Flutter 合成那一层 0.876 降采样）

| 变体 | 眼 中频 | 眼 高频 | 裙格 高频 | 结论 |
|---|---|---|---|---|
| a 现状 mip+三线性 | 2.503% | 0.362% | 1.650% | 基准 |
| b 关 mip（§3.2 方案） | **2.816%（+12.5%）** | **1.053%（×2.9）** | **4.918%（×3.0）** | 中频小赚、高频代价 3× |
| c mip 近邻 | 2.663%（+6.4%） | 0.514%（×1.4） | 2.322%（×1.4） | 但 **talk 会退**（见下） |
| d LOD bias −0.5 | 2.701%（+7.9%） | 0.622%（×1.7） | 2.826%（×1.7） | 两相机都不退化，最优折中 |
| e 2× Lanczos + 关 mip | 2.843% | 1.196% | 5.871% | 再证否一次 |

- **mip 近邻不能当“无代价”选项**：talk 相机 LOD 0.53 会被 floor(LOD+0.5) 取整到 **mip1（半分辨率）**，
  仿真中频 2.806 → 2.566 = **−8.6%**，也就是**派单推近会变糊**；它只在大厅 +6%。
- **LOD bias −0.5 才是最该试的**（大厅 +7.9%、talk +9.4%），落地方式是给 frag shader 的
  texture2D 带 bias。⚠️ 本轮**没打**：GLES2 头里没有 GL_TEXTURE_MAX_LOD 这个 token
  （desktop / GLES3 才有），用 0x813B 硬写要自己确认不触发 GL error 0x500。下一轮从这里接。

**④ 对你的实际含义**：iOS 已经到“屏幕分辨率上限”，**任何滤器改动换来的都是“更利”而不是
“更多细节”**；真正还能增加观感的只剩 §3.6 的**构图放大**（她更大）或换**更高分辨率素材**
（已被两次仿真证否：只加高频噪声）。2026-10-24 装机验收的版本是 **--variant linear（关 mip）**。

### 3.9 【2026-10-24 定案】锯齿问题：开源做法 + 超采样（**这才是最终方案**）

§3.7/§3.8 的结论「关 mipmap 换锐利」被宿主当场否掉：**「锯齿太多了」**。于是按宿主的要求去查
开源实现，再回来做实验 —— 结论是：**不要动采样器，要多渲染像素**。

#### ① 开源/官方是怎么做的（证据）

| 结论 | 出处 |
|---|---|
| 官方 Cubism iOS 样例就是 `glGenerateMipmap` + `GL_LINEAR_MIPMAP_LINEAR` | [LAppTextureManager.mm#L87-L90](https://github.com/Live2D/CubismNativeSamples/blob/develop/Samples/OpenGL/Demo/proj.ios.cmake/src/LAppTextureManager.mm#L87-L90) |
| 而且**每次绑贴图都重设过滤**（只改加载处会被覆盖 —— 这就是「两处必须一起改」的成因） | [CubismShader_OpenGLES2.cpp#L1097-L1102](https://github.com/Live2D/CubismNativeFramework/blob/develop/src/Rendering/OpenGL/CubismShader_OpenGLES2.cpp#L1097-L1102) |
| 官方渲染器**不启用任何 MSAA / 各向异性**（默认 0，从不设置） | [CubismRenderer.cpp#L26](https://github.com/Live2D/CubismNativeFramework/blob/develop/src/Rendering/CubismRenderer.cpp#L26) |
| Flutter 的平台视图缩放是引擎写 `embeddedView.layer.transform` 交给 CoreAnimation，**Impeller 不参与、也没有 filterQuality 开关**；CA 默认 `kCAFilterLinear`、不生成 mip | [FlutterPlatformViewsController.mm#L680-L698](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm#L680-L698) |
| pixi 生态：糊 → `resolution: 2`（多渲染像素） | [pixi-live2d-display#146](https://github.com/guansss/pixi-live2d-display/issues/146) |
| 高模缩小出锯齿 → 加 mipmap；作者原话就是「超采样 vs 分辨率」 | [untitled-pixi-live2d-engine#15](https://github.com/Untitled-Story/untitled-pixi-live2d-engine/issues/15) |
| Ren'Py 用 `config.mesh_oversample` 修 Live2D 渲染糊 | [renpy#6921](https://github.com/renpy/renpy/issues/6921) |
| **GLES2 硬边界**：没有 `GL_TEXTURE_MAX_LOD`、没有 multisample（要 `APPLE_framebuffer_multisample`）、gl2ext.h 里没有各向异性 token ⇒ MSAA / 各向异性 / MAX_LOD 三条路**直接否掉** | [gl2.h](https://github.com/KhronosGroup/OpenGL-Registry/blob/main/api/GLES2/gl2.h) · [gl2ext.h](https://github.com/KhronosGroup/OpenGL-Registry/blob/main/api/GLES2/gl2ext.h#L961-L976) |

⇒ 业界一致的解法是 **「保 mipmap（干净）+ 多渲染像素再缩回去（更利）」**，也就是 SSAA；
把采样器调硬（关 mip）只是把混叠当清晰度卖。

#### ② 四种配置的真机实测（iPhone 15 Pro Max，同一大厅机位）

| 配置 | 中频 0.22–0.38 | 高频 ≥0.60 | 肉眼 |
|---|---|---|---|
| a mipmap + 1.05 族（原版） | 基准 | 基准 | 干净但软 |
| b **关 mipmap** + 1.05 族（§3.7 那版） | +219% | **+133%~2200%** | **点状噪光/阶梯边**（宿主否掉） |
| c mipmap + 1.40 族 = **1.52× 超采样** | **+50~53%** | +74~162% | **更利、无点状噪光** ← 采用 |
| d mipmap + 1.70 族 = 1.85× 超采样 | +73~81% | +103~187% | 略更利，但显存/填充 ×3.6 |

并排放大图（3× 最近邻）：`.verify/l2d-clarity-ios/lead/FINAL_{face,hair}.png`（a / c / d 三档）
截图：`REF_mip105_63.png`（a）· `SSAA140_72.png`（c）· `SSAA170_82.png`（d）
（都带 `--dart-define=SHOT=lobby`，同一姿势、同一机位、可逐像素比）

#### ③ 落地方案（本仓库当前状态）

- `app/lib/stage/live2d_stage.dart`：`kViewFamilies = [1.40, 1.70]`（小景别 1.05 → 1.40）
- **pub 缓存保持插件原版**（`patch_plugin.py --revert`）：mipmap + 三线性不动
- ⚠️ 这是**超采样比**，不是几何回退：布局矩形按 1.40 倍屏高固定，缩放仍由 `Transform.scale(cam.s/族)` 表达，
  她的**屏幕上大小/位置完全不变**，只是平台视图多渲染了 1.52× 的像素，再由 CoreAnimation 线性降采样
- 代价：小景别 FBO 3914×2609 px（≈10.2M px，显存 ~61MB，填充 ×2.3）；派单 1.70 族不变。
  掉帧就把常数退到 1.25（≈1.36×，仍有明显收益）
- `test/stage_port_test.dart` 已同步：新增「大厅超采样比 ≥1.3×」的断言，防止有人把它改回 1.05

#### ④ 还没用、但值得知道的

- **LOD bias −0.5**（frag shader 的 `texture2D(..., -0.5)`）：仿真 +8~9%，可与超采样叠加；
  本轮没打 —— GLSL ES 1.00 的 bias 参数各驱动支持不一，要先真机验编译（失败就是整个 shader 挂掉）。
- **构图放大**（`lobby.s 0.92 → 1.05`）：改观感，要宿主点头；和超采样叠加是最「近看」的组合。
- 贴图分辨率：**别再试**（两次仿真都证否，只加高频噪声）。

### 3.10 下一档（2026-10-24 深夜）：把超采样拉满 + 贴图预锐化，以及两条死路

§3.9 定案后宿主说「尽量再清晰一点」。这一轮把能加的都试了，**结论是：iOS 已经到物理上限**。

#### ① 超采样 1.40 → 1.55（继续加）

| 大厅超采样比 | 脸中频 | 发丝中频 | 梯度 RMS | 结论 |
|---|---|---|---|---|
| 1.00×（原版） | 0.69% | 0.83% | 0.0337 | 软 |
| 1.52×（族 1.40，§3.9） | 1.03%（+50%） | 1.28%（+53%） | 0.0397 | 已很利 |
| **1.68×（族 1.55，本轮）** | **1.13%（+64%）** | **1.41%（+69%）** | 0.0415 | **采用** |
| 1.85×（族 1.70，实测过） | 1.19%（+73%） | 1.51%（+81%） | 0.0423 | 基本饱和 |

**为什么会在 ~1.7× 饱和**（这次才真正想明白）：超采样把 FBO 像素变多以后，插件算出的贴图
LOD 会一路往下掉，**在 1.7× 附近就撞到 mip0（LOD=0）** —— 再多的像素只是在双线性放大同一批
texel，不会变出细节。所以「加到 2×、3×」毫无意义，只是烧显存和填充率。
⇒ 定在 **族 1.55**（大厅 1.68×）：`app/lib/stage/live2d_stage.dart` 的 `kViewFamilies`。

#### ② 贴图预锐化（新能力：`convert.py --sharpen`）

贴图在屏幕上是**被缩小 ≈2.6×** 采样的，所以「提清晰」还有一条路：先在贴图侧把边缘对比度
提上来（烘焙一次 unsharp mask），缩小采样时会平均掉一部分、剩下的就是「更利」。

```bash
python3 tools/l2d/convert.py --sharpen 60   # 只动 RGB，alpha 一律不碰（碰了部件交界会起硬边）
```

实测（大厅、族 1.55、同姿势）：**发丝中频 1.41% → 1.53%（+8%）**，脸上基本持平
（脸的中频本来就被屏幕分辨率限死了）；并排 3× 看**没有可见光晕**
（`.verify/l2d-clarity-ios/lead/SHARP_{face,hair}.png`）。
⚠️ 两个注意：① 素材目录在 `.gitignore` 之下，换机器要重跑这条命令；
② 建议 40~80，超过 100 在**派单特写**（LOD 0.53，缩小倍数最小）可能看到光晕。

#### ③ 两条死路（都实测过，别再走）

| 做法 | 结果 | 证据 |
|---|---|---|
| **frag shader 加 LOD bias −0.5**（`texture2D(s_texture0, v_texCoord, -0.5)`） | **模型整个不渲染** —— Apple 的 GLES2 不接受 texture2D 的 bias 参数（shader 编译失败） | `.verify/l2d-clarity-ios/BIAS_92.png`（只剩背景板） |
| **继续加大超采样**（族 1.70 / 1.85） | 只多 +5~9%，显存/填充却再涨 40%+（LOD 撞 mip0 饱和） | 上表 |

⚠️ `tools/l2d/patch_plugin.py` 里保留的 `--bias` 是**给 Android / 其它 GLES 实现试的**，
iOS 这条别用：打上去不是「变糊」，是**她直接消失**。

#### ④ 最后还剩的、唯一能再加一点清晰的杠杆

**构图放大**（不是渲染问题，是「她占多少屏」）：`camera.dart` 的 `lobby.s: 0.92 → 1.05`。
按几何算，虹膜会从 46px → 52.5px，她占屏高 +14%，**贴图仍然够密（texel/px 1.83，LOD 0.87）**，
所以不会变糊、只会变大变清楚。**但这是改观感构图，要宿主点头**，所以本轮没动。

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
- iOS 贴图密度 + 采样仿真的完整报告（2026-10-24）：`.verify/l2d-clarity-ios/measure-note.md`
  （虹膜 96×112 texel 的连通域裁决、texel/px 与 LOD 对账、五种采样变体的 mid/high/shim 表、
  `sim_sampling.py` / `sim_supersample.py`）
- iOS 三点实测（2026-10-24）：`.verify/l2d-clarity-ios/`（`BEFORE_home.png` / `NEAR_boot_13.png` /
  `LIN_25.png` / `lead/ABC_lobby_*.png` / `lead/AB_boot_face.png`；量测脚本 `lead/lobby_abc.py`）
- 上一轮四路对比：`.verify/l2d-clarity-2/`（`SUMMARY_clarity_4way.png`、`cmp_eyes_1to1.png`）
- 两处目录均在 `.gitignore` 的 `.verify/` 之下，**不入库**
