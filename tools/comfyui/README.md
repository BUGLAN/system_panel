# ComfyUI · SYSTEM 游戏背景生成管线

> 落地日期：2026-11-06 · 模型：**Qwen-Image 2.1**（本机已下载）· 端点：`http://127.0.0.1:8188`

## 文件

| 文件 | 用途 |
|---|---|
| `qwen21-game-bg.workflow.json` | **可拖入 ComfyUI GUI 的工作流**（UI 格式） |
| `qwen21-game-bg.api.json` | API 格式（POST `/prompt` 用，两个脚本都读这份） |
| `gen_game_bg.mjs` | 天幕背景一键重生成脚本 |
| `prompts/shots.json` | **重设计提示词库**：30 镜（角色/素材/整屏时刻），三把锁拼装 |
| `gen_shots.mjs` | 按提示词库批量出图（`--list` / `--print` / `--shot` / `--group` / `--all`） |

## 流程（Qwen-Image 2.1 文生图 + 放大）

```
UNETLoader(qwen_image_2.1_bf16) → QwenImage21Cache(auto) ─┐
CLIPLoader(qwen3vl_8b_int8_convrot, type=qwen_image) → TextEncodeQwenImage21（正/负提示词）
EmptyLatentImage(768x1664 · 9:19.5 手机满屏比例) ──────────┤
                        KSampler(25步 / cfg 1 / euler / simple / denoise 1)
                          → VAEDecode(qwen_image_2.1_vae_bf16)
                          → UpscaleModelLoader(2x-AnimeSharpV4_Fast_RCAN_PU)
                          → ImageUpscaleWithModel（768x1664 → 1536x3328 母版）
                          → ImageScale(1080x2340) 网页版
```

- 参数 25 步 / cfg 1 / euler / simple 来自 ComfyUI 0.38 官方 `image_qwen_image_2_1_t2i` 模板（2.1 是蒸馏模型，cfg=1）
- 首次跑要把 13GB 主模型 + 8.7GB 文本编码器（qwen3vl_8b_int8_convrot）读进显存（RTX 5090 32G 放得下），首轮慢、后续快
- ⚠️ 2.1 的文本编码器是 **qwen3vl_8b_int8_convrot**（hidden 4096）；目录里的 `qwen_3_4b.safetensors`（hidden 2560）配 2.1 会在 KSampler 报 `normalized_shape=[4096]` 形状错
- 产物落在 `ComfyUI/output/SystemBG/`：`qwen21_bg_2x_*.png`（母版）与 `qwen21_bg_web_*.png`（网页版）

## 用法

```powershell
# 换种子抽卡
node tools/comfyui/gen_game_bg.mjs --seed 42
# 原样重生成 + 拷一份到指定目录
node tools/comfyui/gen_game_bg.mjs --out E:\tmp
```

游戏内引用：`prototype/opus-v2-dir/css/app.css` 的 `#bg .sky`（图片垫底，CSS 扫描线/轨道环/地面网格等动态层继续叠在上面）。

## 重设计提示词库（`prompts/shots.json` + `gen_shots.mjs`）

把 `prototype/opus-v2-dir/` 原型里**每一个功能时刻**翻成提示词：游戏化 + Live2D 舞台 + 虚拟娘。
每个镜头的中文功能说明、她的表演、提示词全文见 **`docs/24-ComfyUI重设计提示词集.md`**。

```powershell
node gen_shots.mjs --list                     # 30 镜清单（不需要 ComfyUI 在线）
node gen_shots.mjs --print S10-settle         # 打印拼装好的完整正/负提示词，手动粘 GUI
node gen_shots.mjs --shot A0-bg-void          # 只出一张
node gen_shots.mjs --group 整屏时刻            # 24 张
node gen_shots.mjs --all --out E:\tmp         # 30 张全出
node gen_shots.mjs --shot A1-fx-burst --no-upscale
```

- **拼装规则**：`positive = style_lock + character_lock(有她的镜) + variation`，`negative = negative_base + negative_extra`。
  这是为了防"连续生成同类提示词串台"——改词只改 `shots.json` 里那一镜的 `variation`，别动三把锁。
- **产物**：`tools/comfyui/.out/SystemShots/<镜 id>*.png`，PNG 母版**不入库**。
- **哪些是真素材**：只有 `A0-bg-void`（替换 `prototype/opus-v2-dir/img/bg-void.jpg`）、`A1-fx-burst`、`A2-stamp-crit`、`A3-glitch` 会直接进产品；其余 26 镜是给 CSS / Flutter 对齐气质用的概念参照。
- 脚本会先探活 `http://127.0.0.1:8188/system_stats`，ComfyUI 没起来就直接退出并提示。

## 约定

- 背景图必须**无人物、无文字**（角色是 Live2D 独立图层；大字 SYSTEM 由 CSS 叠加）
- 中心保持低对比，给 UI 文字留可读性；整体压暗，`#app.dim` 还会再降到 0.35 透明度
- 仓库只收网页版 JPEG（`prototype/opus-v2-dir/img/bg-void.jpg`），PNG 母版留在 ComfyUI output，不入库
