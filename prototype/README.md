# 宿主 SYSTEM 原型清单

## 原型目录现状（2026-10-07 归档后）

`prototype/` 只剩**中选原型**与跨原型的真源/证据；另外 7 版历史原型已整体**移动**到 `E:\repo\archive\`（不在本 git 仓库内，每个子目录自包含并各带 `README.md`）：

| 仍在 prototype/ | 说明 |
|---|---|
| `opus-v2-dir/` | ★ **中选原型**：`cd prototype/opus-v2-dir && node server.mjs` → <http://localhost:4925> |
| `.stitch/` | 视觉基准 `DESIGN.md`（GAME HUD v2）+ `SCREENS.md` |
| `motion-demo/` | 动效真源样机（静态服务挂 4920） |
| `references/` | 150+ 张实测截图与验证留痕（`v6-redesign.md`、`verify-v5b*.md` 等） |
| `screens/` | Stitch 生成的 S1~S6 设计稿（见下表） |
| `stitch-bridge/` | Stitch CLI 桥（package.json + 提示词） |

| 已归档到 `E:\repo\archive\` | 原端口 / 打开方式 |
|---|---|
| `app/`（原型 v1「冷光神殿」，原主线原型） | 4921 |
| `opus-v1/`（v1 + OPUS 美术总监重绘） | 4923 |
| `app-v2/`（宿主 SYSTEM II · Ascendance，本地 mock LLM） | 4922 |
| `app2/`（Prototype V2-Gameified · 残件，页面已丢） | 4931 |
| `ink/`（墨染修途，方向 B） | 4931 |
| `opus-dir/`（泼彩） | 双击 `index.html` |
| `redesign-v6/`（主线页三方向探索稿） | 双击 `mainline-3ways.html` |

归档索引与全部说明见 **`E:\repo\archive\README.md`**。本文件下方的 Stitch 屏幕清单不受影响。

---

Stitch 项目 ID：`9824844031085818014`（title: 宿主 SYSTEM 原型）
Design System ID：`5203883926288910671`（来源 [`.stitch/DESIGN.md`](.stitch/DESIGN.md)）
画布地址：https://stitch.withgoogle.com/projects/9824844031085818014

## 屏幕清单

| 屏 | 标题 | Screen ID | 本地文件 |
|---|---|---|---|
| S1 | 宿主绑定仪式 · ONBOARDING | `5ed3d24eca8c4ea98df284bc4ff4230d` | [S1.html](screens/S1.html) / [S1.png](screens/S1.png) |
| S2 | 今日任务 | `f35c33c081c243b8b2352ba32a55a978` | [S2.html](screens/S2.html) / [S2.png](screens/S2.png) |
| S3 | 任务详情 | `3c9cadc798e340c4aeca0aae15a827ce` | [S3.html](screens/S3.html) / [S3.png](screens/S3.png) |
| S4 | 结算浮层 | `d2ef9e7251764e518ed7e77a0ec51c99` | [S4.html](screens/S4.html) / [S4.png](screens/S4.png) |
| S5 | 宿主面板 | `b6848c5558df4737a31f525e74b0c48c` | [S5.html](screens/S5.html) / [S5.png](screens/S5.png) |
| S6 | 失败毒舌 | `8184f2345988436c82affc461e5912d0` | [S6.html](screens/S6.html) / [S6.png](screens/S6.png) |

## 本地预览

```powershell
$env:STITCH_API_KEY = "<你的key>"
npx stitch serve -p 9824844031085818014 --port 8788
# 端口被占时 CLI 会自动顺延（如 8789），以进程输出的 url 为准
# 当前实际地址: http://localhost:8789
```

## 迭代命令（在 stitch-bridge 目录下）

```powershell
# 按新提示词重生成某屏
npx stitch generate screen --project 9824844031085818014 --device MOBILE --title "Sx 名称" --prompt (Get-Content prompts\Sx.txt -Raw) --json

# 编辑已有屏幕
npx stitch edit screen <screen-id> --project 9824844031085818014 --prompt "改法" --json

# 重新拉取某屏
npx stitch get screen <screen-id> --project 9824844031085818014 --json
```

## 生成管线

`prompts/S1~S6.txt`（即贴式提示词）→ `stitch generate screen` → Stitch 按 `DESIGN.md` 主题渲染 → `results/Sx.json`（原始响应）→ 下载 `screens/Sx.html + Sx.png`。

## 已知偏差（v1 待调）

- Stitch 生成代理会自由发挥部分系统腔文案（结构正确，措辞与 SCREENS.md 有出入），需要精修时用 `edit screen` 逐屏约束。
- 截图分辨率低（预览级），HTML 才是权威产物。
