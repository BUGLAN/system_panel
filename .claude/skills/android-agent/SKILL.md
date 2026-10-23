---
name: android-agent
description: "「宿主 SYSTEM」项目的安卓模拟器 Agent 操作技能。封装高频重复动作：关闭弹层、逐级返回、回大厅、UI 快照与对比。基于 MuMu 官方 mumu-control skill。当需要操作 MuMu 模拟器上的 system_panel App、走查界面、验证改动时使用。"
---

# android-agent — 高频操作封装

> 依赖：`mumu-control` skill（`C:\Users\buglan\.agents\skills\mumu-control\`）
> 调研依据：[`docs/45-安卓模拟器Agent操作方案.md`](../../../docs/45-安卓模拟器Agent操作方案.md)

---

## 0 · 环境常量（改这里即可换设备）

```
SERIAL       = 127.0.0.1:16512        # MuMu ADB 端口；用 MuMuManager.exe info -v all 查
PACKAGE      = com.systempanel.app
ACTIVITY     = com.systempanel.app/.MainActivity
SKILL        = C:/Users/buglan/.agents/skills/mumu-control
MUMU         = E:/MuMu Player 12/nx_main
```

**先确认设备在线**：
```bash
adb devices
# 若没有 127.0.0.1:16512：
adb connect 127.0.0.1:16512
```

---

## 1 · 脚本清单

所有脚本在 `scripts/`，统一接口 `--serial`（默认读环境变量 `AGENT_SERIAL`，否则 127.0.0.1:16512）。

| 脚本 | 用途 | 典型命令 |
|---|---|---|
| `ui_snapshot.py` | 截图 + 元素 JSON + 标注图；支持 `--compare` 基线对比 | `python scripts/ui_snapshot.py --name before` |
| `dismiss_overlay.py` | 关闭当前弹层（X → 遮罩 → 返回键，按序尝试并验证） | `python scripts/dismiss_overlay.py` |
| `go_back.py` | 逐级返回（不退出 App） | `python scripts/go_back.py --steps 1` |
| `goto_lobby.py` | 回大厅（多次返回 + 点主线） | `python scripts/goto_lobby.py` |
| `wait_stable.py` | 等待界面稳定（连续两次快照元素数不变） | `python scripts/wait_stable.py --timeout 8` |

---

## 2 · 每个脚本的契约

### 2.1 `ui_snapshot.py`

```bash
python scripts/ui_snapshot.py [--name NAME] [--out DIR] [--compare BASELINE.json]
```

- 输出：`<out>/<name>.png`（原始）、`<name>_annotated.png`（带编号）、`<name>_elements.json`
- `--compare`：与基线 JSON 比对，输出「新增 / 消失 / 位置变化 >8px」三类差异；**退出码 1 = 有差异**
- JSON 结构：
  ```json
  {"serial":"...","ts":"...","elements":[{"index":0,"x":78,"y":72,"name":"LV","type":"View","clickable":false}]}
  ```

### 2.2 `dismiss_overlay.py`

```bash
python scripts/dismiss_overlay.py [--verify-element "档案"] [--max-tries 3]
```

**策略**（按序，每步后重新快照验证）：
1. 找名为 `×` / `X` / `关闭` 的可点元素 → 点
2. 点屏幕顶部 `(W/2, 60)` 的空白区（多数面板点外部关闭）
3. `keyevent 4`（Android 返回）
4. 若仍失败：打印当前元素清单，退出码 2

> ⚠️ **已知坑**：`mumu-control` 调研记录「X 关闭按钮第一次点不生效」，所以**每步都点两次**并中间等 300ms。

### 2.3 `go_back.py`

```bash
python scripts/go_back.py [--steps N] [--expect "元素名"]
```

- 逻辑：发 `keyevent 4`，快照；若 **当前前台包名 ≠ com.systempanel.app** → 说明退到了桌面 → 立即 `am start` 拉回并告警（退出码 3）
- `--expect`：返回后应出现的元素名，出现即成功

### 2.4 `goto_lobby.py`

```bash
python scripts/goto_lobby.py [--max-steps 6]
```

- 快照里若已有 `委托` + `TASK` → 已在大厅，直接返回
- 否则循环：先 `dismiss_overlay`，再点 `主线`（坐标 94,1561）
- 失败时 dump 当前元素清单

### 2.5 `wait_stable.py`

```bash
python scripts/wait_stable.py [--timeout 8] [--interval 0.4]
```

- 连续两次快照的元素数 + 元素名集合相同 → 认为稳定
- 超时退出码 4

---

## 2.6 · boot 过场处理（实测必需）

App 冷启动会停在「SYS // BOOT」过场 / 「触碰屏幕 · 唤醒系统」页，此时
**元素极少（6~7 个）且全部不可点**，任何 keyevent 都无效。`agent_common.skip_boot()`
会自动识别并点击屏幕中下部唤醒：

```python
from agent_common import skip_boot
skip_boot('127.0.0.1:16512', max_wait=30)
```

识别标记：`SYS//BOOT` / `唤醒序列就绪` / `触碰屏幕`。

`goto_lobby.py` 与 `dismiss_overlay.py` 已内置调用，无需手动处理。

---

## 2.7 · uiscan JSON 字段（实测）

`uiscan.py --save-json` 产出的是 **list**，坐标在 `coords.{x,y}`、尺寸在 `size.{width,height}`：

```json
{"index":0,"name":"LV","control_type":"TextView",
 "coords":{"x":88,"y":72},"size":{"width":40,"height":36},
 "clickable":false,"text":"","content_desc":""}
```

`agent_common.scan()` 已做归一化（`x/y/w/h` 提到顶层、`name` 兜底 `text/content_desc`），
脚本里直接用 `el['x']` / `el['y']` 即可。

---

## 3 · 使用范式

### 3.1 标准走查循环

```bash
# 1) 稳定后快照
python scripts/wait_stable.py
python scripts/ui_snapshot.py --name 01-lobby

# 2) 按文字点（直接用 mumu-control）
cd "C:/Users/buglan/.agents/skills/mumu-control"
python scripts/tap.py --text "档案" -s 127.0.0.1:16512

# 3) 快照验证
cd "E:/repo/system_panel/.claude/skills/android-agent"
python scripts/ui_snapshot.py --name 02-archive

# 4) 关闭弹层
python scripts/dismiss_overlay.py

# 5) 回大厅
python scripts/goto_lobby.py
```

### 3.2 改动前后对比

```bash
# 改代码前
python scripts/ui_snapshot.py --name before --out .verify/agent

# 改完重新构建安装后
python scripts/ui_snapshot.py --name after --out .verify/agent
python scripts/ui_snapshot.py --name after --out .verify/agent --compare .verify/agent/before_elements.json
```

### 3.3 常见陷阱与对策

| 陷阱 | 对策 |
|---|---|
| Git Bash 把 `/sdcard/x` 改写成 Windows 路径 | 用 `//sdcard/x` 或让脚本走 `adb exec-out`（本 skill 已处理） |
| 中文乱码 | 统一 `encoding='utf-8'` + `PYTHONIOENCODING=utf-8`（脚本内已设） |
| 点了没反应不知道是没点到还是 UI 没变 | 每次点击后 `ui_snapshot.py` 前后 diff |
| 返回键退出 App | `go_back.py` 会检测前台包名并自动拉回 |
| uiautomator dump 为空 | 先 `screenshot.py` 确认在前台；Flutter 需 `Semantics`（见任务四） |
| 多个 serial 指向同一台 | `adb devices` 只留一个；本 skill 默认 16512 |

---

## 4 · 与 mumu-control 的分工

| 能力 | 用谁 |
|---|---|
| 启动/关闭模拟器、查端口 | `mumu-cli.exe` / `MuMuManager.exe` |
| 截图 + OCR + 无障碍树 | `mumu-control/scripts/uiscan.py` |
| 按文字点 / 滑动 / 输入中文 | `mumu-control/scripts/tap.py` / `swipe.py` / `input_text.py` |
| **关弹层 / 返回 / 回大厅 / 快照对比** | **本 skill** |

---

## 5 · 验收

任一脚本都应：

- 退出码 0 = 成功，非 0 见各脚本注释
- 输出**中文无乱码**
- 不修改 App 任何文件（只操作模拟器）
