# Design System: 宿主 SYSTEM — GAME HUD EDITION (v2)

> 网文系统流自我提升 App · 移动端（390px 基准）· 游戏化方向
> 本文件是所有 Stitch 屏幕生成的唯一视觉基准。任何屏幕生成必须严格遵循本文件。
> v2 变更：整体风格从"冷峻终端"升级为"游戏系统窗"（参考小说里蓝色半透明系统面板与游戏 HUD）。主题色弃用琥珀金，改用电光青 + 稀有度色谱。

## 1. Visual Theme & Atmosphere

A full game-HUD experience: the app IS a game system window. Think translucent deep-blue glass panels floating over a void-dark background, edged with glowing cyan borders and notched corner frames; rarity-colored loot tags; a thin EXP bar breathing under the top HUD; a faint grid and occasional scanline sweeping the background like a standby radar.

The mood: 打开游戏主菜单的一瞬间 — 每个面板都在微微发光，每个数字都在跳，结算的瞬间像开箱出金。Confident, spectacular, but still deadpan in copy (system voice: 宿主 / 系统 / 叮。). Density 6/10, variance 7/10, motion 7/10. Glow is now the core lighting language — controlled cyan radiance on key elements, never random.

## 2. Color Palette & Roles

- **虚空蓝黑** (#0A0E1A) — Primary canvas. Deep space navy, never warm black, never pure black.
- **面板深蓝** (#131C33) — Glass panel fill base (use with 80–90% opacity + backdrop blur for floating panels).
- **面板亮蓝** (#1A2647) — Elevated container, hover states, sheet fill.
- **面板高层** (#22315E) — Popovers, modals, pressed states.
- **屏显白** (#EAF2FF) — Primary text, slightly cool white.
- **次级冰蓝** (#8FA3C8) — Secondary text, descriptions, metadata.
- **息屏蓝灰** (#4A5A7A) — Tertiary text, disabled, axis labels.
- **系统青** (#38E1FF) — THE primary accent. EXP, key numbers, radar stroke, active tabs, focus rings, primary CTA, panel borders, glow. Single most-used color after text.
- **深青渐变端** (#0EA5E9) — Gradient partner for 系统青 (CTA fill: 系统青 → 深青, 135°).
- **危险红** (#FF4D5E) — Failure states, 毒舌框 border, S-rarity ONLY.
- **验收绿** (#34D399) — Success confirmation, verified checks.

### Rarity Spectrum (难度=稀有度, game loot colors)
- **F** 灰白 (#9AA3B2) · **E** 翠绿 (#4ADE80) · **D** 天蓝 (#38BDF8) · **C** 紫晶 (#A78BFA) · **B** 鎏金 (#FBBF24) · **A** 熔橙 (#FB923C) · **S** 猩红 (#FF4D5E)

Rarity colors are used ONLY for: difficulty strips, difficulty tags, loot-style reward chips, rarity glow on cards. UI chrome stays cyan. Max decorative accent remains 系统青; rarity colors are functional data colors.

## 3. Typography Rules

- **Display / Numbers:** Rajdhani (600/700) — condensed game-HUD letterforms, slight tracking. Used for screen titles, level, big EXP numbers, difficulty letters.
- **Chinese Body:** Noto Sans SC — relaxed leading (1.6), body 15px, all Chinese UI copy. Secondary text in 次级冰蓝.
- **Mono:** JetBrains Mono — system-log lines, technical codes, timestamps, the "叮。" prefix, countdown timers. Uppercase Latin status ("SYSTEM ONLINE") with letter-spacing 0.2em.
- **Banned:** Inter, system-ui as identity font, any serif. Big numbers use Rajdhani; inline small numeric metadata uses JetBrains Mono.

## 4. Component Stylings

* **玻璃面板 (Glass Panel):** Base container language. 面板深蓝 fill at 85% opacity, backdrop-blur 12px, 1px border rgba(56,225,255,0.35), outer glow `0 0 20px rgba(56,225,255,0.12)`, radius 14px with ONE clipped corner (12px notch, top-right or bottom-left via clip-path) — the signature game frame.
* **任务卡 (Quest Card):** Glass panel + a 3px left rarity strip in the quest's rarity color + matching soft rarity glow (`0 0 16px <rarity@25%>`). Title 屏显白 15px; meta row in 11px mono 次级冰蓝; a small rarity tag chip ("E 级") with rarity-colored border.
* **HUD 顶栏:** Single-line strip pinned top: level gem badge (hexagonal 系统青 outline with "LV.3"), coins, streak — then a 3px full-width EXP bar directly under it: cyan→deep-blue gradient at 62% filled with a periodic shine sweep.
* **系统发布横幅 (叮！ Banner):** Glass panel strip with 3px 系统青 left edge + cyan glow, mono "叮。" prefix, slides down with spring.
* **Buttons:** Primary = 系统青→深青渐变 fill, 虚空蓝黑 text, 12px radius + one clipped corner, soft cyan glow `0 0 18px rgba(56,225,255,0.35)`. Active: translateY(-1px) + glow intensifies. Secondary = ghost, 1px rgba(56,225,255,0.4) border, 屏显白 text. Danger = ghost with 危险红 border.
* **毒舌框 (Roast Box):** Glass panel with 1px 危险红 border + faint red glow, mono "»" marker in red, copy 屏显白. Always followed by a remedy CTA.
* **结算浮层 (Settlement Overlay):** Dim rgba(10,14,26,0.75), centered glass sheet. Behind the EXP number: a subtle radial cyan burst (rays). EXP in Rajdhani 56px 系统青 with glow. Reward chips = loot chips: rarity-colored border + rarity tint fill + rarity glow. Crit state: "CRIT ×2" tag in 鎏金 with gold glow.
* **六维雷达 (Hex Radar):** SVG hexagon, grid rings rgba(56,225,255,0.12), axis labels 息屏蓝灰, data polygon 系统青 stroke 2px with 18% fill + vertex glow dots. Spring draw on enter.
* **连击指示 (Streak):** Mono number + cyan ember dot with 2s pulse + tiny glow. Never a fire emoji.
* **Inputs:** Label above in 次级冰蓝 12px mono, glass fill, 1px border, cyan focus ring (2px) + glow. No floating labels.
* **Upload Slots:** Dashed rgba(56,225,255,0.35) slots, 4:3, plus icon 次级冰蓝; filled slots show thumbnail with rarity-green verified tick.
* **Background:** Canvas + faint 32px grid (rgba(56,225,255,0.04) lines) + one slow scanline sweeping every 8s (rgba(56,225,255,0.06)).
* **Loaders:** Skeletal shimmer on glass. No circular spinners.
* **Empty States:** Composed — dimmed terminal cursor + game-style "no quests" plaque. Never bare "暂无数据".

## 5. Layout Principles

* Mobile-first, 390px design frame, content max-width 430px centered on desktop preview.
* 16px page padding; 12px gaps between quest cards; section spacing 24–32px.
* Asymmetric, left-aligned structure; centered hero layouts BANNED — the 绑定仪式 screen is left-aligned with input anchored lower-third.
* HUD top bar + EXP bar pinned top, never a card.
* Bottom tab bar: 4 tabs (任务 / 面板 / 主线 / 我的), 56px, glass fill, active tab in 系统青 with icon glow.
* No overlapping elements; every element owns its spatial zone.

## 6. Motion & Interaction

* Spring physics default: stiffness 100, damping 20. No linear easing.
* Settlement choreography: dim → sheet springs up → radial burst flashes behind EXP → number counts up 800ms → loot chips pop with 120ms stagger → EXP bar at top fills with shine sweep. Total under 1.6s.
* Quest list reveals as staggered cascade (40ms/row, translateY 8px + fade).
* Radar draws with overshoot on panel open; EXP bar shine sweeps every 3s; scanline every 8s; streak dot pulses 2s.
* Hover/press on interactive panels: border brightens + glow intensifies (game button feel).
* Animate exclusively transform + opacity. Respect reduced-motion.

## 7. Anti-Patterns (Banned)

* No emojis anywhere — outline icons only.
* No Inter, no serif, no pure #000000, no warm amber/gold as PRIMARY theme color (v1 rejected — gold appears only as B-rarity and crit tag).
* No 3-equal-column card rows. Quest lists are single-column stacks.
* No flat corporate minimalism — every panel participates in the game-frame language (border + glow + notch).
* No cheerleading copy ("加油！") — system stays 毒舌但靠谱. The only "！" allowed is inside "叮！".
* No customer-service tone, no generic placeholder names, no fake stats, no filler ("Scroll to explore").
* No circular spinners, no floating labels.
* Rarity colors must NOT leak into general chrome — chrome is cyan-only.
