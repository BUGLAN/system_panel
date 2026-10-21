# 卡牌系统 · 已实现事实清单（只读考据，v16 现状）

> 出处行号以工作树当前状态为准。凡未在代码中找到的，标「未实现」。
> 基准设计尺寸 390×844 [tokens.dart:165-166]。

## 1 · 尺寸与安全带（含天花板）

| 事实 | 值 | 出处 |
|---|---|---|
| 领位牌（M 档 duty） | **148 × 240**（不是 220） | card_skins.dart:87 |
| L 竖版大牌 | 208 × 292 | card_skins.dart:82 |
| XS 微牌 | 100 × 72 | card_skins.dart:88 |
| 牌扇 geom(duty) | stride **104** / dx1 104 / dx2 164 / dy0 **−12** / dy1 18 / dy2 38 / rot 5° / scale .84→.70 / topPad 26 | card_skins.dart:189-202 |
| CardTable 总高 | h+topPad+dy2+30 = **334** | card_skins.dart:319 |
| 安全带 | kSafeTop **.45** / kSafeBottom **.86** | main_view.dart:128-129 |
| 窗口 | 最多 **5** 张（领位±2） | main_view.dart:135 |
| 牌屉卡高 | clamp(120, 250, band−12−48) | main_view.dart:828 |
| 牌屉宽/半径/斜切 | W−32 / 8 / 22 | main_view.dart:505；card_skins.dart:3700-3701 |

**可用高度真值**：390 基准 band=346.04 → 334 只剩 **12px 余量**；430×932 真机 band=382.12 → 余 48。
即 **148 宽 / 334 高是硬天花板**，向上加 1px 就压她的脸（脸在 20%~42%）。牌屉高 ≤250 且随 band 收缩。

## 2 · 卡边：现实现六层 + 一层角饰（同一 `dutyPath` 内缩画）

`dutyPath` = 圆角 6 + **左下 45° 斜切 16**（M），斜切长度 c=min(16, min(w,h)*.42) [card_skins.dart:727-753]。

| 层 | 内缩/线宽 | 画法 | 作用 |
|---|---|---|---|
| L1 外描边 | .5 / 1.0 | stroke，领位 α.40 / 侧位 .18 / 待发布虚线 dash6 gap5 | 唯一允许发光的一层 |
| L2 暗边 | 2.0 / 1.0 | #000 α.45 | 厚度起点 |
| L3 受光斜面 | 3.2 / 1.6 | LinearGradient 左上→右下 4 段 | 体积 |
| L4 厚度带 | 4.0~7.5 | **不画**（让底色透出） | 材质截面 |
| L5 内框 | 7.5 / 1.0 | 领位 α.26 / 侧位 .12 | 双线第二条 |
| L6 内凹阴影 | 8.4/9.4/10.4 | **三条递减 α 描边** .18/.09/.05 | 凹进卡面 |
| L7 角饰 | 贴 L5 | C.ice α.20/.28，L 折线臂长 9 | chrome，不随稀有度 |

出处 [card_skins.dart:824-945]；稀有度角饰 **C 起**（ri≥3）三直角菱形 d=2.0/2.5/3.0 [947-978]。
**被否的手法**（有注释真源）：内凹阴影**禁 MaskFilter**（每次 drawPath 独立栅格化 → 5 张卡每帧掉帧）[780-782]；禁整卡 Opacity/saveLayer、禁 backdrop-blur、噪点禁每帧 Random。
⚠️ 但 **MaskFilter 在别处仍用了 4 处**：徽记外辉 blur4 [:685]、印位 A/S 外辉 blur3/5 [:1076]、星轨 B 起小格 blur1.5 [:1224]、光包 blur4 [:4505]——「不用 MaskFilter」只对卡边成立。

## 3 · 档位印 / 星轨 / 术式徽记

- **六边印**（`DutyCrestPainter`，盒 34×38，尖朝上 `hexPath` insetX=hw*.866）[:1040-1054]。六层：压印阴影(平移 1,1 #000 α140)→外六边(F~E α.55 / D 起 .90 / 待发布线框 .45 / 已放弃 .18)→内底凹槽(deflate2.5 α.10，C 起)→内六边(.8px α.45，C 起)→内受光边(裁左上两段 C.ice α.22)→外亮边(B 起 inflate1.0)。A/S 才有外辉 [1057-1159]。
  **字母由 Text 画**：Tektur 800 **18pt** [3539-3548]——不是 painter 画字。
- **七格星轨**：点亮数 = rarity.i+1（**F=1 … S=7**）[1208]。格子 **3×4 竖刻度** gap3.6；首版 4×2.5 横方块被否（与点线规格表撞视觉语言）[1198-1204]。位置：印位右 8px、top 26、46×5 [3552-3567]。
- **术式徽记**（`DutySigilPainter`）：六维→母题 **力=三角 / 敏=双斜线 / 体=圆 / 智=方 / 知=眼 / 魅=菱形** [491-499, 576-631]；**glyph 为空 → 回落品牌母题「六边核心 + 三段经验弧 + 中心亮点」** [632-672]。外环 = 三段同心弧，半径 R(1+i·.16)，开合 .55+ri/6·.30；六枚短刻 R·1.26→1.38（点亮那枚 1.52/宽2.2）。R = 38·(w/148)，**可被 maxRadius 封顶**（牌屉传 34）[505-516]。竖牌位置 top 156 / 高 34 = 横贯术式带 [3406-3410]。
- **材质**（`DutyGroundPainter`）：铸面晕 radial 圆心(.32w,.20h) 半径 .92w α.07/.05 → 蚀刻线 −38° 间距 11 α.030 → 噪点固定种子 0x53595354 静态缓存 drawPoints α.035 → 底缘内阴影底 22% α0→.42 → 顶封条 1px α.14 [1246-1362]。
- **中景**（`DutyMidPainter`）：校验环三圈 34/26/18（按 w/148），最外圈虚线 dash3/gap9；α 从设计稿 .035~.055 **上调到 .09/.11/.14**（深底上看不见）。水印字已传 glyph: null 让位给徽记 [3382-3388]。

## 4 · 五态：形状 + 颜色双编码（状态线贴底）

> 实测线高 **2px**（`Positioned(height: 2)`）[3637-3642]，docs/40 写的是 3px——以代码为准。

定义 `enum DutyState { sealed, open, active, done, abandoned }` [card_skins.dart:66]；映射 [main_view.dart:152-160]。

| 态 | 线型（形状） | 颜色/附加 | 出处 |
|---|---|---|---|
| 待发布 sealed | 真虚线（段 4px，步长 7） | 暗青 0x5538E1FF | :4518-4538；:4224 |
| 可接 open | 实线 + 两端渐隐 + 外辉 | C.blue，boxShadow α150 blur10 | :4241-4251 |
| 执行中 active | 实线 + **12px 光包沿线走** | C.blue；ticker **15fps / 1600ms 一圈** | :4252-4273, :4485-4514；main_view:457-464 |
| 已完成 done | 实线金（三档渐变） | C.rB | :4228-4240 |
| 已放弃 abandoned | 纯灰块（无虚线） | 0x449AA3B2 + **整张叠 0x8C03060E**（不用 Opacity） | :4226-4227；:3470-3475 |

- 执行中另给**牌角计时**：Tektur 700 **11pt** C.blue，右下 [3646-3662]——光包是运动、计时是不动读数。
- **方印** 22×22 双框（外 1px + 内缩 3 的 1px），rotate 已完成 −6° / 待发布 0° / 已放弃 +8°，压印阴影右下 1px；已完成金底实心、待发布线框；字 7pt。只有 done/sealed 两态有印 [4387-4476]。
- 动画参数：光包 1.6s；扫光 520ms；落定压印 200ms（1→1.02→1，白闪 16%）；按下 .97 无补间（reduce 时压暗 .86）[card_table.dart:39-47, 453-462, 520]。

## 5 · 音效

**`Sfx.table` 共 19 个 key**（[sfx.dart:46-114]）：tap · poke · choose · land · rung(5 档) · rank(7 档) · ignite(8 档) · **detent(5 档)** · **stamp** · **deal(5 档)** · seal · publish(→ding.wav) · impact · count(3 档) · crit · levelup · fail · **boot** · ambient。
资产 **96 个 wav**；另有 48 件 `syl_<12情绪>_<4变体>` 由 `Sfx.syllable()` 拼路径、**不走 table**。
- `Sfx.play(key, {variant})`：variant 指定档位（clamp 到列表内），不传则**随机取一变体** [223-242]。
- 卡牌接线：发牌首张 deal v0 / 末张 v4（入场 88% 补，走 `_DealTicker` 不用 delayed）[card_table.dart:200,213]；咬合 detent variant=**lead%5**（修掉了原来随机音高）[227,251]；落定 **stamp**（不再用 seal）[289]；接单/提交才 seal [main_view.dart:911]。
- 池化：**12 槽**按忙闲发牌，全忙直接弃这一发（不打断）[136,191-221]；释放取 `_busyHold 250ms` 与按 key 的 `_longHold` 上界（seal 1500 / impact 1500 / boot 3900…）孰先 [141,154-164]；起播看门狗 **1200ms** 超时丢弃并踢槽 [179,300-306]。永不抛：failCount/lastError、dropCount/lastDrop [26-41]。
- ⚠️ **flip 不在 table 里**：main_view.dart:1532 调 `Sfx.play('flip')` 是**空调用**（开牌屉没声，只有震动）——与 v16 修掉的 boot 是同一类坑，这次仍在。

## 6 · 触觉

**不是 HapticFeedback**：用 `vibration ^3.2.1` 插件（为的是拿节奏而非四档强度）[haptics.dart:7-10；pubspec.yaml:24]。`patterns` 共 **20 条波形** [27-49]，卡牌 4 条：stamp [12,10,20] / deal [4] / flip [6] / edge [6]。
现状不对称：**咬合仍用 choose [8]**（docs/41 §5.1 建议的 detent [5] 未落地）[card_table.dart:228,252]；edge 已定义但**全仓无调用点**（死代码）；接单用 seal [30,40,60] 而非建议的 press。
已知未修 bug：Android `createWaveform` 首元素是「等待」→ 多元素波形整体错位一格 [docs/41 §5.3]；iOS 老机降级成 ~400ms 整机震动。

## 7 · Motion 令牌（tokens.dart:112-153）

touchMs 0 · releaseMs 120 · respondMs 140 · sceneContentMs 320 · sceneChromeMs 520 · harvestMs 600 · stampMs 280 · levelUpMs 780 · **heartMs 2400** · drawerOpenMs 420 · drawerCloseMs 260 · scrimMs 200 · **cardTableK 120 / ζ.9** · cameraK 70 / ζ.95 · maxOvershoot 1.08 · exitRatio .6 · maxLooping 2。
曲线：kOut=Cubic(.16,1,.3,1) [101]、kInOut=Cubic(.65,0,.35,1) [104]。
**实况**：19 个常量只有 **7 个**被引用（respondMs/harvestMs/stampMs/heartMs/drawerOpenMs/drawerCloseMs/scrimMs）[docs/41 §1.4 已核]；弹簧实际跑的是 rail_base.dart **自研半隐式欧拉 Spring**，显式禁用 Flutter `SpringSimulation` [rail_base.dart:348-376]。

## 8 · 接任务三拍（v16 唯一已落地的手感编排）

`_accept` **360ms**：0~120ms 压印 .96→1.02（easeOut）；120~360ms 抽走 1.02→.84、dy −34、op 1→0（easeInCubic）；**360ms 才调 onAccept** [main_view.dart:285-332]。seal 音与震动在**按下第 0 拍**就响 [911-914]。reduce-motion 直接落终态。

## 9 · 两处「注释有、实现无」（提案别当已存在）

1. **牌屉 scrim 未实现**：多处注释写「α.22 / 200ms 舞台压暗」，但 `_DetailStage.build` 只有 translate+rotate，全仓无该压暗层 [main_view.dart:1459-1463 vs 1555-1615]。docs/41 §3.5 也点过这条。
2. **dutyStateLabel 与 dutyBreathing 为零引用死代码** [card_skins.dart:3124, 4542]。

## 10 · 提案必须知道的硬约束

1. **尺寸天花板**：148×240，卡桌 334 / 390 基准安全带 346 → **只剩 12px**；再高压脸。
2. **性能红线**：卡边禁 MaskFilter、整卡禁 Opacity/saveLayer/BackdropFilter、噪点必须静态缓存、光包 15fps。
3. **所有 α 是模拟器标定值**，需真机复核（.03~.05 会被深底+低亮度吃掉）[docs/40 §7.4]。
4. **颜色不新开**：只有青系 + 稀有度七色 + 黑白（只以 α 出现），稀有度色只进印位/星轨/角饰/铸面晕 [docs/40 §3.11]。
