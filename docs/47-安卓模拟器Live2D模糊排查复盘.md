# 安卓模拟器里 Live2D 变糊：四层排查复盘

> 一次「感觉不如原数据清晰」的排查全程记录。结论是**素材没损失、渲染器没锅，
> 糊在显示链路的隐形重采样**。文末是可复用的量测法与检查清单。

## 一句话结论

MuMu 模拟器用 `adb shell wm size` 把画面设成 780×1688，而物理面板是 1080×1920 ——
**SurfaceFlinger 在最后一步把 780 拉伸到 887**（1.137×）。只改这一处，
脸部中频清晰度就能翻倍。**改法不是 `wm size`，是改实例面板本身。**

## 症状

- Live2D 人物比「原始数据网页」软一档，睫毛、发丝、裙格格纹发虚
- 截图看细节：贴图 2048²，屏上虹膜却只有 24 px
- 主观对比图里「右边清楚」—— 但那张对比本身有问题（见文末「对比陷阱」）

## 四层排查（顺序很重要）

### 第 1 层：素材是不是被压过？

**结论：没有，零损失。**

```
texture_00.png  2062566 B  2048×2048 RGBA  sha1 ee7b2b7ca667
原始同名贴图    2062566 B  2048×2048 RGBA  sha1 ee7b2b7ca667   ← 完全一致
sakiko.moc3     6558656 B  sha256 == 原始 moc3 解压后            ← 完全一致
```

贴图无 gamma 块、无 DPI 块，就是原始 PNG。转换工具只是换外层格式，不动像素。

⇒ **「模型转换把图压糊了」这个假设直接排除。**

### 第 2 层：渲染器的纹理过滤

插件把 `MIN_FILTER` 设成 `GL_LINEAR_MIPMAP_LINEAR`，缩小采样时会选更小的一级 mip
（2048² → mip1 1024²），等于采样前先预模糊一遍。

打补丁改成 `GL_LINEAR`（两处必须同改，只改一处会黑剪影）：

| 位置 | 说明 |
| --- | --- |
| `Live2DTextureManager.cpp:44` | 创建贴图时 |
| `CubismShader_OpenGLES2.cpp:1113` | **绘制时每张 drawable 重设**，这才是真正生效的那处 |

验证方式：直接扫编译产物里的 GL 常量。

```
GL_LINEAR_MIPMAP_LINEAR(0x2703)  count: 0     ← 补丁进包了
GL_LINEAR(0x2601)                count: 4
```

**效果：中频 +29%，运动中高频 +45%**，代价是缩小场景下细线有轻微走样。

⇒ 这是**真实差异之一**，但只占一部分。改完还是觉得糊，说明还有别的东西。

### 第 3 层：画布 / DPR / 抗锯齿

**结论：都正常，不是问题。**

- 逻辑尺寸 390×844dp，DPR 2 ⇒ 物理 780×1688
- iOS 侧 `contentScaleFactor` 已参与计算，按 DPR 出图
- 合成只有一次重采样（`sourceCrop` 与缓冲同尺寸）

### 第 4 层：显示链路 —— **真正的锅在这里**

```bash
adb shell wm size      # Physical 1080×1920 / Override 780×1688  ← 覆盖！
adb shell wm density   # Physical 480      / Override 320

adb shell dumpsys SurfaceFlinger | grep -oE "displayFrame=\[[0-9 ]+\] sourceCrop=\[[0-9. ]+\]"
# displayFrame=[96 0 983 1920]  sourceCrop=[0 0 780 1688]
```

读法：**887×1920 的坑里装了 780×1688 的图** ⇒ 放大 **1.137×**。

这是双线性放大，等于整幅画面过一遍模糊。实测这一小段链路的代价：

| | 中频能量 |
| --- | --- |
| 应用缓冲区（780×1688，未经合成） | 0.1298 |
| 同一帧经窗口合成后 | 0.0719 |
| **损失** | **−44.6%** |

⇒ **同一份渲染结果，光是被显示链路拉一下就掉一半中频。**

## 修法：改实例面板，不是 wm size

关键认知：`wm size` 是**运行时覆盖**，只会让 SurfaceFlinger 多插一次缩放。
**只有改实例面板本身，才能拿到 1:1。**

```
逻辑尺寸  390 × 844 dp     ← 不变，布局/字号/热区全照旧
面板      1170 × 2532 px
dpi       480              ← dp = px/(dpi/160) = 1170/3 = 390 ✓
DPR       3
```

**为什么是 1170×2532**：宽高比 0.46209，与旧档 780/1688 **完全一致** ⇒ 零布局位移。
换成 1080×2340（同为 19.5:9）宽高比就成了 0.4615，会引入亚像素级重排。

### 完整操作

```bash
# 1) 关机态写面板（分辨率设置只在关机时能改）
mumu-cli.exe control -v 4 shutdown
mumu-cli.exe setting -v 4 --key resolution_mode --value custom
mumu-cli.exe setting -v 4 --key resolution_width.custom  --value 1170
mumu-cli.exe setting -v 4 --key resolution_height.custom --value 2532
mumu-cli.exe setting -v 4 --key resolution_dpi.custom    --value 480
mumu-cli.exe control -v 4 launch

# 2) 等 adb 就绪后，清掉运行时覆盖（否则还是缩放）
adb -s 127.0.0.1:16512 shell wm size reset
adb -s 127.0.0.1:16512 shell wm density reset
```

### 验证（两条都对才算成功）

```
Physical size: 1170x2532 / Physical density: 480    ← 没有 Override 行
displayFrame=[0 0 1170 2532]  sourceCrop=[0 0 1170 2532]   ← 两者尺寸相同 = 1:1
```

### 效果

| 指标 | 旧 780×1688 (DPR2) | 新 1170×2532 (DPR3) | 变化 |
| --- | --- | --- | --- |
| 虹膜直径 | 21.5 px | 36.0 px | 1.67× |
| texel / 屏幕像素 | 5.77 | 3.44 | 贴图利用率 +68% |
| **脸部中频** | 0.1013 | **0.2124** | **+109.7%** |
| 高频 ≥0.60 | 0.0886 | 0.0545 | ↓（见下） |

**高频为什么反而降低**：旧配置是「小图放大」，放大会在没有细节的地方造出锯齿高频。
新配置 1:1，高频回落但真实笔触的中频翻倍 —— 观感是「更干净且更利」，不是更糊。

## 两个必踩的坑

### 坑 1：`resolution_mode` 的顺序陷阱

```
setting --key resolution_width --value 1170
→ {"errcode": -101, "errmsg": "key not writable"}
```

必须先切 `resolution_mode = custom`，**但这一步会把 width/height/dpi 三个值清零**，
之后也不能写普通键 —— 只能写 **`.custom` 后缀键**：

```
resolution_mode          = custom     （清零，正常现象）
resolution_width.custom  = 1170       ← 只认这个
resolution_height.custom = 2532
resolution_dpi.custom    = 480
```

### 坑 2：实例刚起来时 adb 是 offline

```
adb.exe: device offline
```

脚本要加**重连轮询**再 `wm size reset`，否则 `set -e` 会让脚本停在
「面板已改、覆盖未清」的最糟中间态 —— 分辨率变了但还在缩放，比不改更迷惑。

## 为什么前几次「修」都没用

| 试过 | 结果 | 为什么无效 |
| --- | --- | --- |
| 2× Lanczos 上采样贴图 4096² | 高频只 **+3%**，主观「更糊」 | mipmap 链按缩小倍数选级，**把细节归一化掉了** |
| 加点画布超采样 | 救不回细节 | 同因：mip1 已经吃掉了 |
| 关 mipmap 补丁 | 中频 **+29%**，有效但不够 | 只解决了渲染层，显示层还在拉 |

⇒ **每次只修一层，所以每次都觉得「有点用但没根治」。**

## 对比陷阱：先归一化几何再比

宿主给的左右对比图里「右边更清楚」，实测：

| | 眼距 | 虹膜 | 结论 |
| --- | --- | --- | --- |
| 左（我们的 App） | 69.0 px | 25.0 px | |
| 右（原始数据） | 75.5 px | 27.5 px | **大 1.09 倍** |

右图高频 0.0515 < 左图 0.0721，**高频并不更高**。它看起来更清楚，**主要是更大 + 特写构图**。

**规则：对比前必须按眼距把两张脸缩放到同一尺寸**，否则「更大」会被误判成「更清楚」。

## 可复用的四维量测法

不要只看单一指标，四个一起看才不会被骗：

| 量 | 怎么算 | 看什么 |
| --- | --- | --- |
| **虹膜像素** | 阈值分割金色虹膜 → 连通域宽度 | 与贴图里虹膜的 texel 数比 ⇒ texel/px |
| **中频能量** | FFT 径向谱 0.22–0.38 归一化占比 | **真实笔触细节，主判据** |
| 高频 ≥0.60 | 同上 | ⚠️ 会误报：放大走样也在这里，**不能单独用** |
| **SurfaceFlinger 几何** | `sourceCrop` vs `displayFrame` | 两者尺寸**相同**才 1:1；不同就有一次重采样 |

## 下次遇到「模拟器里糊」的检查清单

1. `adb shell wm size` —— 有没有 **Override**？有就先怀疑显示链路
2. `dumpsys SurfaceFlinger` 的 `sourceCrop` 与 `displayFrame` 尺寸是否相同
3. 贴图 sha256 和原始素材是否一致（排除素材损失）
4. 编译产物里有没有 `0x2703`（GL_LINEAR_MIPMAP_LINEAR）
5. 量 iris px 算 texel/px，判断瓶颈在贴图还是显示
6. **对比前先按眼距归一化**

## 一句话给未来的自己

> 显示链路的缩放是**最容易漏、代价最大**的一环：它不报错、不改代码、
> 只是让画面变软，而你会在渲染器和素材上白找一下午。
