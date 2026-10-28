# tools/audio — 离线音效烘焙（原型 Web Audio → App 可播素材）

把 `prototype/opus-v2-dir/js/audio.js` 里**现场合成**的那套音效，用离线脚本烘成
`app/assets/audio/*.wav`：参数照原型抄，**零依赖**（只用 `node:` 内置模块，不需要 `npm install`），
**同 `--seed` 逐字节可复现**。

- 烘焙器：`gen_sfx.mjs`（Node ≥ 18，实测 v22.19.0）
- 实测器：`inspect_wav.mjs`（读回 WAV 头 + 算 peak/RMS/DC/削顶 + 无缝循环接缝 + FFT 主频）

> **2026-10-28 追加（docs/49 A6）**：v3 界面用的是参考稿 `宿主养成系统_重设计.html` 那套音效，
> 已逐条转写进本脚本（`REF` 表，master 链按参考稿 gain .55 + 压缩 −14dB/4:1），产出 39 件 `ref_*.wav`：
> `click soft hover swipe whoosh tick beat success error coin buy stamp crit levelup unlock fail boot scan`
> + `ref_type_0..3` + `ref_boop_0..8` + `ref_hold_0..7`。`sfx.dart` 直接按参考稿音名取这一套。
> 只重烤这一组：`node tools/audio/gen_sfx.mjs --only $(node tools/audio/gen_sfx.mjs --list | grep ^ref_ | cut -f1 | paste -sd, -)`

## 用法

```bash
node tools/audio/gen_sfx.mjs --seed 1                       # 全量重烤（84 件，约 1.9 MB，~3s）
node tools/audio/gen_sfx.mjs --seed 1 --only tap,land,impact # 只重烤指定几件
node tools/audio/gen_sfx.mjs --seed 7                        # 换一手随机（抽卡）
node tools/audio/gen_sfx.mjs --list                          # 只列清单不写文件
node tools/audio/gen_sfx.mjs --raw                           # 跳过 master 链（听裸层叠加，调试用）
node tools/audio/gen_sfx.mjs --out /tmp/sfx                  # 换输出目录（不动 app/）

node tools/audio/inspect_wav.mjs                             # 实测表（默认扫 app/assets/audio）
node tools/audio/inspect_wav.mjs --md                        # 同表，markdown（可直接贴文档）
node tools/audio/inspect_wav.mjs --spec rung_0,ding,tap      # FFT 主频校验
```

## 产出清单（84 件 / 1 971 854 字节 = 1.881 MB）

| 组 | 文件名 | 件数 |
|---|---|---|
| 高频 12 件 | `tap` `choose` `land` `seal` `ding` `impact` `crit` `levelup` `fail`（单文件）+ `rank_0..rank_6`（7 档）+ `rung_0..rung_4`（5 档）+ `count_0..count_2`（3 变体） | 26 |
| 备用 | `rank.wav`（= i=2 中档）—— **⚠️ 目前不被总线引用**（独立验收 N1 更正：`sfx.dart` 的 `_pick` 在 `variant == null` 时是**随机取一条变体**，所以这个文件永远不会被播；留档备用，想省 50KB 可直接删） | 1 |
| 逐字音节 | `syl_<emotion>_<0..3>`，12 情绪 × 4 变体：`neutral smug cold annoyed pleased tsun joy proud surprised sad focus sleep` | 48 |
| 环境底噪 | `ambient_loop.wav` | 1 |
| 追加两件 | `boot.wav`（启动）`hold.wav`（按住每步） | 2 |
| 批次③ 补件 | `ignite_0.wav` … `ignite_7.wav`（点环音 8 档；`flows.js:90` 开机逐环点亮） | 8 |
| **合计** | | **84** |

覆盖检查（需要 84 / 实有 84 / 缺 0 / 多余 0）：

```
$ node -e "...need vs have..."
需要 84 实有 84 缺 无 多余 无
$ ls app/assets/audio/*.wav | wc -l
84
$ du -sb app/assets/audio
1971854
```

命名约定（播放总线按此查表）：`<event>.wav`、带变体 `<event>_<n>.wav`（n 从 0 起）、
逐字音节 `syl_<emotion>_<n>.wav`、底噪 `ambient_loop.wav`。

---

## 一、实测表（从写好的 16-bit PCM 读回，不是合成中间量）

`$ node tools/audio/inspect_wav.mjs --md`

| # | 文件 | 采样率 | 时长 s | 峰值(线性) | 峰值 dBFS | RMS dBFS | DC | 削顶 | 字节 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `ambient_loop.wav` | 22050 | 7.143 | 0.0356 | -28.98 | -38.26 | -4.0e-8 | 0 | 315044 |
| 2 | `boot.wav` | 22050 | 3.650 | 0.1736 | -15.21 | -33.26 | -1.1e-5 | 0 | 161010 |
| 3 | `choose.wav` | 44100 | 0.190 | 0.0386 | -28.27 | -45.23 | -9.1e-7 | 0 | 16802 |
| 4 | `count_0.wav` | 44100 | 0.035 | 0.0189 | -34.46 | -48.21 | 4.4e-6 | 0 | 3132 |
| 5 | `count_1.wav` | 44100 | 0.035 | 0.0194 | -34.23 | -48.25 | 9.3e-7 | 0 | 3132 |
| 6 | `count_2.wav` | 44100 | 0.035 | 0.0195 | -34.21 | -48.20 | 8.3e-7 | 0 | 3132 |
| 7 | `crit.wav` | 44100 | 0.870 | 0.3223 | -9.83 | -32.42 | -3.9e-4 | 0 | 76778 |
| 8 | `ding.wav` | 22050 | 1.510 | 0.1622 | -15.80 | -33.80 | 1.0e-6 | 0 | 66636 |
| 9 | `fail.wav` | 22050 | 1.710 | 0.1011 | -19.90 | -34.36 | -1.6e-5 | 0 | 75456 |
| 10 | `hold.wav` | 44100 | 0.050 | 0.0245 | -32.20 | -46.05 | 1.0e-6 | 0 | 4454 |
| 11 | `ignite_0.wav` | 22050 | 1.110 | 0.0798 | -21.96 | -38.47 | 6.9e-6 | 0 | 48996 |
| 12 | `ignite_1.wav` | 22050 | 1.110 | 0.0764 | -22.34 | -38.47 | 2.9e-6 | 0 | 48996 |
| 13 | `ignite_2.wav` | 22050 | 1.110 | 0.0771 | -22.26 | -38.47 | -4.9e-6 | 0 | 48996 |
| 14 | `ignite_3.wav` | 22050 | 1.110 | 0.0759 | -22.40 | -38.47 | 3.2e-6 | 0 | 48996 |
| 15 | `ignite_4.wav` | 22050 | 1.110 | 0.0760 | -22.39 | -38.47 | -1.0e-6 | 0 | 48996 |
| 16 | `ignite_5.wav` | 22050 | 1.110 | 0.0773 | -22.24 | -38.47 | 2.1e-6 | 0 | 48996 |
| 17 | `ignite_6.wav` | 22050 | 1.110 | 0.0778 | -22.18 | -38.47 | -1.8e-6 | 0 | 48996 |
| 18 | `ignite_7.wav` | 22050 | 1.110 | 0.0770 | -22.27 | -38.47 | 1.3e-6 | 0 | 48996 |
| 19 | `impact.wav` | 22050 | 1.290 | 0.3622 | -8.82 | -29.32 | -2.2e-4 | 0 | 56934 |
| 20 | `land.wav` | 44100 | 0.430 | 0.2441 | -12.25 | -28.20 | -4.4e-4 | 0 | 37970 |
| 21 | `levelup.wav` | 22050 | 1.210 | 0.0798 | -21.96 | -37.50 | 1.9e-6 | 0 | 53406 |
| 22 | `rank.wav` | 22050 | 1.170 | 0.1855 | -14.63 | -33.42 | -1.7e-4 | 0 | 51642 |
| 23 | `rank_0.wav` | 22050 | 0.870 | 0.1445 | -16.80 | -34.82 | -1.9e-4 | 0 | 38412 |
| 24 | `rank_1.wav` | 22050 | 1.020 | 0.1837 | -14.72 | -34.05 | -1.8e-4 | 0 | 45026 |
| 25 | `rank_2.wav` | 22050 | 1.170 | 0.1855 | -14.63 | -33.42 | -1.7e-4 | 0 | 51642 |
| 26 | `rank_3.wav` | 22050 | 1.320 | 0.2159 | -13.32 | -32.86 | -1.7e-4 | 0 | 58256 |
| 27 | `rank_4.wav` | 22050 | 1.470 | 0.2383 | -12.46 | -32.38 | -1.7e-4 | 0 | 64872 |
| 28 | `rank_5.wav` | 22050 | 1.620 | 0.2606 | -11.68 | -31.94 | -1.6e-4 | 0 | 71486 |
| 29 | `rank_6.wav` | 22050 | 1.770 | 0.2774 | -11.14 | -31.59 | -1.6e-4 | 0 | 78102 |
| 30 | `rung_0.wav` | 44100 | 0.080 | 0.0555 | -25.11 | -39.29 | -7.7e-5 | 0 | 7100 |
| 31 | `rung_1.wav` | 44100 | 0.080 | 0.0512 | -25.81 | -39.28 | -1.5e-4 | 0 | 7100 |
| 32 | `rung_2.wav` | 44100 | 0.080 | 0.0551 | -25.18 | -39.28 | 1.3e-5 | 0 | 7100 |
| 33 | `rung_3.wav` | 44100 | 0.080 | 0.0529 | -25.53 | -39.27 | 8.8e-5 | 0 | 7100 |
| 34 | `rung_4.wav` | 44100 | 0.080 | 0.0566 | -24.94 | -39.25 | -5.9e-5 | 0 | 7100 |
| 35 | `seal.wav` | 22050 | 1.255 | 0.2618 | -11.64 | -31.97 | -8.7e-5 | 0 | 55390 |
| 36–83 | `syl_*.wav`（48 件，逐字音节） | 22050 | 0.070 | 0.0193–0.0217 | -34.28…-33.27 | -50.44…-49.89 | ≤4.4e-5 | 0 | 各 3132 |
| 84 | `tap.wav` | 44100 | 0.060 | 0.0352 | -29.06 | -43.47 | -3.6e-6 | 0 | 5336 |

合计 84 个文件 / 1971854 字节 = 1925.6 KB = 1.881 MB

```
✅ 全部通过：PCM/单声道/16-bit/头自洽/无削顶/DC≈0
```

**响度关系照原型 `vol`，没有拉平**（Lead 明确要求：忠实复刻优先于数字好看）：

| 事件 | 原型 `vol` | 实测峰值 | 说明 |
|---|---|---|---|
| `tap` | 0.04 | 0.035 | 打点/轻触 |
| `count` | 0.016 | 0.019 | 滚数（每 55ms 一发，必须最轻） |
| `ding` | 0.14 / 0.05 / 0.02 | 0.162 | 派单叮 |
| `land` | 0.38 (+noise .14) | 0.244 | 落板 |
| `impact` | 0.5 (+noise .2) | 0.362 | 结算砸印，**全库最响** |
| `seal` | 0.34 | 0.262 | 按满接单 |
| `rank_0→rank_6` | 0.2→0.38 | 0.145→0.277 | 越高越重（单调 ✓） |
| `ignite_0→ignite_7` | 0.07（+ 0.02 泛音） | 0.0759→0.0798 | **8 档几乎等响**（差 0.44 dB）：原型 8 档只换音高、不改 `vol`，所以逐环点亮是"一串等响的音阶"，不是渐强 |

`impact` / `tap` 实测峰值比 = **10.3×**（原型 `vol` 比 12.5×）——差在 master 链的压缩器按原样
吃掉了瞬态，**没有为了对齐倍数去手改响度**。同文件 `--raw`（跳过 master 链）对比：

```
$ node tools/audio/gen_sfx.mjs --seed 1 --raw --only impact,tap --out /tmp/sfx_raw
$ node tools/audio/inspect_wav.mjs /tmp/sfx_raw
1   impact.wav   22050  1.290  0.5539  -5.13  -23.64  0  56934
2   tap.wav      44100  0.060  0.0391  -28.15 -42.56  0   5336
```

---

## 二、主频校验：证明烘的**就是原型写的那个音高**

`$ node tools/audio/inspect_wav.mjs --spec rung_0,rung_1,rung_2,rung_3,rung_4,ding,tap,count_0,count_1,count_2,rank_0,rank_6,seal,impact,land,fail,levelup,syl_neutral_0,syl_sleep_0,syl_joy_0,hold`

```
rung_0.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)
   主峰: 300.3Hz(0.0dB)  900.9Hz(-9.2dB)  1501.1Hz(-13.1dB)  2100.3Hz(-16.2dB)  2699.0Hz(-19.4dB)
rung_1.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)
   主峰: 344.6Hz(0.0dB)  1033.8Hz(-9.0dB)  1722.9Hz(-12.5dB)  2412.2Hz(-15.7dB)  3101.3Hz(-20.8dB)
rung_2.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)
   主峰: 395.0Hz(0.0dB)  1186.9Hz(-8.1dB)  1979.6Hz(-11.7dB)  2771.9Hz(-16.7dB)  3562.0Hz(-23.4dB)
rung_3.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)
   主峰: 454.2Hz(0.0dB)  1363.1Hz(-9.0dB)  2274.3Hz(-13.3dB)  3183.8Hz(-19.1dB)  4092.1Hz(-26.0dB)
rung_4.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)
   主峰: 521.3Hz(0.0dB)  1568.0Hz(-8.2dB)  2610.7Hz(-13.6dB)  3657.2Hz(-21.5dB)  4700.1Hz(-29.2dB)
ding.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 2093.1Hz(0.0dB)  3135.9Hz(-10.9dB)  4185.9Hz(-29.1dB)
tap.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)
   主峰: 1244.5Hz(0.0dB)  1091.8Hz(-32.2dB)
count_0.wav  (FFT n=1024, 分辨率 43.1Hz, 起点 0s)
   主峰: 1886.2Hz(0.0dB)  5651.7Hz(-15.7dB)  9424.0Hz(-32.5dB)
count_1.wav  (FFT n=1024, 分辨率 43.1Hz, 起点 0s)
   主峰: 1815.2Hz(0.0dB)  5450.5Hz(-15.4dB)  9083.6Hz(-31.3dB)
count_2.wav  (FFT n=1024, 分辨率 43.1Hz, 起点 0s)
   主峰: 1916.2Hz(0.0dB)  5748.7Hz(-16.0dB)  9581.2Hz(-33.0dB)
rank_0.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 783.9Hz(0.0dB)  587.9Hz(-1.5dB)  493.9Hz(-2.8dB)  68.4Hz(-3.4dB)  392.1Hz(-3.5dB)
rank_6.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 71.2Hz(0.0dB)  1176.1Hz(-1.4dB)  987.8Hz(-1.9dB)  1568.0Hz(-2.0dB)  783.9Hz(-3.0dB)
seal.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 62.6Hz(0.0dB)  587.2Hz(-1.4dB)  439.9Hz(-2.9dB)  293.6Hz(-3.1dB)  369.9Hz(-3.5dB)
impact.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 103.8Hz(0.0dB)  2637.1Hz(-9.0dB)  1760.1Hz(-9.2dB)  1318.6Hz(-10.2dB)
land.wav  (FFT n=8192, 分辨率 5.4Hz, 起点 0s)
   主峰: 82.4Hz(0.0dB)
fail.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 94.2Hz(0.0dB)
levelup.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 783.9Hz(0.0dB)  659.3Hz(-0.3dB)  1046.6Hz(-4.2dB)  523.2Hz(-5.3dB)  1319.2Hz(-15.7dB)
syl_neutral_0.wav  (FFT n=1024, 分辨率 21.5Hz, 起点 0s)   ← PITCH.neutral 560 × rand(.92,1.08)
   主峰: 544.4Hz(0.0dB)  1636.9Hz(-4.5dB)  2728.3Hz(-16.7dB)  3819.1Hz(-24.5dB)  4912.6Hz(-30.7dB)
syl_sleep_0.wav  (FFT n=1024, 分辨率 21.5Hz, 起点 0s)     ← PITCH.sleep 300 × rand
   主峰: 289.8Hz(0.0dB)  870.5Hz(-4.2dB)  1451.8Hz(-15.7dB)  2037.0Hz(-23.1dB)  2623.2Hz(-28.6dB)
syl_joy_0.wav  (FFT n=1024, 分辨率 21.5Hz, 起点 0s)       ← PITCH.joy 700 × rand
   主峰: 737.6Hz(0.0dB)  2214.2Hz(-5.9dB)  3686.6Hz(-18.9dB)  5157.8Hz(-28.3dB)
hold.wav  (FFT n=2048, 分辨率 21.5Hz, 起点 0s)            ← 600 + x·500, x=0
   主峰: 600.6Hz(0.0dB)  1800.7Hz(-8.8dB)  2999.1Hz(-13.7dB)  4199.7Hz(-21.6dB)  5400.9Hz(-29.2dB)
```

> 上为 `inspect_wav.mjs --spec` 的**逐字输出**（只在行尾加了 ← 标注，未改动任何数字）。

逐条核对（原型 → 实测）：

| 事件 | 原型频率 | 实测主峰 | 结论 |
|---|---|---|---|
| `rung_0..4` | `300·2^(x/5)` = 300 / 344.6 / 395.8 / 454.7 / 522.4 | 300.3 / 344.6 / 395.0 / 454.2 / 521.3 | ✓（分辨率 21.5Hz） |
| `ding` | 2093 / 3136 / 4186 | 2093.1 / 3135.9 / 4185.9 | ✓ 三音全中 |
| `levelup` | 523.3 / 659.3 / 784 / 1046.5 / 1318.5 | 523.2 / 659.3 / 783.9 / 1046.6 / 1319.2 | ✓ 五音全中 |
| `rank_0` | 392 的 ×1 / ×1.26 / ×1.5 / ×2 = 392 / 493.9 / 588 / 784 + 低频 80→45 | 392.1 / 493.9 / 587.9 / 783.9 + 68.4 | ✓ 和弦四条全中 |
| `seal` | 293.7 / 370 / 440 / 587.3 + 70→44 | 293.6 / 369.9 / 439.9 / 587.2 + 62.6 | ✓ |
| `impact` | 1318.5 / 1760 / 2637 + 130→36 | 1318.6 / 1760.1 / 2637.1 + 103.8 | ✓ |
| `count_0..2` | `1700+rand·300` ∈ [1700,2000] | 1886 / 1815 / 1916 | ✓ 三发互不相同 |
| `land` | 96→40 滑音 | 82.4（窗内平均） | ✓ |
| `fail` | 98→69，slide 1.5s | 94.2 | ✓ |
| `ignite_0..7` | 见下（批次③ 补件小节，8 档全测） | 523.2 / 587.2 / 659.3 / 783.9 / 880.0 / 1046.6 / 1174.6 / 1318.6 | ✓ 8/8 |

### 批次③ 补件：`ignite_0..7` 逐档主频（8/8 命中，每档都测，没有抽样）

`$ node tools/audio/inspect_wav.mjs --spec ignite_0,ignite_1,ignite_2,ignite_3,ignite_4,ignite_5,ignite_6,ignite_7`

```
ignite_0.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 523.2Hz(0.0dB)  1444.4Hz(-19.8dB)
ignite_1.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 587.2Hz(0.0dB)  1620.8Hz(-20.0dB)
ignite_2.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 659.3Hz(0.0dB)  1819.6Hz(-20.0dB)
ignite_3.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 783.9Hz(0.0dB)  2163.9Hz(-19.6dB)
ignite_4.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 880.0Hz(0.0dB)  2428.7Hz(-20.5dB)
ignite_5.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 1046.6Hz(0.0dB)  2888.3Hz(-19.8dB)
ignite_6.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 1174.6Hz(0.0dB)  3242.2Hz(-20.0dB)
ignite_7.wav  (FFT n=8192, 分辨率 2.7Hz, 起点 0s)
   主峰: 1318.6Hz(0.0dB)  3639.1Hz(-19.9dB)
```

逐档核对（**8/8**，两个 tone 都命中；解析度 2.7Hz + 抛物线插值）：

| 档 `x` | 原型基频 `f`（:89） | 实测主峰 | 偏差 | 原型泛音 `f×2.76` | 实测次峰 | 偏差 |
|---|---|---|---|---|---|---|
| 0 | 523.3 | 523.2 | −0.1 Hz | 1444.31 | 1444.4 | +0.1 |
| 1 | 587.3 | 587.2 | −0.1 | 1620.95 | 1620.8 | −0.1 |
| 2 | 659.3 | 659.3 | 0.0 | 1819.67 | 1819.6 | −0.1 |
| 3 | 784 | 783.9 | −0.1 | 2163.84 | 2163.9 | +0.1 |
| 4 | 880 | 880.0 | 0.0 | 2428.80 | 2428.7 | −0.1 |
| 5 | 1046.5 | 1046.6 | +0.1 | 2888.34 | 2888.3 | 0.0 |
| 6 | 1174.7 | 1174.6 | −0.1 | 3242.17 | 3242.2 | 0.0 |
| 7 | 1318.5 | 1318.6 | +0.1 | 3639.06 | 3639.1 | 0.0 |

> 次峰比主峰低约 20 dB，**这不是 `vol` 比例**（.02/.07 = −10.9 dB）：FFT 是 8192 样本（0.372s）
> 的**窗内能量**，而泛音 `dur .4`、基音 `dur 1.1`，同一条指数包络下泛音在窗内衰减得更快。
> 频率位置对得上（8/8），幅度关系不做等价解读。

---

## 三、参数逐条对照表（事件 → 原型 → 烘焙 → 差异理由）

原型行号均指 `prototype/opus-v2-dir/js/audio.js`。

| 事件 | 原型位置 | 原型参数（原样抄） | 烘焙产物 | 差异 / 理由 |
|---|---|---|---|---|
| `tap` | :74 | `tone{f:1320,f2:1080,dur:.05,vol:.04}` | `tap.wav` 44.1k .060s | 无（+10ms 尾巴，见全局近似 #6） |
| `choose` | :76-78 | `tone{740→1110,.12,.045,triangle}` + `noise{bp 2400→5200,.18,.02}` | `choose.wav` 44.1k .190s | 无 |
| `land` | :93-96 | `tone{96→40,.42,.38,a.004}` + `noise{lowpass 700,.16,.14,a.002}` + `tone{2400,.03,.03}` | `land.wav` 44.1k .430s | 无 |
| `rung` | :97 | `tone{300·2^(x/5),.07,.045,square,lp:2600}` | `rung_0..4`（x=0..4） | 原型 x 是任意步进值；总线要 5 档 → 固定 0..4 |
| `rank` | :98-105 | `tone{80→45,.35+.05i,.2+.03i}` + 和弦 `base[i]×[1,1.26,1.5,2]` `triangle,.8+.15i,.03+.006i,spread.02`；`i≥5` 再加 `noise{6000,.8,.03}` + `tone{base×4,1.4,.02,at.05}` | `rank_0..6`（i=0..6）+ 兜底 `rank.wav`(i=2) | 无（7 档全出，i≥5 的两个附加层也按原型加） |
| `seal` | :107-110 | `tone{70→44,.5,.34}` + 和弦`[293.7,370,440,587.3]` `triangle,1.2,.05,spread.015` + `noise{1800→400,.3,.06}` | `seal.wav` 22.05k 1.255s | 无 |
| `ding` | :79-82 | `tone{2093,1.5,.14,a.003}` `{3136,.9,.05,a.003}` `{4186,.35,.02,a.002}` | `ding.wav` 22.05k 1.510s | 无 |
| `impact` | :113-116 | `tone{130→36,.75,.5,a.003}` + `noise{lowpass 1200→200,.4,.2,a.002}` + 和弦`[1318.5,1760,2637]` `1.2,.022,at.02,spread.03` | `impact.wav` 22.05k 1.290s | 无 |
| `count` | :117 | `tone{1700+rand·300,.025,.016,square,lp:4000}` | `count_0..2`（3 变体） | 原型每发都随机；3 变体由 (seed, 文件名) 派生，可复现 |
| `crit` | :118-122 | `noise{bp 3000→9000,.18,.05,a.15}` + `tone{1567,.5,.08,square,lp:5000,at.16}` + `{2093,.7,.06,at.16}` + `{110→50,.3,.3,at.16}` | `crit.wav` 44.1k .870s | 无 |
| `levelup` | :123-125 | 5 音 `523.3/659.3/784/1046.5/1318.5` `triangle,.7,.055,at:i·.07` + `noise{7000,.9,.02,at.3}` | `levelup.wav` 22.05k 1.210s | 无 |
| `fail` | :128-129 | `tone{98→69,1.7,slide:1.5,.13,a.06}` | `fail.wav` 22.05k 1.710s | 无（时长不超原型） |
| `boot` | :83-87 | `tone{38→112,1.1,slide.9,.3,a.2}` + `noise{bp 300→5200,.95,.06,a.6,q.7}` + 和弦`[220,329.6,440,554.4,659.3]` `triangle,2.6,.045,a.02,at.9,spread.035` + `tone{1760,1.8,.02,at.95}` | `boot.wav` 22.05k 3.650s | 无（本批追加件） |
| `hold` | :133 | `tone{600+x·500,.04,.02,square,lp:3000}` | `hold.wav` 44.1k .050s（x=0） | **单文件只能一个音高**：烘 x=0=600Hz。原型按住时每 1/8 步往上爬 → 要升调需 `hold_0..N` 或播放端改 `rate`（诚实清单 #3） |
| `ignite` | :88-91 | `f = [523.3, 587.3, 659.3, 784, 880, 1046.5, 1174.7, 1318.5][clamp(x\|0, 0, 7)]`；`tone{f, dur:1.1, vol:.07, a:.004}` + `tone{f×2.76, dur:.4, vol:.02, a:.003}` | `ignite_0..7`（x=0..7）22.05k 1.110s | 无（8 档全出，波形参数原样抄）。此 case 原型**没有 `Math.random()`** → 换 `--seed` 也逐字节不变（§4.3）；`flows.js:90` 逐环点亮时 `x = 环序号` |
| 逐字音节 | :194-200 + `PITCH` :183 | `base=PITCH[emo]·rand(.92,1.08)`；`f2=base·rand(.86,1.12)`；`dur .06`；`vol soft?.016:.03`；`square, bp base·2.1, q1.4, a.004` | `syl_<emo>_<0..3>` ×12 情绪 | 只烘 `soft=false`(vol .03)；`soft=true`(.016) 这条路径**没烘**（诚实清单 #4） |
| `ambient` | :157-171 | 4 振荡器 `55/82.41/110.2/164.8` gain `[.5,.35,.18,.08]`、`type i<2?triangle:sine`、`detune (i-1.5)·6` → `lowpass 520 Q2`（LFO `.07Hz ±160`）→ `pg .11` → `amb .32·level` | `ambient_loop.wav` 22.05k 7.143s | LFO `.07→.14Hz`、分音量化到整数周期（见 §五）；**不加宽带噪声层**（原型 L152-156 明确写过：那是手机喇叭上的嘶嘶声，已删） |

### 全局近似（作用于所有文件）

1. **master 链照抄 `audio.js:13-20`，但压缩器是近似**：`gain .9 → lowpass 18000 → compressor(threshold -16dB, ratio 3.5, knee 30dB, attack 3ms, release 250ms)`。
   近似点：① 没有 Web Audio 的 6ms lookahead；② 原型是**全局总线**（同时发声才互相压），这里是**逐文件独立**压缩。
2. **振荡器用 polyBLEP 抗混叠**（方波/锯齿）：原型 Web Audio 振荡器是带限 wavetable，听感上 polyBLEP 更"亮"一点点。**三角波未做带限**（三角谐波按 1/n² 衰减，混叠可忽略）。
3. **噪声源实现不同、统计相同**：原型是 2s 白噪 buffer + `start(t0, Math.random())` 随机偏移；这里是逐样本 xorshift 白噪，起始相位照 `Math.random()` 抽取（所以含噪声的事件会随 seed 变——与原型行为一致）。
4. **滤波器**：用 RBJ biquad。Web Audio 的 `lowpass/highpass` 把 `Q` 当 **dB（谐振高度）**解释、`bandpass` 用传统 Q —— 已按这个语义翻译（原型用到 lowpass `.6/.7/.8/2`、bandpass `1/1.4/2/3`）。
5. **采样率**：短音 44.1k；≥1s 的长音 22.05k（任务卡允许）——`impact/rank/seal/ding/boot/levelup/fail/ambient/syl` 都满足 Nyquist（最高需求：`crit` 噪声到 9kHz → 留在 44.1k；`levelup` 噪声 7kHz、`rank_5/6` 噪声 6kHz 均在 11.025k 之下）。
6. **尾部**：原型 `osc.stop(t0+dur+.05)`，增益在 `dur` 时已到 .0001 → 这里只留 10ms 尾巴防截断，所以每件比原型长 10ms。
7. **没做响度归一化**：全部按原型 `vol` 相对关系原样出口（Lead 明确要求）。

---

## 四、确定性与重烤证据

### 4.1 空目录 → 一条命令重烤出全部（验收口径）

```
$ rm -rf app/assets/audio
$ node tools/audio/gen_sfx.mjs --seed 1
...
  ambient: loop=7.142857s (LFO 0.14Hz = 1 周期), 渲染 2 个 loop 丢第 1 个
    partial 0: 55Hz detune -9c → 54.715Hz → 整数周期量化 54.7400Hz（周期数 391，偏差 0.80 音分）
    partial 1: 82.41Hz detune -3c → 82.267Hz → 整数周期量化 82.3200Hz（周期数 588，偏差 1.11 音分）
    partial 2: 110.2Hz detune +3c → 110.391Hz → 整数周期量化 110.4600Hz（周期数 789，偏差 1.08 音分）
    partial 3: 164.8Hz detune +9c → 165.659Hz → 整数周期量化 165.6200Hz（周期数 1183，偏差 -0.41 音分）
ambient_loop       22050Hz  7.143s  peak 0.036  307.7KB

seed=1  wrote 84 files → E:\repo\system_panel\app\assets\audio
total 1925.6 KB = 1.881 MB
```

全量输出（压缩列举，含每件的采样率/时长/峰值/体积）：

```
tap                44100Hz  0.060s  peak 0.035  5.2KB
choose             44100Hz  0.190s  peak 0.039  16.4KB
land               44100Hz  0.430s  peak 0.244  37.1KB
rung_0..rung_4     44100Hz  0.080s  peak 0.051~0.057  各 6.9KB
rank_0             22050Hz  0.870s  peak 0.145  37.5KB
rank_1             22050Hz  1.020s  peak 0.184  44.0KB
rank_2             22050Hz  1.170s  peak 0.186  50.4KB
rank_3             22050Hz  1.320s  peak 0.216  56.9KB
rank_4             22050Hz  1.470s  peak 0.238  63.4KB
rank_5             22050Hz  1.620s  peak 0.261  69.8KB
rank_6             22050Hz  1.770s  peak 0.277  76.3KB
rank               22050Hz  1.170s  peak 0.186  50.4KB
seal               22050Hz  1.255s  peak 0.262  54.1KB
ding               22050Hz  1.510s  peak 0.162  65.1KB
impact             22050Hz  1.290s  peak 0.362  55.6KB
count_0..count_2   44100Hz  0.035s  peak 0.019  各 3.1KB
crit               44100Hz  0.870s  peak 0.322  75.0KB
levelup            22050Hz  1.210s  peak 0.080  52.2KB
fail               22050Hz  1.710s  peak 0.101  73.7KB
boot               22050Hz  3.650s  peak 0.174  157.2KB
hold               44100Hz  0.050s  peak 0.025  4.3KB
ignite_0..ignite_7 22050Hz  1.110s  peak 0.076~0.080  各 47.8KB
```

### 4.2 逐字节可复现

```
$ find app/assets/audio -name '*.wav' | sort | xargs sha256sum > h1
$ rm -rf app/assets/audio && node tools/audio/gen_sfx.mjs --seed 1
$ find app/assets/audio -name '*.wav' | sort | xargs sha256sum > h2
$ diff -q h1 h2
DETERMINISM: OK (76 文件逐字节一致)
```

### 4.3 `--seed` 的语义：**只移动原型里 `Math.random()` 的地方**

`seed=1` 与 `seed=2` 跑完逐文件比 sha256：

```
same（原型里没有随机量的，换 seed 也逐字节相同，24 件）：
  ambient_loop ding fail hold ignite_0..ignite_7 rank rank_0..rank_4 rung_0..rung_4 tap

DIFF（随 seed 变，60 件）：
  count_0..2          ← 原型 1700+Math.random()*300（随机音高）
  syl_*（48 件）       ← 原型 base×rand(.92,1.08) / f2×rand(.86,1.12)
  boot choose crit impact land levelup rank_5 rank_6 seal
                      ← 原型 noise() 里 s.start(t0, Math.random())（噪声起始相位随机）
```

注意 `rank_5/rank_6` 随 seed 变而 `rank_0..4` 不变 —— 因为原型只在 `i>=5` 那支才加 `noise`。
这条**不是设计意图，是原型行为的忠实结果**。

批次③ 补的 `ignite_0..7` 已按这条实测一遍：`--seed 1` 与 `--seed 2` 各烤一组，
8 件 sha256 逐行 `diff` 为空（原型该 case 没有任何 `Math.random()`）。

### 4.4 WAV 头（`tap.wav` 前 44 字节）

```
52494646 d0140000 57415645 666d7420 10000000 01000100 44ac0000 88580100 02001000 64617461 ac140000
RIFF     size=5332 WAVE     fmt  16      PCM(1) 1ch     44100    88200    align2/16bit data  size=5292
```

`inspect_wav.mjs` 对每件都断言：`audioFormat==1 && channels==1 && bits==16 && RIFF/data 长度自洽 && 削顶==0 && |DC|<1e-3`。

### 4.5 批次③（task-18）：加 8 档 `ignite` 后重烤，**原有 76 件逐字节不变**

先做 pre-flight，证明"不变"不是碰巧——重烤前先验证 `app/assets/audio` 现有 76 件本身就是
**空目录 `--seed 1` 重烤**的产物：

```
$ node tools/audio/gen_sfx.mjs --seed 1 --out <tmp>     # 76 件
$ diff before76.txt pre76.txt                            # 现有 76 件 vs 空目录重烤
（无输出）
```

再加 `ignite_0..7` 的 case（`buildManifest()` 里一张 `IGNITE_F` 表 + 一个 `for`）后全量重烤，
对**原有 76 件**做 sha256 校验（原始输出）：

```
$ cd app/assets/audio
$ sha256sum -c before.check        # before.check = 重烤前那 76 件的哈希
ambient_loop.wav: OK
boot.wav: OK
choose.wav: OK
count_0.wav: OK
...（中间 72 行同形，全 OK）
syl_tsun_3.wav: OK
tap.wav: OK
$ echo $?
0
$ sha256sum -c before.check | grep -c ': OK$'   # 76
$ sha256sum -c before.check | grep -c FAILED    # 0
```

逐行 diff（只比原有 76 件）：

```
$ diff before76.txt after76.txt
（无输出 → 76/76 逐字节不变）
```

**为什么必然不变**：每个文件的随机流由 `(seed, 文件名)` 派生（`makeRng(name)`；dither 用
`dither:<名>`），增删事件**不会移动别的事件的随机数**（脚本头注释的设计意图）；
`ignite` 又不用任何随机量（原型该 case 无 `Math.random()`）。

重烤后的总数与体积（原始输出）：

```
seed=1  wrote 84 files → E:\repo\system_panel\app\assets\audio
total 1925.6 KB = 1.881 MB

$ ls app/assets/audio/*.wav | wc -l
84
$ du -sb app/assets/audio
1971854
```

`ignite_*` 8 件合计 **391 968 字节 = 382.8 KB**（各 48 996 字节）。
全量 84 件重跑 `inspect_wav.mjs` 后仍是 `✅ 全部通过：PCM/单声道/16-bit/头自洽/无削顶/DC≈0`（exit 0）。

8 件的 sha256（`sha256sum ignite_*.wav`，原始输出 —— 8 条互不相同，"等响/等 RMS"不是复制文件）：

```
8c9d2bcd4879030d18c72b04679229bd401a0a1d4255a54ae2d7fc254e4d5734  ignite_0.wav
92d1dd5f0270508d0ec01c25dd014d7a85665327ab8889243170a73a66466132  ignite_1.wav
1cfbcaed7a1fd2867a61ba720029ff585a207f5873859e476211691db72e2b97  ignite_2.wav
14e3addbd527d453773eb6d5bc2ea768abd81693c074b228b69964f0c2214238  ignite_3.wav
ff763f10d198e161ed12d1b4ad7b16a0e01c94769e5f4768750ae5847a984f90  ignite_4.wav
8c0e41407d8522152c52aae204109971e405f9717fd94de4a3b087a1549acfd3  ignite_5.wav
d840866e7b2fc23fa9c0c45db5f682f66c2468756215b3ad8eec38e6d037d088  ignite_6.wav
525fd8a35074b6b3cbcebc64b72c3ce2ce993d2fbd17c4f1f7db73ef9732ec08  ignite_7.wav
```

---

## 五、`ambient_loop.wav` 的无缝循环证据

原型 `ambient()` 的 pad 是 4 个固定分音 + 一个 `0.07Hz` 的 LFO 低频呼吸（周期 14.29s）。
要求「≤8s 且可无缝循环」→ **loop 长度必须是 LFO 周期的整数倍**，所以取
`loop = 1/0.14Hz = 7.142857s = LFO 正好 1 个周期`，并把 4 个分音量化到「在 loop 内正好整数个周期」：

```
partial 0: 55Hz     detune -9c → 54.715Hz  → 量化 54.7400Hz（391 周期，偏差 +0.80 音分）
partial 1: 82.41Hz  detune -3c → 82.267Hz  → 量化 82.3200Hz（588 周期，偏差 +1.11 音分）
partial 2: 110.2Hz  detune +3c → 110.391Hz → 量化 110.4600Hz（789 周期，偏差 +1.08 音分）
partial 3: 164.8Hz  detune +9c → 165.659Hz → 量化 165.6200Hz（1183 周期，偏差 -0.41 音分）
```

再**渲染 2 个 loop、丢掉第 1 个**（让 lowpass 的启动暂态衰减干净），留下的第 2 个 loop
逐样本周期化。实测接缝：

```
[loop] ambient_loop 接缝跳变 |x[0]-x[n-1]| = 3.052e-5，文件内最大相邻差 = 8.240e-4
       → 无缝（接缝小于文件内部的正常样本间跳变）
```

⚠ 按原型 `audio.js:152-156` 的明确警告，**没有**加那层 `白噪 → bandpass(7kHz,Q=.5)` 的
「空气声」——它在手机喇叭上就是一层嘶嘶声。

---

## 六、诚实清单

### 我认为「烘得不像 / 可能不够好」的

1. **`rung` 用 polyBLEP 方波，比原型的带限 wavetable 略亮/略毛**：听感差异应该在手机喇叭上不可闻，
   但耳机上 AB 得出来。若觉得刺，可把 `rung_*` 的 `lp:2600` 降一点（原型值原样保留，我没动）。
2. **`boot.wav` 3.65s 是全库最长**：原型 `chord` 在 `at:.9` + `dur 2.6` 才结束。它是"启动演出"用，
   体积 157KB 可接受；若嫌长可裁到 1.2s（会丢掉尾音）。
3. **`hold.wav` 只有一个音高（600Hz）**：原型 `hold(x)` = `600+x·500` 按住时逐 1/8 步往上爬。
   单文件表达不了阶梯。**建议**：要么总线用 `playbackRate` 按步进改（0 步=1.0，1 步=1.83…），
   要么我补 `hold_0..5`。**我没擅自加命名**，等你定。
4. **`syl_*` 的软音节路径**：`ui.js:96` 对 `soft` 行传 `soft=true` → 原型用 `vol .016`（= 正常 `.03` 的 0.53×）。
   我按你给的命名只出了 `syl_<emo>_<0..3>`（`vol .03`）。**已核对播放总线**：`sfx.dart:157` 对 soft 行用
   `volume * 0.5`，与 0.53 只差 0.5dB —— **这条按总线现有实现已闭环，不需要额外文件**（要更准就把 0.5 改成 0.53）。
5. **主频校验里 `tap` 的峰是 1244Hz**：原型是 `1320→1080` 的 50ms 滑音，FFT 窗（46ms）跨整段扫频，
   谱峰自然落在中间 —— 不是烘错了，是滑音的谱本来就宽。
6. **`ignite_0..7` 是批次③ 新增里最大的一块**：8 件 × 48 996 字节 = 391 968 字节 = 382.8 KB
   （总包 1.507 → 1.881 MB）。按"事件分组"算它是全库第二大块，`rank_0..6` 7 件共 407 796 字节更重。
   原型频率表是**固定 8 档**，我没擅自合并成 1 件 + 播放端变调；若嫌大，可选
   `rate` 变调只留 1~2 件，或把这 8 件降到 11.025k（最高分量 3639 Hz，够）。
7. **`ignite` 8 档是"等响音阶"，不是渐强**：原型 8 档只换 `f`、`vol` 一律 `.07`，实测峰值
   0.0759~0.0798（差 0.44 dB）。若"逐环点亮"想要越来越亮，得改原型参数或播放端乘增益——我没动。
8. **`ignite` 8 件的 RMS 完全相同（-38.47 dBFS，2 位小数）**：包络与幅度逐样本一致、只有频率不同，
   这是"同一条包络换音高"的必然结果，不是复制粘贴——8 件的 sha256 互不相同（见 §4.5）。

### 哪些是**猜的 / 自己定的**（原型没写、我做了决定）

1. **loop 长度 7.142857s 与 LFO `0.14Hz`**：原型是 `0.07Hz`。这是"≤8s 且无缝"的硬约束推出来的
   （loop 必须是 LFO 周期的整数倍），等价于把呼吸从 14.3s 缩到 7.1s。**这是我改的唯一一个原型参数**，
   理由是任务卡的「可无缝循环」优先。
2. **分音量化到整数周期**（偏差 ≤1.11 音分）：原型没有这个动作，是循环无缝的必要代价。
3. **压缩器参数**（attack 3ms / release 250ms）：原型只写了 threshold/ratio/knee，attack/release 是
   Web Audio 的默认值，我按默认值取（`audio.js` 没设这两个字段）。
4. **每件加 10ms 尾巴**：原型 `stop(t0+dur+.05)`，我取 10ms（增益在 `dur` 已到 .0001，50ms 是纯静音）。
5. **`rank.wav`（i=2 中档）= 备用，不是兜底**：独立验收（`.verify/batch2/` N1）指出
   `sfx.dart` 的 `_pick` 在 `variant == null` 时是**随机取一条变体**，所以这个文件
   **永远不会被播**。原写法（"不带 variant 时的兜底"）与实现不符，已更正为"备用/留档"；
   想省 50KB 可删，删前确认 `app/lib/state/sfx.dart` 的 rank 表只列 `rank_0..6`。
6. **`--only` / `--out` / `--raw` / `--list` / `--seed` 这些 CLI** 都是我自己定的形状，没有原型依据。
7. **TPDF dither 的随机流不带 seed**（固定按文件名派生）：故意这样，好让"换 seed 只影响原型里
   真随机的地方"这条性质可验证（§4.3）。dither 是 ±1 LSB，不影响响度。

### 哪些**明确是近似的**

见 §三「全局近似」1–7 七条：压缩器（无 lookahead + 逐文件压缩）、polyBLEP、
三角未带限、噪声源实现、低通 Q 的 dB 语义、长音的 22.05k 采样率、10ms 尾巴。

### 我没做的（不在 task-7 范围；`ignite` 已按批次③ task-18 划掉）

原型 `audio.js` 里还有 `soft / boot(做了) / ~~ignite~~(批次③ task-18 已补 8 档，见 §一/§二/§三) / whoosh / engrave / scan / coin / title / poke /
shutter / deny / unhold` 与 `drone()` 两条连续音、`muffle()`（失败时把整个世界的高频拿走）——本批 12+2 件之外的一律没烘。
按需可扩（加一行 `add(...)` + 跑一次）。

---

## 七、与播放总线（`app/lib/state/sfx.dart`）的接口核对

烘焙完只读核对了 Lead 的查表（**没有改它**），逐条命中：

| 总线 key | 总线要的文件 | 实有 | 备注 |
|---|---|---|---|
| `tap` | `audio/tap.wav` | ✓ | |
| `choose` | `audio/choose.wav` | ✓ | |
| `land` | `audio/land.wav` | ✓ | 委托单落板 |
| `rung` | `audio/rung_0.wav`…`rung_4.wav`（5） | ✓ | `variant.clamp(0,4)` |
| `rank` | `audio/rank_0.wav`…`rank_6.wav`（7） | ✓ | F~S = i=0..6 |
| `seal` | `audio/seal.wav` | ✓ | |
| `publish` | `audio/ding.wav` | ✓ | 总线把 key 叫 `publish`、文件仍叫 `ding` —— 对得上 |
| `impact` | `audio/impact.wav` | ✓ | |
| `count` | `audio/count_0.wav`…`count_2.wav`（3） | ✓ | `_rnd.nextInt(3)` |
| `crit` | `audio/crit.wav` | ✓ | |
| `levelup` | `audio/levelup.wav` | ✓ | |
| `fail` | `audio/fail.wav` | ✓ | |
| `ambient` | `audio/ambient_loop.wav` | ✓ | `ReleaseMode.loop`；总线额外 `volume*0.5`，若嫌底噪浅可去掉那 0.5（或让我 +6dB 重烤） |
| `syllable` | `audio/syl_<情绪>_<0..3>.wav`（48） | ✓ | 情绪串与 `persona.emotions` 一致 |
| `ignite` | `audio/ignite_0.wav` … `audio/ignite_7.wav`（8） | ✓ | 批次③ 补件（task-18）：`main.dart` 的 `_igniteRings()` 调 `Sound.play('ignite', i)`（i = 环序号，对应原型 `clamp(x\|0,0,7)`）。**命名与总线已对表**：`sfx.dart:67-76` 的 `'ignite'` 表正好列这 8 条，磁盘 8 件全在（我烘焙侧只读核对，未改 `app/lib/**`） |

总线表在批次②口径下引用 **73** 件，全部实有；另有 **3 件总线暂未使用**：`boot.wav`（R5 预留）、
`hold.wav`（`docs/22 §10-G-2`：本批「按住」只用震动）、`rank.wav`（**备用留档**，
`_pick` 在无 variant 时随机取变体 → 它不会被播，见上面第 5 条更正）。73 + 3 = 76 ✓。
批次③ 的 8 件 `ignite_*` 另计：76 + 8 = **84** ✓（目录实有 84）。
