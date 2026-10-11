# 29 · ComfyUI 重设计：功能自然语言说明 + 提示词集

> 落地日期：2026-10-11 · 管线：**Qwen-Image 2.1 + 2x-AnimeSharpV4**（`tools/comfyui/`）
> 提示词真源：`tools/comfyui/prompts/shots.json` · 批量脚本：`tools/comfyui/gen_shots.mjs`
> 视觉对象：`prototype/opus-v2-dir/`（宿主最终选定的那一版：全息舞台 + 环套在她身上）

---

## 0 · 这份东西是什么，怎么用

**是什么**：把 `opus-v2-dir` 原型里**每一个功能时刻**先用中文讲清楚（她怎么演、屏幕上演什么、手感从哪来），再把每一镜翻译成**可直接投进 ComfyUI 的英文提示词**。要求按宿主指定：**游戏化**、**背景是 Live2D 舞台**、**画面里有虚拟娘**。

**不是什么**：不是最终素材，也不是要拿生成的图去切图做 App。生成物只有两种用途——

| 用途 | 哪些镜 | 说明 |
|---|---|---|
| **真素材**，直接替换进原型 | `A0-bg-void` / `A1-fx-burst` / `A2-stamp-crit` / `A3-glitch` | 垫底层与粒子，符合仓库既有约定（无人物、无文字、中心留白） |
| **概念参照**，给 CSS / Flutter 对齐 | 其余 26 镜 | 界面本身仍然由 CSS（原型）与 Flutter Widget（`app/`）实现，图只用来对齐气质、层次、稀有度用法 |

**三步跑起来**：

```powershell
# ① 看清单（不需要 ComfyUI 在线）
node tools/comfyui/gen_shots.mjs --list

# ② 看某一镜拼装好的完整提示词（手动粘进 ComfyUI GUI 用这个）
node tools/comfyui/gen_shots.mjs --print S10-settle

# ③ 出图（需要 ComfyUI 在 127.0.0.1:8188 在线）
node tools/comfyui/gen_shots.mjs --shot S10-settle
node tools/comfyui/gen_shots.mjs --group 整屏时刻          # 24 张
node tools/comfyui/gen_shots.mjs --all --out E:\tmp        # 30 张全出
```

产物落 `tools/comfyui/.out/SystemShots/`，PNG 母版**不入库**（沿用 `tools/comfyui/README.md` 的约定）。

---

## 1 · 三把锁：所有提示词都由这三段拼出来

> ⚠️ 仓库踩过的坑：**连续生成同类提示词会串台**（见 AGENTS.md 的 Stitch 一节）。所以每一镜都不是自由发挥，而是 `STYLE LOCK + CHARACTER LOCK + 本镜变化段` 三段拼接。`gen_shots.mjs` 自动拼，人工改词只改第三段。

### 1.1 STYLE LOCK（每一镜都带）

```
Vertical mobile game key visual, portrait 9:19.5 composition. Art direction: a vast deep
navy-blue void (#0A0E1A) fading to near-black (#020409) at the edges, electric cyan (#38E1FF)
as the single dominant accent, pale ice-cyan (#9FF0FF) highlights and near-white (#E9FBFF)
bloom. Gamified holographic sci-fi interface language: semi-transparent glass panels with
bevelled chamfered corners and thin glowing cyan edges, hairline hexagonal data lattice, faint
horizontal scanlines, a thin cyan wireframe floor grid receding toward a glowing horizon,
volumetric cyan light shafts, drifting luminous particles and small cyan bokeh, soft vignette,
very dark and low contrast in the background so bright user-interface text stays readable.
Rarity colour system reserved strictly as signal, never as ambience: F gray #9AA3B2, E green
#4ADE80, D blue #38BDF8, C purple #A78BFA, B gold #FBBF24, A orange #FB923C, S red #FF4D5E.
Cinematic lighting, crisp anime line art, ultra-detailed polished digital painting, premium
sci-fi game user interface, high-end mobile game key art.
```

这一段同时承担三件事：**比例**（9:19.5 竖屏，对得上 `prototype/opus-v2-dir` 的 390×844 手机）、**色板**（深蓝虚空 + 电光青，与 `AGENTS.md` 锁定的主题色逐字一致）、**游戏化语言**（玻璃面板 / 斜切角 / 扫描线 / 六边数据纹 / 地面网格 / 稀有度色谱）。

### 1.2 CHARACTER LOCK（有她的镜都带，`use_character: true`）

```
The protagonist is a virtual girl: an anime cel-shaded Live2D-style character with flat clean
line art, cool-toned pale skin, shoulder-length dark navy hair with one electric-cyan highlight
strand, calm half-lidded eyes and a faint condescending smirk, slim build, wearing a simple
dark high-collared sleeveless uniform dress with thin glowing cyan seams and a small chest
emblem, bare arms, no warm ambient light on her skin. She is rendered as a semi-transparent
holographic projection: her silhouette dissolves into fine scanlines and cyan light at the
edges, a thin cyan rim light runs along her contour, with subtle chromatic aberration on the rim.
```

**这一段是虚拟娘的身份证**——平涂 Live2D 上色、冷调皮肤、一撮青色挑染、半透明全息边缘。它是原创设定，**不是**原型里那个现成 Live2D 模型（`live2d/sakiko/`，版权红线，禁止拿去当 prompt 参照）。整屏稿里的她一律照这一段走，不许漂移；漂了就回 `C0-character-sheet` 重锁。

### 1.3 NEGATIVE BASE（每一镜都带）

```
western wanted poster, bounty poster, aged yellow paper, rope, blood stamp, sepia tone, warm
colour dominance, orange and teal grading, neon rainbow gradient, oversaturated, plastic 3D
render, photorealistic, realistic human, extra fingers, deformed hands, distorted face,
asymmetrical eyes, cluttered composition, busy background, high contrast centre, bright
daylight, watermark, signature, logo, jpeg artifacts, low resolution, blurry
```

前六条是**硬约束**：上一轮提示词里一句"像接到一张悬赏令"被字面执行成了西部通缉令（黄纸、绳、血印）。这次从负面词里就把那条路堵死——**分量来自材质与动作，不来自形态**。

### 1.4 文字预算

Qwen-Image 2.1 写中文是强项，但**一屏最多给 6 个短标签**。所以每一镜的 variation 末尾都显式写了 `Text allowed: ...`，其余一律不写进图里——正文、长句、数值格式全部交给 CSS/Flutter 叠字。原型里那些 34ms/字的打字机字幕，永远不会由生图来承担。

### 1.5 中文版三把锁（可选）

> 提示词正文用英文是**故意的**：色值（`#38E1FF`）、构图术语（`portrait 9:19.5` / `front half behind the body`）、负面词权重，英文都更稳。
> 但 Qwen-Image 2.1 是中文模型，中文提示词同样能跑。要中文版就照下面三段替换，变化段按 §3 的中文描述自己串。

**风格锁 · 中文**
```
竖版手游主视觉，9:19.5 竖屏构图。美术方向：深蓝虚空（#0A0E1A）向边缘渐入近黑（#020409），
电光青（#38E1FF）为唯一主强调色，冰青（#9FF0FF）高光与近白（#E9FBFF）辉光。游戏化全息科幻界面语言：
半透明玻璃面板、斜切倒角、细青色发光边、发丝级六边数据纹、极细横向扫描线、向发光地平线退去的
青色线框地面网格、体积青光柱、漂浮光粒与青色散景、柔和暗角，背景整体压暗低对比以保证界面文字可读。
稀有度色谱只作信号不作氛围：F 灰 #9AA3B2、E 绿 #4ADE80、D 蓝 #38BDF8、C 紫 #A78BFA、
B 金 #FBBF24、A 橙 #FB923C、S 红 #FF4D5E。电影级打光，干净动画线稿，超精细厚涂数字绘画，
高级科幻游戏界面，高品质手游主视觉。
```

**角色锁 · 中文**
```
主角是一名虚拟少女：动画赛璐璐平涂的 Live2D 风格角色，线稿干净，冷调白皙肤色，及肩深蓝黑发，
一撮电光青挑染，半睁的平静眼睛配一丝居高临下的讥诮，身形纤细，穿简洁的深色立领无袖制服裙，
裙上有细青色发光缝线与一枚小胸章，手臂裸露，皮肤上没有暖色环境光。她以半透明全息投影呈现：
轮廓边缘溶解进细扫描线与青光，身体轮廓有一圈细青色边缘光，边缘带轻微色散。
```

**负面锁 · 中文**
```
西部通缉令，悬赏海报，泛黄纸张，绳索，血印，棕褐色调，暖色主导，橙青调色，霓虹彩虹渐变，
过饱和，塑料感 3D 渲染，写实照片，真人，多余手指，畸形手，五官扭曲，双眼不对称，构图杂乱，
背景繁杂，中心高对比，明亮日光，水印，签名，标志，JPEG 压缩伪影，低分辨率，模糊
```

---

## 2 · 功能清单 → 分镜对照

30 镜，两组。**左列是原型里真实存在的功能**（出处见 `prototype/opus-v2-dir/js/`），右列是对应的提示词 id。

### 2.1 角色与素材（6 镜）

| 功能（原型出处） | 镜 id | 有她？ |
|---|---|---|
| 系统拟人化本体：全息系统体 · 冷感少女（`stage.js` 的情绪/镜头/全息滤镜） | `C0-character-sheet` | ✓ |
| 参数级情绪：neutral/focus/smug/cold/annoyed/tsun/sad/surprised/pleased/joy/sleep（`stage.js` + `content.js`） | `C1-face-diff` | ✓ |
| 天幕：深蓝虚空 + 轨道环 + 地面网格 + 噪点（`index.html` 的 `#bg`） | `A0-bg-void` | ✗ |
| 粒子：burst / streak / spark / ripple / shock（`fx.js`） | `A1-fx-burst` | ✗ |
| 印章：CRIT ×2 / 双倍卡 ×2（`flows.js` 的 `#rsTags .stamp`） | `A2-stamp-crit` | ✗ |
| glitch 转场与扫描线（`Stage.glitch` / `.grain`） | `A3-glitch` | ✗ |

### 2.2 整屏时刻（24 镜）

| # | 功能（原型出处） | 镜 id |
|---|---|---|
| 1 | 开机自检 · 唤醒（`flows.js boot()` / `wake()`） | `S01-boot` |
| 2 | 绑定仪式 · 报名（`onboard()` 的 wake0~wake2 + choose） | `S02-onboard` |
| 3 | 立目标 · 一句梦话被当场驳回（`makeGoal` 的 `vague` 分支） | `S03-goal` |
| 4 | 拆环 · 环从脚下挂到头顶（`assemble()`） | `S04-rings` |
| 5 | 大厅 · 她记得你走了多久（`_greet()` 的 back10m/back2h/back12h/back36h/backLong） | `S05-lobby` |
| 6 | 派单 · 玻璃板砸落 + 激光刻字（`Plate.land()` / `engrave()`） | `S06-dispatch` |
| 7 | 按住指纹 0.9 秒接单（`Plate.hold()`） | `S07-hold` |
| 8 | 退缩 · 稀有度降一档 + 强制称号（`retreat()` / `reRank()` / `shame()`） | `S08-retreat` |
| 9 | 执行中 · 计时 + 证据槽 + 暴击率 + 道具（`Exec`） | `S09-exec` |
| 10 | 结算 · 稀有度砸落 + EXP 上涨（`settle()` ①~⑤） | `S10-settle` |
| 11 | 暴击 / 双倍卡盖章（`settle()` 的 `res.crit` / `res.dbl`） | `S11-crit` |
| 12 | 升级 · LEVEL UP（`expBar()` / `levelUp()`） | `S12-levelup` |
| 13 | 认输 · 更暗更安静更短（`_fail()`） | `S13-fail` |
| 14 | 补救 · 永远留一条路（`info.remedy`） | `S14-remedy` |
| 15 | 主线全景 · 环套在她身上（`MainV` + `Stage.ringPoint`） | `S15-mainline` |
| 16 | 档案 · 六维雷达 + 称号墙（`Sheet.archive()`） | `S16-archive` |
| 17 | 补给 · 金币唯一去处（`Sheet.supply()`） | `S17-supply` |
| 18 | 系统设置 · 投影光束（`Sheet.system()` + `Beam`） | `S18-system` |
| 19 | 主线达成 · 整轨亮起（`finale()`） | `S19-finale` |
| 20 | 战报 · 900×1600 导出（`shareCard()`） | `S20-share` |
| 21 | 常驻 HUD 与底栏（`HUD` / `Dock` / `#cta`） | `S21-hud` |
| 22 | 打瞌睡 · 没人理她（`doze()` / `undoze()`） | `S22-doze` |
| 23 | 冷场 · 连击断了 / 好几天没来（`Store.mood() === 'cold'`） | `S23-cold` |
| 24 | 今日已清 · 等换日（`Dock.render()` 的 `idle` 分支） | `S24-cleared` |

---

## 3 · 逐镜：自然语言描述 + 提示词变化段

> 下面每一镜给：**这是什么**（功能）、**她怎么演**、**屏幕上是什么**、**提示词变化段**（英文，接在 §1 三把锁之后）。
> 完整可粘贴版本：`node tools/comfyui/gen_shots.mjs --print <id>`。

---

### C0 · 系统娘 · 设定三视图

**这是什么**：她本人的唯一视觉真源。整屏最底层是"她是谁"，后面 20 多屏全部锁这一张。

**她怎么演**：三视图（正面全身 / 四分之三 / 背面）＋ 底部五个头部特写（平静讥诮 / 不耐烦 / 冷淡 / 惊讶 / 柔和满意）。比例、发型、服装必须逐视图一致。

**屏幕上是什么**：纯深蓝底 + 三视图 + 青色细导线 + 空白标注框（框里不写字）。

**提示词变化段**：
```
Character reference sheet on a flat dark navy background, no interface elements at all. Three
views of the same girl side by side: full-body front, full-body three-quarter, full-body back,
plus a row of five head close-ups along the bottom showing her expression range (calm smirk,
annoyed frown, cold flat stare, wide-eyed surprise, softly pleased). Clean turnaround layout,
thin cyan guide lines, small empty annotation boxes with no writing. Identical proportions, hair
and outfit across every view. Text: none.
```
**参数**：1024×1024 · 附加负面 `text, letters, numbers, multiple different characters, inconsistent outfit`

---

### C1 · 表情差分表 · 九种情绪

**这是什么**：她的情绪不是贴纸，是参数级的——眼睑、眼笑、眉（只在动作算出的眉形上叠偏移，绝不写绝对值）、嘴型包络、脸红、呼吸。这张表用来校准九种基准表情。

**她怎么演**：九宫格头肩特写，依次是 平静 / 专注 / 讥诮 / 冷淡 / 不耐烦 / 傲娇别开脸 / 低落 / 惊讶 / 柔和满意。

**提示词变化段**：
```
Expression sheet, head and shoulders only, nine head close-ups arranged in a clean three by
three grid on a flat dark navy background, no interface. The nine expressions in order: neutral
calm, focused narrowed eyes, smug smirk, cold flat stare, annoyed frown, tsundere flustered
blush looking away, sad downcast eyes, wide-eyed surprise, softly pleased smile. Consistent
face, hair and lighting across all nine. Thin cyan separator lines between cells. Text: none.
```
**参数**：1024×1024 · 对不上就以 C0 为准重抽

---

### A0 · 天幕 · 虚空舞台（无人物）

**这是什么**：她身后的世界，整屏最底层，垫在 CSS 的扫描线、噪点、地面网格之下。**她会被合成在正中央，所以中心必须空、必须暗。**

**屏幕上是什么**：上三分之一是一圈正面朝向的巨大全息环阵，中心留空；中间竖着一摞七条椭圆环轨虚影（暗的、虚线的、等着她站进去）；下方是细青网格地面退向发光地平线；粒子、六边数据纹、扫描线、薄雾。

**提示词变化段**：
```
Empty stage background, absolutely no people and no characters and no text. A huge circular
holographic array of thin glowing electric-cyan concentric rings floats in the upper third like
a high-tech summoning circle seen face-on, its centre left completely empty. A vertical stack of
seven faint elliptical ring tracks recedes upward through the middle of the frame, dim and
dashed, empty and waiting. Far below, a barely visible holographic floor of thin cyan grid lines
recedes toward a glowing horizon. Fine luminous particles drift, faint hexagonal data patterns
and subtle scanlines dissolve into darkness, thin wisps of fog catch the light near the floor.
Dead centre stays clean, dark and low contrast.
```
**参数**：768×1664 → 放大 → 落 1080×2340 网页版，**直接替换 `prototype/opus-v2-dir/img/bg-void.jpg`**
**抽卡要点**：中心但凡出现任何结构物就废，重抽。

---

### A1 · 粒子素材 · 辉光与拖尾

**这是什么**：结算炸开、升级、刻字火星、环亮，全靠这几个 sprite。要加色混合友好：黑底、亮核、边缘干净。

**提示词变化段**：
```
Sprite sheet on a pure black background, eight isolated effects laid out in a clean grid,
additive-blend ready, no text: a radial glow burst with a white-hot core, a thin ring shockwave,
a comet trail with a tapering tail, a cluster of soft cyan bokeh, a spray of sharp spark
streaks, a hexagonal shard shatter, a soft light haze puff, and a fine particle dust cloud.
Each effect fully separated with generous black spacing, bright cores fading cleanly to black at
the edges, electric cyan and white.
```
**参数**：1024×1024 · 切图后在 Flutter 侧做 CustomPainter 贴图，不做视频

---

### A2 · 印章纹章 · CRIT / 双倍

**这是什么**：暴击和双倍卡盖章那一下的分量全在这两枚章上。要有**光刻**质感、边缘磨损，不是实体橡皮章。

**提示词变化段**：
```
Two circular emblem stamp designs on a pure black background, isolated and centred, no text
other than the two short uppercase captions. The left stamp is a starburst-edged circular seal
with the word CRIT in bold condensed uppercase across its middle, engraved metallic texture,
distressed worn edges, glowing electric cyan ink. The right stamp is a doubled hexagon seal with
a large multiplication sign in its centre and a short uppercase caption below, engraved, in the
same cyan ink. Hard-edged, high contrast, silkscreen poster quality.
```
**参数**：1024×1024 · S 级红色变体：去掉 cyan、换 `#FF4D5E` 重抽

---

### A3 · glitch 帧与扫描线贴图

**这是什么**：转场、觉醒、S 级降临时那一下信号错乱。要**可平铺**，能被 CSS 或着色器直接叠。

**提示词变化段**：
```
Glitch and overlay texture sheet on a black background, four separate tiles with clean spacing,
no text: a horizontal band of RGB-split scanline corruption in cyan and white, a seamless
tileable fine scanline overlay, a seamless tileable faint hexagonal data lattice, and a blocky
datamosh tear with sharp rectangular displacement. High contrast, crisp, designed to be
composited with additive and screen blending.
```
**参数**：1024×1024 · 四块都要能无缝平铺

---

### S01 · 开机自检 · 唤醒

**这是什么**：打开 App 的第一秒**不是首页**，是开机自检。这一屏的任务是让人意识到：进的是另一个地方，不是打开了一个工具。

**她怎么演**：闭着眼、头微低、竖着悬在一根细青光柱里，整体压到约三分之一亮度、去饱和、边缘化进扫描线。日志滚到「校准良心……未找到，跳过」，底下写「触碰屏幕 · 唤醒系统」。你点一下，她才睁眼。

**屏幕上是什么**：极简自检界面——底部细青进度条、上面四行等宽字体系统日志、右上小时钟、居中一行大写提示 `TOUCH TO WAKE` 带脉冲小环。**没有别的东西。**

**提示词变化段**：
```
She is asleep: eyes closed, head tilted slightly down, floating upright in the centre of the
dark void inside a tall cylindrical containment field of thin cyan light. Her body is dimmed to
about one third brightness, desaturated, edges dissolving into scanlines. Overlaid on the void
is a minimal boot self-test interface: a thin cyan progress bar near the bottom, four short
lines of system log text in a monospaced terminal font stacked above it, a tiny clock at the top
right, and a centred uppercase prompt reading TOUCH TO WAKE with a small pulsing ring around it.
No other interface elements. Text allowed: four short monospaced log lines and one uppercase
prompt.
```
**参数**：768×1664 · 附加负面 `awake eyes, bright colours, cheerful`

---

### S02 · 绑定仪式 · 报名

**这是什么**：首次进入，她刚醒。第一句是「……就你？」，第二句开始问你叫什么。**没有注册页、没有引导浮层、没有「开始使用」按钮**，只有她说话，和两个你回她的按钮。

**她怎么演**：刚睁眼、抬头、直视镜头、嘴角一点讥诮。四分之三身位，站在环轨里。

**屏幕上是什么**：下三分之一两枚叠放的玻璃选择按钮（长条、细青边），上方一条单行对话卡（两行中文台词 + 左侧五格声波图标），身后一个巨大低不透明度的背景大字。

**提示词变化段**：
```
She has just woken: eyes open, head lifted, looking directly at the viewer with a faint smirk,
three-quarter body, standing inside her ring tracks. In the lower third of the screen there are
two stacked glass choice buttons, each a long translucent bar with a thin cyan edge, and above
them a single-line dialogue card holding two short lines of Simplified Chinese dialogue in a
clean sans-serif, with a small five-bar audio waveform icon at its left. Behind her, a very
large word in a thin display typeface sits at low opacity. Text allowed: two short Simplified
Chinese button labels and two short Simplified Chinese dialogue lines.
```
**参数**：768×1664 · 附加负面 `registration form, onboarding tutorial overlay, start button, checkbox list`

---

### S03 · 立目标 · 一句梦话被当场驳回

**这是什么**：宿主输入一句话目标，比如「变优秀」。她当场驳回——太虚了，拆不动。这一屏要让人知道：**这个系统不陪你许愿，它只接能拆成环的目标。**

**她怎么演**：微微前倾、皱眉、抬一只手像在驳回一个念头。

**屏幕上是什么**：下三分之一一条发光输入框，上方四枚圆角玻璃预设词胶囊；再上方一条对话卡。

**提示词变化段**：
```
She leans forward slightly with an annoyed frown, one eyebrow raised, one hand lifted as if
rejecting an idea. In the lower third of the screen there is a glowing text input bar with a row
of four small rounded glass preset chips above it, each holding a short Simplified Chinese
phrase. A dialogue card above the input holds one short line of Simplified Chinese dialogue.
Behind her the faint background word is being overwritten by a new one. Text allowed: four short
Simplified Chinese preset phrases, one input placeholder, one short Simplified Chinese dialogue
line.
```
**参数**：768×1664 · 她的表情是**不耐烦**，不是生气

---

### S04 · 拆环 · 环从脚下挂到头顶

**这是什么**：全屏最用力的一处。一句话目标被她拆成 5~8 环，一环一环从脚下挂到头顶，每亮一环「叮」一声，最后最高那一环亮起时放烟花。

**她怎么演**：全身站在正中央，**站在环里面**——每条环的前半圈画在她身前、后半圈画在她身后。

**屏幕上是什么**：七条同心椭圆光轨，亮度随高度递减（脚下实心炽亮、头顶虚线暗轨）；每条环右端挂一枚小标签（R1~R7）。

**提示词变化段**：
```
Wide full-body shot: she stands at the exact centre while seven concentric elliptical
holographic rings ignite one after another from her feet up to above her head. Each ring is a
thin glowing cyan track with tick marks; the front half of every ring is drawn in front of her
body and the back half behind it, so she stands inside them. Brightness steps down with height:
the lowest rings are solid and blazing, the highest are dashed and dim. Small floating label
tags hang at the right end of each ring. A wide cyan particle burst and a white flash at the
highest ring. Text allowed: seven tiny ring index labels reading R1 through R7.
```
**参数**：768×1664 · 附加负面 `progress bar, linear progress track, dashboard`
**验收点**：如果她看起来是"贴在一张画着环的图上"，这一张就废了——环必须在她身前身后各画半圈。

---

### S05 · 大厅 · 她记得你走了多久

**这是什么**：日常待机。你回来，她先念出你走了多久（10 分钟 / 2 小时 / 12 小时 / 36 小时 / 好几天，语气逐档变冷）。四周浮着常驻 HUD。

**她怎么演**：放松站姿、重心压一条腿、视线略微偏开，脚下一圈环轨亮着。

**屏幕上是什么**：左上六边等级牌（细经验弧 + 数字）、中上你的名字＋称号＋连击计数、右上六边金币、中上一枚执行中计时 pill；底部导航条＝左侧三个小图标页签 + 中央一颗被两圈细弧环绕的巨大圆按钮 + 一行短说明。

**提示词变化段**：
```
Idle lobby: she stands relaxed at the centre with her weight on one leg, looking slightly to
the side, one ring track glowing beneath her feet. Around the screen edges float the always-on
game HUD: at the top left a hexagonal level badge with a thin experience arc and a number
inside, at the top centre the host name with an honourific title and a small streak counter, at
the top right a hexagonal coin counter, at the top centre also a small pill reading a running
timer. Along the bottom is a navigation bar with three small icon tabs on the left and one large
circular central button ringed by two thin orbiting arcs, with a short caption under it. Text
allowed: a few short uppercase labels and numbers.
```
**参数**：768×1664 · 附加负面 `card list, to-do list, feed, chat bubbles`
**这是常驻层的基准屏**——HUD 全部贴边，中心永远留给她。

---

### S06 · 派单 · 一块被她刻上字的玻璃

**这是什么**：派单**不是弹一条通知**，是一块全息玻璃朝你砸下来落定。右上角稀有度骰子从 F 滚到目标等级（S 级会在 A 上停一拍），然后她当着你的面用激光把字一行行烧上去。**分量来自材质与动作，不是边框。**

**她怎么演**：手臂还伸着，隔着玻璃板直视你，表情专注。

**屏幕上是什么**：悬浮的斜置玻璃板（斜切边、表面有移动高光、一行行被激光烧出的字＋火星）、右上七刻度六边稀有度盘 + 一个大字母、标题、两段短说明、三行点线规格表。

**提示词变化段**：
```
She has just thrown a slab of holographic glass toward the camera: a large translucent
rectangular panel hovers in mid-air in front of her, tilted slightly, with a chamfered bevelled
edge, a moving specular sheen sweeping across its surface, and a bright laser line burning a row
of text into it with tiny sparks flying off. On the panel top right corner sits a hexagonal
rarity dial with seven tick marks and one big letter; below it a title, two short paragraphs,
and a three-row dotted specification table. She stands behind the panel with one arm still
extended, looking straight at the viewer with a focused expression. Text allowed: one big rarity
letter, one short Simplified Chinese task title, a few short Simplified Chinese labels.
```
**参数**：768×1664 · 附加负面 `notification card, mobile push banner, rounded app card, paper document`
**硬约束**：**禁止黄纸、绳、血印。**

---

### S07 · 按住指纹 · 接单

**这是什么**：接单不是点按钮，是**按 0.9 秒指纹不回弹**。中途松手会被她抓包：「……犹豫了？」这是整个产品里唯一一件需要你付出一点点力气才能做到的事——**分量的来源**。

**她怎么演**：在板后微微前倾、眯眼盯着，轻微失焦。

**屏幕上是什么**：七条同心指纹弧填了约七成，下方一行按住提示 + 百分比。

**提示词变化段**：
```
Close-up on the lower area of the floating glass panel: a large fingerprint made of seven
concentric fingerprint arcs glows bright cyan, filled about seventy percent from the outside in,
with a progress caption below it reading a hold-to-confirm prompt in Simplified Chinese and a
percentage. Behind the panel she is slightly out of focus, leaning in and watching closely with
narrowed focused eyes. Text allowed: one short Simplified Chinese hold prompt and one uppercase
English caption.
```
**参数**：768×1664 · 附加负面 `fingerprint scanner hardware, real hand, thumb`
**注意**：是**七条同心弧**，不是真实指纹纹理。

---

### S08 · 退缩 · 稀有度往下掉一档

**这是什么**：你说「换一个」，她当场把这一单降一档，报酬重刻。退三次，强制给你挂上「口头巨人」称号——**嘴不豁免记录**。退缩要有代价，但代价是可承受的。

**她怎么演**：冷、抱臂、下巴略抬。是「冷」，不是「凶」。

**屏幕上是什么**：玻璃板闪动、稀有度盘掉档（字母变暗、刻度只亮一部分）、报酬行正被激光重刻冒火星；顶部滑入一条横幅，把强制称号钉在宿主身上，带一个警示小符。

**提示词变化段**：
```
She has a cold, unimpressed expression, arms crossed, chin slightly raised. The glass panel in
front of her is flickering and its rarity dial has just dropped: the big letter is dimmer and
only part of the seven tick marks are lit, while the reward line on the panel is being re-etched
by a bright laser with fresh sparks. A banner strip has slid in at the top of the screen showing
a forced title being pinned onto the host, with a small warning glyph. Text allowed: one big
rarity letter, one short Simplified Chinese title, one short banner label.
```
**参数**：768×1664 · 附加负面 `angry shouting, red alert, punishment screen`

---

### S09 · 执行中 · 她盯着你

**这是什么**：计时开始，她退到右边看着你。**她不许被压掉——她永远可见。**

**她怎么演**：退到画面右侧、四分之三身位、眯眼专注看镜头。

**屏幕上是什么**：左三分之二被一摞玻璃卡盖住——等宽大字计时器、进度条 + 限时小标、「SYSTEM 正在看着你」+ 小眼睛图标、三个虚线证据槽（一个已填照片缩略图）、暴击率读数 + 两枚小道具标签，底部两枚 ghost 动作按钮 + 一条按住认输条。背后场景整体压暗。

**提示词变化段**：
```
She has stepped back and to the right of frame, three-quarter body, looking at the viewer with
narrowed focused eyes. The left two thirds of the screen are covered by a tall execution panel
of stacked glass cards: a big running timer in a wide monospaced font, a thin progress bar with
a small limit label, a line reading that the system is watching with a small eye glyph, a row of
three dashed square evidence slots with one filled by a photo thumbnail, a crit-chance readout
with two small item tags beside it, and at the bottom two ghost action buttons plus a
hold-to-surrender bar. The whole scene behind the panel is dimmed. Text allowed: one timer
readout, a few short Simplified Chinese labels, one crit percentage.
```
**参数**：768×1664 · 附加负面 `stopwatch hardware, clock face, calendar`

---

### S10 · 结算 · 稀有度砸落 + EXP 上涨

**这是什么**：一秒的「给」。证据飞进她手里 → 她扫一眼 → 稀有度字母砸进屏幕 → EXP 往上跳 → 经验条上涨 → 金币/六维/连击一枚枚 chip 浮起来 → 她头顶那一环亮起。**你只需要看着，不需要点。这一屏要让人想截图。**

**她怎么演**：直视你、得意、一手叉腰，环在她周围变亮。

**屏幕上是什么**：巨大稀有度字母砸在正中（硬边辉光 + 冲击波环 + 粒子外爆），下方叠一张结算卡：大写 kicker、正在跳的 EXP 大数字、细经验条、等级读数、三枚小奖励 chip；两道扫描线扫过。

**提示词变化段**：
```
She is looking straight at the viewer with a proud self-satisfied expression, one hand on her
hip, the ring tracks around her brightening. A huge rarity letter slams into the centre of the
screen with a hard-edged glow and radiating shockwave rings, particles bursting outward. Below
it a stacked result card holds an uppercase kicker line, a big EXP number counting up, a thin
experience bar, a level readout, and three small reward chips. Two thin scan lines sweep across
the screen. Maximum bloom and contrast, this is the brightest frame in the whole app. Text
allowed: one huge rarity letter, one big EXP number, a few short uppercase kickers.
```
**参数**：768×1664 · 附加负面 `confetti, party popper, cartoon celebration`
**这是整屏最亮的一帧。** 稀有度色**只**出现在字母和印章上。

---

### S11 · 暴击 / 双倍卡 · 盖章

**这是什么**：命中暴击：数字定格 200ms，盖上 CRIT 印章，再翻倍续滚；身上带双倍卡再盖一枚。**两枚章砸下去的质感，是这一屏的全部。**

**她怎么演**：头微微后仰、眼睛睁大，惊讶。

**提示词变化段**：
```
Same result layout as a clear screen, but the numbers have been doubled and two heavy circular
ink stamps have just been slammed onto the result card, one reading a crit multiplier and one
reading a double-item multiplier, each with a starburst edge, engraved metallic cyan texture,
distressed edges, and a burst of particles behind it. She throws her head back slightly, eyes
wide with surprise. Text allowed: one big number, two short uppercase stamp captions.
```
**参数**：768×1664 · 附加负面 `paper stamp, ink pad, rubber stamp object`

---

### S12 · 升级 · LEVEL UP

**这是什么**：经验跨级：先涨满 → 白闪 → 归零 → 再涨到余额。**白闪那一帧就是这一屏**：LEVEL UP 砸出来，她欢呼，脚边最内那一环点亮。日委托上限 +1，难度也跟着涨。

**她怎么演**：双臂微举、眼神发亮、头发与衣摆被冲击波掀起。

**提示词变化段**：
```
A full-screen white flash at the exact moment of level-up: she is mid-cheer with both arms
raised slightly, eyes bright, hair and uniform lifted by the shockwave. A large level-up banner
is centred holding a small uppercase kicker, a huge level number, and one short line of small
text. The lowest ring track around her has ignited into a solid blazing band. Cyan particles
explode outward in a wide cone. Text allowed: one uppercase kicker, one huge number, one short
Simplified Chinese line.
```
**参数**：768×1664 · 附加负面 `gold coins raining, treasure chest, fireworks cartoon`
**时长约束**：升级 ≤2s，同日重复只播简版。

---

### S13 · 认输 · 更暗、更安静、更短

**这是什么**：按住认输。画面整体压暗、饱和度抽掉，**没有冲击音**，字幕比平时更慢更短。她念出你真实的连败数据——毒舌就是惩罚本身。**难受，但不羞辱。**

**她怎么演**：低头、闭眼、肩膀塌下来、手垂在身侧，全息边缘光几乎熄灭。

**屏幕上是什么**：底部一条窄记录条（认输时间），下面一张黯淡的补救卡开始淡入，最底一条极细的认输进度线。**没有粒子。**

**提示词变化段**：
```
The scene is drained and quiet: overall saturation cut to roughly one third, brightness reduced,
a heavy dark vignette closing in from every edge, no particles at all. She stands with her head
lowered and eyes closed, shoulders dropped, hands at her sides, her holographic rim light almost
extinguished. A single narrow record strip near the bottom shows a surrender timestamp, and a
small muted card begins to fade in beneath it. A very thin surrender progress line stretches
across the bottom edge. Text allowed: one short Simplified Chinese record line.
```
**参数**：768×1664 · 附加负面 `game over screen, skull, red X, harsh punishment`
**亮度铁律**：失败亮度＝成功的**三分之一**。全程不许有暖色。

---

### S14 · 补救 · 永远留一条路

**这是什么**：在同一块板上，她**已经给你备好了补救单**：明天此时之前做一半，这一笔就划掉。「永远有补救」是机制，也是她这个角色的底线。

**她怎么演**：抬起头，用平的、耐心的眼神看着你。

**屏幕上是什么**：黯淡场景里只亮起一张补救卡（kicker + 任务名 + 半量时长 + 截止时间），边缘是柔和的中性青；卡下两枚选择按钮。

**提示词变化段**：
```
Still the drained dark scene, but one small panel has lit up on the board in front of her: a
remedy card with an uppercase kicker, one task title, a half-duration note and a deadline, its
edge glowing in soft neutral cyan rather than any warm colour. She has raised her head and is
looking at the viewer with a flat patient expression. Two choice buttons sit below the card.
Text allowed: one short Simplified Chinese title, one deadline line, two short Simplified
Chinese button labels.
```
**参数**：768×1664 · 附加负面 `warm hopeful glow, sunrise, redemption light`
**注意**：补救卡**不许用暖色**。希望是靠机制给的，不是靠打光给的。

---

### S15 · 主线全景 · 环套在她身上

**这是什么**：主线不是进度条，是**天花板**。5~8 环全部套在她身上：已走过＝实心发光的环，脚下这一环＝一颗彗星沿环慢慢扫永不停，还没到＝虚线暗轨悬着。**你离她还有多远，是看得见的。**

**她怎么演**：全身站在一摞从脚下爬到头顶的环轨里；环跟着她呼吸，她打瞌睡时环变慢。

**屏幕上是什么**：顶部一个报头块（大写 kicker + 主线目标句 + 进度分数），每条环右端一枚小标签。

**提示词变化段**：
```
Wide full-body shot of her standing inside a vertical stack of seven concentric elliptical
holographic ring tracks climbing from the floor at her feet to far above her head. Completed
rings are solid and blazing with tick marks; the ring at her feet carries a small comet of light
travelling around it; the rings above are dashed dim rails. Small labels hang at the right end
of each ring. At the top of the screen a header block holds an uppercase kicker, the mainline
goal sentence and a progress count. Text allowed: one uppercase kicker, one short Simplified
Chinese goal sentence, a progress fraction, seven tiny ring labels.
```
**参数**：768×1664 · 附加负面 `progress bar, milestone list, timeline list, dashboard`
**硬约束**：**禁止出现状态文字**（已完成 / 进行中 / 未解锁），状态只能用样式表达。

---

### S16 · 档案 · 六维雷达与称号墙

**这是什么**：宿主档案。六边等级牌（沿轮廓走的经验环）＋金币；六维雷达（**4 环 + 6 轴 + 每轴 3 枚刻度，刻度走平方根**——低值外扩，避免偏科变成"一根针"）；战绩四格；称号墙（锁着的显示？？？）；道具库存。

**她怎么演**：被压暗，站在投影板后面。

**屏幕上是什么**：一块从屏幕下方升起、**由她胸口打出的一条宽三角青光托着**的全息板。

**提示词变化段**：
```
A tall holographic projection sheet has slid up from the bottom of the screen, floating between
her and the viewer and lit from her chest by a wide triangular cyan light beam; she is visible
behind the sheet, dimmed. The sheet is the host archive: a hexagonal level plate holding a
number and a thin experience arc, a coin readout beside it, a title string, a six-axis radar
chart with four concentric grid rings and one filled polygon, a row of four statistic counters,
a wall of title chips with some locked and shown as question marks, and an inventory row of four
item icons. Text allowed: uppercase kickers, a few numbers, a few short Simplified Chinese
labels.
```
**参数**：768×1664 · 附加负面 `flat dashboard, spreadsheet table, bar chart list`
**注意**：雷达**顶点默认不画点**，只留多边形轮廓；数值悬浮才显。

---

### S17 · 补给 · 金币唯一去处

**这是什么**：四种道具——双倍卡、暴击卡、免死金牌、换单券。**金币只能花在这**，买不起的行自动变灰。她会在旁边损你一句。

**她怎么演**：从板后探身进来，一脸讥诮。

**屏幕上是什么**：四行，每行＝左侧发光道具字形（双六边 / 星芒 / 盾 / 循环箭头）+ 中间名称与一行说明 + 右侧六边金币价格按钮；一行因为买不起而变灰禁用；板头有金币余额。

**提示词变化段**：
```
The projection sheet now shows the supply shop: four rows, each with a glowing item glyph on the
left (a doubled hexagon, a starburst, a shield, and a circular swap arrow), an item name and a
one-line description in the middle, and a hexagonal coin price button on the right. One row is
greyed out and disabled because the price is unaffordable. A coin balance sits in the sheet
header. She leans in from behind the sheet with a smug expression. Text allowed: four short
Simplified Chinese item names, four prices, one balance number.
```
**参数**：768×1664 · 附加负面 `real money, credit card, paywall, in-app purchase screen`
**硬约束**：全程没有真实货币，只有金币。

---

### S18 · 系统设置 · 从她胸口打出的光束

**这是什么**：音效、她的声音（电子音节 / 人声 / 静音）、震动、全息描边、重置存档。面板由一条从她胸口打上去的青色光束托着——**她不是背景，她是这个界面的电源。**

**屏幕上是什么**：五行设置（标签 + 一行灰色副说明 + 右侧两/三档分段玻璃开关），最后一行是红框危险按钮带按住确认填充条；面板上方一条宽三角青光连到她胸口。

**提示词变化段**：
```
The projection sheet shows a minimal settings console: five rows, each with a label, a one-line
grey sub-caption and a two or three position segmented glass toggle on the right; the last row
is a red-outlined destructive button with a hold-to-confirm fill bar. Above the sheet, a wide
triangular cyan light beam connects her chest to the top edge of the sheet. Text allowed: five
short Simplified Chinese labels and a few short toggle words.
```
**参数**：768×1664 · 附加负面 `smartphone settings app, iOS settings list, flat list`
**注意**：红色只出现在那一行边框，不许铺开。

---

### S19 · 主线达成 · 整轨亮起

**这是什么**：最后一环完成，**所有环同时亮起，从脚下一路亮到头顶**。她会说一段话——这是整个产品**唯一一次她不再毒舌**。

**她怎么演**：双臂微张、仰头、闭眼，第一次露出真正温和的表情。**收着，不要喜极而泣。**

**提示词变化段**：
```
Every ring track around her has ignited at once into a solid blazing ladder of light from her
feet to far above her head, and she stands inside it with both arms slightly out, head up, eyes
closed, wearing a genuinely warm expression for the first time. A huge burst of cyan particles
and a white flash flood the frame. A centred banner holds an uppercase mainline-complete kicker,
the goal sentence in large type, and a day count. Text allowed: one uppercase kicker, one short
Simplified Chinese goal sentence, one count.
```
**参数**：768×1664 · 附加负面 `fireworks cartoon, trophy, medal, confetti`

---

### S20 · 战报 · 一张想发出去的图

**这是什么**：结算完给一张 **900×1600 的战报 PNG**，真的能导出、真的能发。真实实现是 canvas 画的（`flows.js shareCard()`），这一张只做视觉参照。

**屏幕上是什么**：上半＝她的半身剪影压在暗底上，下半＝稀有度大字母、大写 CLEAR kicker、任务名、巨大 EXP、一行小标签、她说的那句话（带署名），页脚是名字 / 等级 / 日期。

**提示词变化段**：
```
A vertical shareable battle-report card rendered as a flat graphic with no perspective:
near-black background with a faint cyan grid, a faded oversized watermark word behind
everything, a hard-cut band across the upper half holding a dimmed silhouette of the girl, then
a stacked lower section with a huge glowing rarity letter, an uppercase clear kicker, a task
title, a huge EXP number, a row of small reward tags, one quoted line of Simplified Chinese
dialogue with a small attribution, and a footer line with the host name, level and date. Text
allowed: several short labels, one big number, one quoted Simplified Chinese line.
```
**参数**：768×1664 · 附加负面 `social media frame, phone mockup, instagram story template`

---

### S21 · 组件层 · HUD 与底栏

**这是什么**：常驻四层包裹里的第一层。等级六边牌带经验弧、金币六边计数、执行中计时 pill、贴顶 4px 经验条、底栏三页签 + 中央委托按钮、两枚玻璃选择按钮。**全部贴边，中心永远留给角色。**

**提示词变化段**：
```
A component sheet on a flat dark navy background with no character at all: the always-on game
HUD parts laid out in a clean evenly spaced grid, each isolated with thin cyan guide lines. The
parts are a hexagonal level badge with a thin experience arc, a hexagonal coin counter, a small
running-timer pill, a thin full-width top experience bar, a bottom navigation bar with three
small icon tabs and one large circular central button ringed by two thin orbiting arcs, and a
pair of glass choice buttons. Text allowed: a few uppercase labels and numbers.
```
**参数**：768×1664 · 附加负面 `character, girl, face, hands`
**用途**：做 Flutter 组件时的对照图，尺寸标注另出。

---

### S22 · 打瞌睡 · 没人理她

**这是什么**：80 秒没人理她，她站着睡着了，环变慢、光变暗。你一碰她就醒，还嘴硬。**这一屏是「她是个活的」最便宜也最有效的一次证明。**

**她怎么演**：闭眼、头前垂、身体微塌，全息亮度调低，环轨变慢变暗，周围浮着粒子与薄雾。

**提示词变化段**：
```
She has fallen asleep standing up: eyes closed, head drooped forward, body sagging slightly,
her holographic brightness lowered and the ring tracks around her slowed and dimmed. Small cyan
particles drift and a soft haze hangs around her. A single short subtitle card near her waist
holds one sleepy line of Simplified Chinese dialogue with a slow five-bar waveform icon. Text
allowed: one short Simplified Chinese line.
```
**参数**：768×1664 · 附加负面 `zzz symbols, sleep bubble, cartoon snoring`
**注意**：**不许出现 zzz 气泡**那种漫画符号。

---

### S23 · 冷场 · 连击断了 / 好几天没来

**这是什么**：她记得你断了几天的连击。这一档她话变短、眼神变平、色温更冷，环的呼吸变慢。**毒舌升级是有数据支撑的：她会念出你真实的连败次数。**

**她怎么演**：抱臂自然下垂、下巴平、眼睛平且半闭、**一点讥诮都没有**，散发冷感。全息边缘光比平时更细更冷，环暗且呼吸慢，画面比正常大厅略去饱和。

**提示词变化段**：
```
She stands with her arms loosely at her sides, chin level, eyes flat and half-lidded with no
smirk at all, radiating cold disinterest. The holographic rim light on her contour is thinner
and cooler than usual, the ring tracks around her are dim and breathing slowly, and the frame is
very slightly desaturated compared with a normal lobby screen. One short subtitle card near her
waist holds a single short Simplified Chinese line. Text allowed: one short Simplified Chinese
line.
```
**参数**：768×1664 · 附加负面 `angry face, shouting, red eyes, harsh lighting`
**关键**：这一档是**更冷**而不是更凶——把表情减到最少。

---

### S24 · 今日已清 · 等换日

**这是什么**：当日委托清空。中央那颗大按钮从「委托」变成「今日已清」，底下写着换日还有多久，她会预告明天的等级。**这一屏要传达的不是空，是「今天已经没事了」的松弛感。**

**她怎么演**：重心偏移、双手背在身后、看着你，带一点自得。

**提示词变化段**：
```
A calm end-of-day lobby: she stands at the centre with her weight shifted and her arms behind
her back, looking at the viewer with a small self-satisfied expression. The large circular
central button at the bottom is dimmed and empty, with a short Simplified Chinese caption
underneath reading that today is clear plus a countdown to the next day, and a second small line
predicting tomorrow. No task panel anywhere on screen, the stage is uncluttered. Text allowed:
two short Simplified Chinese captions and one small level prediction label.
```
**参数**：768×1664 · 附加负面 `empty state illustration, sad empty box, zero data`
**注意**：空不是缺，是清空后的安静。

---

## 4 · 生成参数与抽卡策略

| 项 | 值 | 理由 |
|---|---|---|
| 底模 | `qwen_image_2.1_bf16` | 本机已下载，中文与 UI 文字表现最好 |
| 文本编码器 | `qwen3vl_8b_int8_convrot` | ⚠️ 换成 `qwen_3_4b` 会在 KSampler 报 `normalized_shape=[4096]` |
| 采样 | 25 步 / cfg 1 / euler / simple / denoise 1 | 2.1 是蒸馏模型，cfg=1，沿用 ComfyUI 0.38 官方模板 |
| 整屏尺寸 | 768×1664（9:19.5） | 与 390×844 手机满屏比例一致 |
| 素材尺寸 | 1024×1024 | sprite / 印章 / 贴图 |
| 放大 | 2x-AnimeSharpV4_Fast_RCAN_PU | 线稿锐化，出 1536×3328 母版 + 1080×2340 网页版 |
| 抽卡 | 每镜 3 张起，`--seed` 逐个换 | 概念稿靠挑，不靠调 |

**种子策略**：先抽 `C0-character-sheet` 挑一张最像的，把它当"她"的基准；后续整屏稿固定用**同一组种子家族**（例如 610200~610299）连抽，比每次随机更容易保持同一个人。

**优先级**（如果不想一次出 30 张）：

1. `A0-bg-void` —— 唯一直接进原型的真素材，替换 `bg-void.jpg` 立刻能看效果
2. `S04-rings` / `S15-mainline` —— 这两个决定"游戏化"成不成立
3. `S06-dispatch` / `S10-settle` —— 派单与结算是产品的两个高潮
4. `S13-fail` / `S14-remedy` —— 最难写对的一对（暗而不羞辱）
5. 其余按需

---

## 5 · 已知坑

1. **ComfyUI 必须在线**。脚本会先探活 `/system_stats`，不在线直接退出并提示用绘世启动器拉起（默认 `127.0.0.1:8188`）。
2. **首次跑要读 13GB 主模型 + 8.7GB 文本编码器进显存**（RTX 5090 32G 放得下），首轮慢、后续快。
3. **中心不许有东西**（`A0`）：她会被合成在正中央，中心一乱整张废。
4. **稀有度色只能当信号**：B 金 / A 橙只在那一张单子上出现，不许变成氛围色。这是 `opus-v2-dir/README.md` 里明确写下的铁律。
5. **连续生成会串台**：所以才有三把锁。发现某镜跑偏，先检查是不是变化段被 LOCK 盖掉了。
6. **中文长句不要写进图里**：一屏 ≤6 个短标签，正文交给 CSS/Flutter。
7. **模型版权红线**：原型里 `live2d/sakiko/`（丰川祥子）与 `live2d/Hiyori/` 都**不入库、不外传**，也**不要**拿去当 prompt 的参照。`C0` 的虚拟娘是原创设定。
8. **PNG 母版不入库**：只收网页版 JPEG（沿用 `tools/comfyui/README.md`）。

---

## 6 · 下一步（待宿主拍板）

这套东西现在是**提示词层**，还没落到原型上。可选的三条路，按代价从低到高：

- **A｜只换底图**：出 `A0-bg-void`，替换 `prototype/opus-v2-dir/img/bg-void.jpg`，其余不动。半小时，立刻能看到"游戏化"的底色变化。
- **B｜换底图 + 粒子 + 印章**：`A0`~`A3` 四件真素材全部落地，`fx.js` 与结算印章改用贴图。
- **C｜按概念稿重做视觉层**：拿 `S01`~`S24` 当参照，逐屏改 `css/app.css` 与 `js/ui.js`，最终同步到 Flutter `app/`。这是真正的"用 ComfyUI 重新设计"，代价也最大。

**建议先走 A**，一张图就能判断方向对不对，再决定要不要往下走。
