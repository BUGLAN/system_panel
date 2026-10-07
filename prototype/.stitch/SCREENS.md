# SCREENS — 宿主 SYSTEM 原型屏幕清单

> 用法：打开 [labs.google/stitch](https://labs.google/stitch) → 新建 Mobile 项目 → 把 [.stitch/DESIGN.md](.stitch/DESIGN.md) 内容作为主题/风格上下文载入 → 逐条粘贴下面的提示词生成屏幕。
> 每条提示词自包含，可直接复制粘贴。生成后如走样，追加一句 "Strictly follow DESIGN.md: dark #101012 canvas, single amber accent #E8B04B, mono numbers."

---

## S1 绑定仪式（新手开局）

规则来源：05-新手开局规则。目的：首次打开的"系统绑定"仪式感 + 写下第一个目标。

```text
Apply the attached DESIGN.md strictly. Dark mobile onboarding screen, 390px, left-aligned asymmetric layout, no centered hero.

Top area: tiny mono status line in muted gray, letterspaced uppercase "SYSTEM ONLINE", with a slow amber scanline sweeping the header. Below it a deadpan system log, 3 short lines in mono 12px: "> 扫描完成", "> 宿主档案：空", "> 期待值已预设：最低".

Middle: huge display headline in off-white, two lines: "检测到新宿主。" second line in amber: "系统已接管。" Subcopy in muted gray 15px: "在留下第一个目标之前，系统对本宿主不抱任何期待。"

Lower third: a goal input field, label above in muted gray "宿主目标（一句话即可）", placeholder text "例如：三个月减十斤 / 早睡早起 / 考研上岸", dark input with 1px faint border and amber focus ring. Below the input, the starter-kit inventory as a single mono line with small amber tick icons: "开局三件套：金币 ×10 · 免死金牌 ×2 · 称号「三分钟热度」".

Bottom: one primary button, amber fill, dark text: "绑定系统". No secondary link. Skeletal shimmer allowed while typing simulation. Spring physics on all transitions.
```

---

## S2 今日任务（主界面 / 任务中枢）

规则来源：01-任务规则 + 00-核心规则。目的：每日枢纽——短期轨道为主，主线一环置顶，HUD 一行化。

```text
Apply the attached DESIGN.md strictly. Dark mobile home screen, 390px, single-column quest hub.

Top HUD bar, one mono line, no card background: "LV.3" in off-white, a small amber dot separator, "金币 248" , right side "连击 6" with a subtly pulsing amber dot. Below the HUD a full-width system banner strip, dark elevated fill with a 3px amber left edge, mono amber prefix "叮。" then: "新任务已发布。别问，问就是你自己立的目标。"

Section 1, small gray label "主线 · 进行中": one wide quest card, elevated dark fill, 1px faint border, left 3px amber difficulty strip tagged "D". Card title in off-white: "初试锋芒：累计跑步 10 公里", progress line in mono: "7.2 / 10 km", thin amber progress bar, right-aligned mono hint "环 2/6".

Section 2, small gray label "今日 · 短期轨道": three stacked quest cards, 1px faint borders, each with a left difficulty strip (one "E" gray, one "E" gray, one "F" dimmest). Card 1 title "词汇锻造：背 30 个单词", meta row in mono 11px muted: "截图验证 · 今日 24:00". Card 2 title "静心术：冥想 10 分钟", meta "截图验证 · 今日 24:00". Card 3 title "感恩清单：记录 3 件值得感谢的事", meta "截图验证 · 今日 24:00", this card fully ticked with a desaturated green check and dimmed content.

Bottom tab bar, 56px, 4 tabs with outline icons: 任务 (active, amber tint), 面板, 主线, 我的. Spring cascade reveal for the quest list.
```

---

## S3 任务详情 · 截图提交

规则来源：04-验证规则 + 01-任务规则。目的：统一的截图验证提交流程。

```text
Apply the attached DESIGN.md strictly. Dark mobile task-detail screen, 390px, single column, left-aligned.

Header: back arrow icon, then quest title in off-white 20px display: "词汇锻造：背 30 个单词". Under it a meta row: a small outlined tag "E 级" with gray difficulty strip color, and mono muted text "日常 · 今日 24:00 截止 · 剩余 04:12:37" with the countdown in mono amber, ticking.

System narration block, 14px muted gray, deadpan: "系统提醒：截图不会伪造，但面板不会说谎。"

Section, label above in muted gray "验证方式": one line in off-white: "上传背单词 App 今日进度截图", sub-line in dim gray: "可上传多张 · 可附文字备注".

Upload area: a row of one filled 4:3 thumbnail slot (a plausible vocab-app screenshot) with a small dim delete icon, plus one empty dashed 4:3 slot with a gray plus icon. Below, a text note field, label "备注（可选）", dark input with faint border.

Bottom fixed area: one primary amber button full-width: "提交验证". Directly beneath it a centered ghost text link in dim gray: "拒绝本任务（免死金牌 ×2）". No other buttons.
```

---

## S4 结算浮层（奖励动画）

规则来源：02-面板与奖励规则。目的：核心多巴胺时刻——经验跳字、属性+1、暴击。

```text
Apply the attached DESIGN.md strictly. Dark mobile reward-settlement overlay, 390px. Background dimmed with 70% dark scrim; a centered sheet, elevated dark fill, 24px radius, occupying the lower two-thirds.

Sheet top, mono amber letterspaced: "任务结算". Below, huge EXP number in Space Grotesk 56px amber, mid count-up, showing "+40 EXP" with a small mono "CRIT ×2" tag beside it outlined in amber.

Under the number, a horizontal row of reward chips, dark pills with 1px faint borders, popping with spring scale and 120ms stagger: "金币 +20" with a small amber coin dot, "经验 +40" mono, and one accent chip with amber fill: "智 +1".

Below chips, the hexagon radar preview in miniature: amber stroke polygon at 15% fill, axis labels 体/智/专/心/交/生 in dim gray 11px, the 智 vertex visibly pushed outward with a tiny amber value label "智 12".

Bottom of sheet: one full-width amber primary button: "收下". Tiny dim gray mono line under it: "系统评价：勉强符合预期。" Total choreography under 1.6 seconds, spring physics stiffness 100 damping 20, numbers count up, never fade in statically.
```

---

## S5 宿主面板（状态页）

规则来源：02-面板与奖励规则 + 03-惩罚规则。目的：等级、称号、六维雷达、连击——变强的可见资产。

```text
Apply the attached DESIGN.md strictly. Dark mobile status-panel screen, 390px, asymmetric, left-aligned.

Header block: small mono muted uppercase "HOST STATUS" with a slow amber scanline sweep, below it huge level display in off-white Space Grotesk: "LV.3" with the title tag beside it as an outlined pill in dim gray: "三分钟热度". Under, one mono line: "累计任务 27 · 金币 248 · 连击 6" with the streak dot pulsing subtly.

Center: large hexagon radar chart, thin structural grid rings at 8% white, axis labels 体/智/专/心/交/生 in dim gray, data polygon amber stroke 1.5px with 15% fill, the 智 axis extended furthest with a tiny mono value near each vertex (体 8 · 智 12 · 专 6 · 心 9 · 交 4 · 生 7). Chart draws with spring overshoot on entry.

Below, a two-line insight block, 14px muted deadpan: "系统观测：宿主在「智」上略有长进。在「交」上，系统建议宿主先从给一位旧友发消息开始。"

Bottom section, label "未竟之志": one collapsed ghost card with faint border, dimmed title "三个月减十斤", mono tag "已放弃", chevron. Then bottom tab bar with 面板 tab active in amber. Perpetual micro-loops on scanline and streak only.
```

---

## S6 失败 · 毒舌（任务失败态）

规则来源：03-惩罚规则 + 07-文案规则。目的：失败的即时惩罚是毒舌，骂完给出口。

```text
Apply the attached DESIGN.md strictly. Dark mobile failure-state screen, 390px, single column, left-aligned. No red flood, no sad illustration — the pain is verbal.

Top: quest title in dimmed off-white 18px with a strikethrough: "静心术：冥想 10 分钟", meta row mono muted: "日常 · 已超时".

Below, a large terminal-style roast box: elevated dark fill, 1px oxide-red border (#E05252), mono red "»" marker, roast copy in off-white 16px: "连 10 分钟都凑不出来，系统对宿主的最后一丝期待已耗尽。" Second smaller roast line in muted gray: "连击 6 → 0。系统已截图存档。"

Below the box, a consequence summary in two mono lines: "连击加成：已失效", "称号评定：维持「三分钟热度」", each prefixed with a dim gray ">". No HP bar anywhere.

Lower third, the remedy exit: a small gray label "补救出口 · 限 24 小时内", then one quest-card-style remedy row with an amber left strip tagged "E", title in off-white: "补救任务：现在补一次 5 分钟冥想", meta "完成则连击视为未断 · 每月 2 次". Bottom: one full-width amber primary button "接受补救任务", and beneath it a centered ghost dim link "放弃（毒舌加倍）". Spring transitions, no shake animation.
```

---

## 后续屏幕（待补）

- S7 立目标 / 主线链详情（长期轨道：5~8 环链、未竟之志列表）
- S8 突发任务（限时横幅 + 倒计时沉浸页）
- S9 周挑战结算（每周日）
- S10 商店 / 道具（金币消费：免死金牌、翻倍卡）
