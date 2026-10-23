# 45 · 安卓模拟器 Agent 操作方案（skill / MCP 调研）

> 调研日期：2026-10-23 ｜ 整理日期：2026-10-23
> 原文：`E:\repo\研究\安卓模拟器Agent方案-skill与MCP调研.md`（259 行）
> 适用范围：本仓库（`E:\repo\system_panel`）Flutter 客户端 + MuMu Player 12 模拟器的 Agent 走查 / 操作 / 验证。
> 证据等级沿用原文标注：**〔实测〕** 已在本机跑通 ｜ **〔文档〕** 仅读官方文档 ｜ **〔未验证〕** 未跑过

---

## 0 · 一句话结论

**不要找 MCP。用 MuMu 官方 `mumu-control` skill（已装、已在本项目跑通）。**

```bash
# 一次性安装（全局）
npx skills add https://skills.mumu.163.com/mumu-control -g -a '*' -y
```

装完位于 `C:\Users\buglan\.agents\skills\mumu-control\`（9 个文件，网易官方，MIT，Windows only）。

**效率对比**：此前「MuMu 已启动，用 adb 连接操作验证」那一轮共 **64 次工具调用**；改用官方 skill 后，同一类任务 **2 条命令**（`uiscan.py` + `tap.py --text`）即可完成。

---

## 1 · 问题诊断：裸 adb 当「眼睛和手」为什么会卡

原文逐条核对了 session-8529ce5f 第 18 轮的 64 次工具调用，8 个卡点全部有日志实证：

| # | 卡点 | 代价 |
|---|---|---|
| 1 | `adb shell uiautomator dump` 产出文件 **size: 0**，UI 树根本没写出来 | 3 次调用反复试 |
| 2 | Git Bash 把 `/sdcard/ui.xml` 改写成 `C:/Users/.../sdcard/ui.xml`，只能靠 `//sdcard/` 绕 | 1 次试错 + 认知负担 |
| 3 | UI 树中文全是 `����` 乱码，无法用文本定位元素 | 只能退回「看截图猜坐标」 |
| 4 | 只能靠截图人肉读坐标：`input tap 94 1561` 一个个试 | 每次点击前都要截图 + 读图 |
| 5 | 点了没反应时，分不清「没点到」还是「点到了但 UI 没变」，一次连试 X / 空白 / 返回键 / 长按 | 一整轮排查 |
| 6 | 返回键直接把 App 退了（P0 bug），状态丢失需重启 | 重进一次 |
| 7 | Flutter 语义树默认未开，`uiautomator` 拿不到内容 | 卡死在第一步 |
| 8 | 想量化对比度 / 触控尺寸，只能自己写 5 个临时脚本（`_check.py` / `_contrast.py` / `_sample*.py`） | 5 个文件 + 1 次语法错误 |

**核心结论**：64 次调用里至少 **40 次** 是在与「没有 UI 元素模型」搏斗，不是在审查 App。

---

## 2 · 官方 skill：mumu-control

### 2.1 身份信息

| 项 | 值 |
|---|---|
| 名称 | `mumu-control` |
| 作者 | MuMu（网易官方） |
| 版本 | 1.2 · MIT · **Windows only** |
| 来源 | https://skills.mumu.163.com/mumu-control |
| 本机路径 | `C:\Users\buglan\.agents\skills\mumu-control\` |
| 组成 | `SKILL.md` + `requirements.txt` + 7 个脚本 |

### 2.2 两层架构

| 层 | 工具 | 寻址方式 | 职责 |
|---|---|---|---|
| 实例管理 | `mumu-cli.exe` | `--vmindex N` | 启动 / 关机 / 配置 / 装包 / 导入导出 |
| UI 自动化 | Python 脚本（`scripts/`） | `-s <serial>` | 截图 / 点按 / 滑动 / 输入 / OCR |

> ⚠️ `mumu-cli.exe` 是 `MuMuManager.exe` 的新名字。**实测二者是同一个二进制**（同为 18,454,520 字节、同一时间戳）〔实测 + 官方 SKILL.md 明说〕。

### 2.3 七个脚本能力表

| 脚本 | 干什么 | 解决的痛点 |
|---|---|---|
| `uiscan.py` | **截图 + 双源识别（无障碍树 + RapidOCR）**，输出标注图 + 元素 JSON | #1 #2 #3 #4 一次解决 |
| `tap.py` | 按坐标点 / **按文字自动 OCR 找 + 点** / 长按 | #4「猜坐标」 |
| `swipe.py` | 按坐标或方向滑动，自动算屏幕尺寸 | — |
| `input_text.py` | **支持中文输入**（裸 adb `input text` 不支持中文） | — |
| `keyevent.py` | home / back / enter / volume / dpad | — |
| `screenshot.py` | 单纯截图 | — |
| `common.py` | 公共模块（设备连接 / 元素模型 / 画框 / OCR 匹配） | — |

### 2.4 实测结果（在本项目 `com.systempanel.app` 上）

**A. 依赖安装**〔实测〕
```
uiautomator2 3.7.0 + opencv-python 5.0.0.93 + rapidocr-onnxruntime 1.2.3 + onnxruntime 1.23.0  ✓
```
> 踩坑：默认 pip 源与清华源均不通（`pypi=000`、`tsinghua=403`），阿里云仅 27KB/s，**腾讯云 60MB/s**。必须换 `-i https://mirrors.cloud.tencent.com/pypi/simple/`。

**B. `uiscan.py -s 127.0.0.1:16512 --save-json`**〔实测〕
```
Connected to 127.0.0.1:16512 (SDK 32, 780x1688)
Hierarchy: 19 elements / OCR: 14 text regions
Merged: 15 hierarchy + 2 OCR = 17 total

| Index | X   | Y    | Name          | Type                |
|-------|-----|------|---------------|---------------------|
| 0     | 78  | 72   | LV            | View                |
| 1     | 173 | 78   | 宿主          | View                |
| 4     | 211 | 109  | 「第一滴汗」  | View                |
| 8     | 640 | 1530 | 委托 TASK     | View (clickable)    |
| 9     | 94  | 1561 | 主线          | ImageView (clickable) |
| 10    | 222 | 1561 | 档案          | ImageView (clickable) |
| 11    | 350 | 1561 | 补给          | ImageView (clickable) |
| 14    | 640 | 1660 | 她手里有 5 单 | View                |
```
**中文零乱码，坐标直接可用**——与旧方案人肉试出的 `94 / 222 / 350, y=1561` 完全一致，但这里**一条命令、17 个元素全给**。

**C. `tap.py --text "档案"`**〔实测〕
```
Found "档案" at (222, 1610), tapped
```
→ 截图确认面板真的打开。

**D. 顺手复现 P0 bug**〔实测〕：档案面板打开后，「执行中 9:12:43」胶囊**压在人物脸上**。根因即 `exec_pill.dart:129 top:80` 撞 `main_view.dart Positioned(top:22)`。

**E. 额外发现：X 关闭按钮第一次点不生效**〔实测〕：点档案面板的 X（约 700,671）第一次没关掉，第二次才关。疑似**关闭动画期间按钮不可点 / 点击被吞**，建议单独验证（`tap.py 700 671` 连点两次即可复现）。

---

## 3 · 改用 skill 后的任务形态

| 环节 | 旧（裸 adb） | 新（mumu-control） |
|---|---|---|
| 拿到界面元素 | 3+ 次 adb dump，还失败 | `python scripts/uiscan.py -s <serial>` |
| 中文文本 | 乱码，不可用 | 正常 |
| 点某个按钮 | 截图→人肉读坐标→`input tap`→再截图 | `python scripts/tap.py --text "档案"` |
| 输入中文 | 不支持 | `python scripts/input_text.py "文字" --coord x y` |
| 滑动 | 手算坐标 | `python scripts/swipe.py --direction up` |
| 验证结果 | 再截一张图 | `python scripts/uiscan.py` 对比 |

**官方推荐循环**：
```
1. uiscan.py  → 截图 + 识别 → 标注图
2. AI 读标注图 → 找目标编号
3. tap.py     → 点击
4. uiscan.py  → 验证
5. 循环
```

---

## 4 · MCP 方案评估：暂不上

### 4.1 候选对比

| 项目 | 情况 |
|---|---|
| `nnaridz/mcp-mumu` | 号称 59 个工具，专为 MuMu Player 12 写。**但 npm 上无此包（`npm view mcp-mumu` → 404）**，只能从 GitHub 源码装；本机 GitHub 直连不通，**未能验证**〔未验证〕 |
| `mcp-android-emulator`（Anjos2） | `npm i -g mcp-android-emulator`，40 个工具，MIT，v2.0.0。通用 ADB，不绑 MuMu。**可安装**〔实测：npm 可查并下载〕 |
| `Teemo4621/MCP-Emulator-Controller` | 学习项目，能力弱 |

`mcp-android-emulator` 的工具面确实漂亮：`get_ui_tree` / `get_clickable_elements` / `tap_text` / `wait_for_element` / `wait_for_ui_stable` / `assert_screen_contains` / `get_logs` 等。

### 4.2 为什么打不过官方 skill（三条）

1. **官方 skill 是网易自己维护的**，知道 MuMu 的 `vmindex` / 端口规则 / `hide_window` 等私有语义；通用 MCP 只能看到 ADB 那一层。
2. **MCP 每个工具调用是一次独立 round-trip**，而 skill 脚本**一次进程内跑完「截图 + OCR + 合并 + 标注」**，token 与延迟都省。
3. **DSH 默认没装 MCP 客户端**——`cordis.patch.yml` 里没有任何 MCP 配置〔实测〕。

### 4.3 若将来确实要接 MCP

```
@deepseek-ai/dsh-mcp-client   ← MCP 客户端桥（把 MCP server 的工具注册到 ctx.tools）
        ↑
   cordis.patch.yml 里加一条登记
```

- `@deepseek-ai/dsh-mcp-client`：npm 上有，`0.0.1-rc.1` / `next: 0.2.1-rc.2`，官方（deepseek.com）维护，BSD-3-Clause〔实测：npm 可查〕
- `dsh-plug-mcp`：第三方图形化管理面板（设置 → 插件 → MCP），可搜 GitHub `topic:mcp-server` 一键装〔文档，未实测〕

**建议**：等官方 skill 用顺、确实缺某个能力时再考虑。

---

## 5 · 配套 skill 分工

| Skill | 什么时候用 | 与模拟器的关系 |
|---|---|---|
| **`mumu-control`** | 任何「操作模拟器 / 点 App / 截图 / 走查」 | 核心，直接驱动 |
| `ui-ux-pro-max` | 拿到截图后做设计审查 | 消费 `uiscan.py` 的产物 |
| `improve-animations` | 审查动效实现 | 同上 |
| `find-animation-opportunities` | 找「该动没动」的地方 | 同上 |
| `agent-browser` | 仅 **Web 原型**阶段有用 | 与模拟器无关 |

> ⚠️ `gpt-taste` / `design-taste-frontend` 是**做设计**的，不是**审查现有 App** 的，方向不对。

---

## 6 · 落地步骤（照抄即可）

### 6.1 一次性安装

```bash
# 1. 装 skill（全局）
npx skills add https://skills.mumu.163.com/mumu-control -g -a '*' -y

# 2. 装 Python 依赖（务必用腾讯源）
pip install -r "C:/Users/buglan/.agents/skills/mumu-control/requirements.txt" \
  -i https://mirrors.cloud.tencent.com/pypi/simple/

# 3. 验证
python -c "import cv2, uiautomator2; from rapidocr_onnxruntime import RapidOCR; print('OK')"
```

### 6.2 每次用的模板

```bash
SKILL="C:/Users/buglan/.agents/skills/mumu-control"
MUMU="E:/MuMu Player 12/nx_main"
SERIAL="127.0.0.1:16512"     # ← 先跑 "$MUMU/MuMuManager.exe" info -v all 查 adb_port

# 1) 确保实例起来了
"$MUMU/MuMuManager.exe" control -v 4 launch
"$MUMU/MuMuManager.exe" info -v 4 | grep is_android_started   # 等到 true

# 2) 看清界面（一条命令拿到全部元素 + 标注图）
cd "$SKILL" && python scripts/uiscan.py -s "$SERIAL" --save-json

# 3) 按文字点（不用算坐标）
python scripts/tap.py --text "档案" -s "$SERIAL"

# 4) 验证
python scripts/uiscan.py -s "$SERIAL"
```

---

## 7 · Flutter 端「可被 Agent 看见」的能力（已落地）

**问题**：Flutter 的 UI 树对 agent 几乎是空的——实测大厅只有 17 个元素、**0 个 resource-id**，Agent 只能靠 OCR 猜。

**方案**：新增 `app/lib/dev/agent_bridge.dart`，四条通道：

| 能力 | API | Agent 侧怎么用 |
|---|---|---|
| 语义树 | `AgentBridge.enableSemantics()` | `uiautomator dump` / `uiscan.py` 能读到中文标签（不再是空树） |
| 节点标记 | `AgentTag(id:, label:, button:, role:)` | 元素名里出现 `agent:<id>`，可直接检索，不依赖文字匹配 |
| 组件树导出 | `AgentBridge.dumpTree()` | 输出 Widget 树 JSON（类型 / key / 文本 / 屏幕矩形） |
| 截图 | `AgentBridge.screenshot(name:)` | 写 PNG 到 `/sdcard/agent/`，不依赖 adb screencap |

**开关**：`kAgentBridgeEnabled = kDebugMode || --dart-define=AGENT_BRIDGE=true`。**release 包零影响**——`AgentTag` 在关闭时原样返回 `child`，不产生额外节点。

**已打标的节点**（可继续加）：

| Agent id | 位置 | 说明 |
|---|---|---|
| `agent:dock.主线` / `agent:dock.档案` / `agent:dock.补给` | `dock.dart` `_Dk` | 三颗侧键 |
| `agent:dock.cta` | `dock.dart` `_Core` | 中央委托环 |
| `agent:exec.pill` | `exec_pill.dart` | 顶部「执行中」胶囊 |
| `agent:main.close` | `main_view.dart`（原有 Semantics） | 主线关闭 |

**验证方式**（一条命令）：

```bash
cd "C:/Users/buglan/.agents/skills/mumu-control"
python scripts/uiscan.py -s 127.0.0.1:16512 --save-json
# 元素表里出现 agent:dock.主线 这类名字 = 语义树已生效
```

**为什么不全量包 Semantics**：`Semantics` 会给每个节点建额外 RenderObject，动画密集型界面（本 App 的 Live2D + 卡牌）全量包会掉帧。所以只对**关键可交互节点**用 `AgentTag`，其余交给全局语义树 + OCR 兜底。

---

---

## 8 · 参考链接

- 官方 skill 包：https://skills.mumu.163.com/mumu-control
- 官方 mumu-cli 文档：https://mumu.163.com/redirect/nx/function/mumucli/
- `mcp-android-emulator`（40 tools）：https://github.com/Anjos2/mcp-android-emulator
- `nnaridz/mcp-mumu`（59 tools，**未验证**）：https://github.com/nnaridz/mcp-mumu
- `@deepseek-ai/dsh-mcp-client`：https://www.npmjs.com/package/@deepseek-ai/dsh-mcp-client
- `dsh-plug-mcp`（MCP 管理面板）：https://github.com/Casually/dsh-plug-mcp

---

## 9 · 证据等级汇总

| 结论 | 等级 |
|---|---|
| session 第 18 轮 64 次调用、UI 树 size:0、中文乱码、`//sdcard` 绕路 | ✅ 逐条核对 session 日志 |
| `mumu-control` 官方、MIT、9 文件、装到本机 | ✅ 实测 |
| `uiscan.py` 出 17 元素、中文正常、坐标正确 | ✅ 实测（本项目 App） |
| `tap.py --text "档案"` 成功打开面板 | ✅ 实测 + 截图 |
| `uiautomator2` 3.7.0 直连 MuMu 16512 成功 | ✅ 实测 |
| 依赖必须用腾讯源 | ✅ 实测（阿里云 27KB/s vs 腾讯 60MB/s） |
| `mumu-cli.exe` == `MuMuManager.exe` | ✅ 实测 + 官方 SKILL.md |
| `mcp-mumu` 59 工具 | ⚠️ 仅见 GitHub 描述，未拉取未运行 |
| `dsh-plug-mcp` 图形化装 MCP | ⚠️ 仅读 npm 描述 |
| DSH 默认无 MCP 配置 | ✅ 检查 `cordis.patch.yml` 无 mcp 条目 |
