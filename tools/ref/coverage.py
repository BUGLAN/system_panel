#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
覆盖审计：把原型里所有的 id / class 列出来，逐个对 Flutter 侧核。

为什么要有这个：PORTING-NOTES #19 —— 当年大厅比到 1.5% 之后才做了一次这样的审计，
发现 `#ringTag`（当前环的挂签）**根本没移植**，而我的区域表里没有它，
所以连着八轮比对都"合格"。

用法：
    python tools/ref/coverage.py            # 打印报告
    python tools/ref/coverage.py --md       # 输出 Markdown（可直接贴进文档）

判定方式：每个原型 id 在 `MAP` 里给出它对应的 Flutter 标识（Key / 类名 / 文件名），
脚本去 `app/lib` 里 grep 那个标识是否真的出现过 —— 所以**报告不会被写成"应该有"**，
它只认代码里真有的东西。
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTO = ROOT / "prototype" / "opus-v2-dir"
APP = ROOT / "app" / "lib"

# 原型 id → Flutter 侧用来证明它存在的标识
MAP = {
    "app": "AppShell",
    "ask": "AskField",
    "askIn": "AskField",
    "askPresets": "AskField",
    "askPs": "AskField",
    "banner": "SysBanner",
    "beam": "SheetBeam",
    "beamG": "SheetBeam",
    "beamL": "SheetBeam",
    "beamPoly": "SheetBeam",
    "beamR": "SheetBeam",
    "bg": "BgLayer",
    "bgWord": "BgLayer",
    "boot": "BootScreen",
    "btBar": "BootScreen",
    "btClock": "BootScreen",
    "btGo": "BootScreen",
    "btLog": "BootScreen",
    "btTip": "BootScreen",
    "choices": "Choices",
    "cta": "Dock",
    "ctaCap": "Dock",
    "ctaLabel": "Dock",
    "ctaN": "Dock",
    "ctaSub": "Dock",
    "dock": "Dock",
    "exec": "ExecPanel",
    "execPill": "ExecPill",
    "failv": "FailLayer",
    "flash": "FlashLayer",
    "fx": "FxField",
    "hud": "Hud",
    "hudCoin": "Hud",
    "hudLv": "Hud",
    "hudLvN": "Hud",
    "hudMenu": "Hud",
    "hudName": "Hud",
    "hudStreak": "Hud",
    "hudTitle": "Hud",
    "line": "LineLayer",
    "lineMood": "LineLayer",
    "lineTxt": "TypeText",
    "lvArc": "Hud",
    "mainv": "MainView",
    "pillT": "ExecPill",
    "plate": "Plate",
    "plateAlt": "PlateAlt",
    "result": "ResultPanel",
    "ringLabels": "RingLabels",
    "ringTag": "RingTag",
    "rtName": "RingTag",
    "rtNum": "RingTag",
    "shake": "ShakeLayer",
    "shBody": "Sheet",
    "sheet": "Sheet",
    "shK": "Sheet",
    "shT": "Sheet",
    "shX": "Sheet",
    "ui": "Stack",
    "veil": "Veil",
    "ringCv": "RingField",
    # ── 下面这些是 JS 里动态建出来的 id（innerHTML 模板），同样是真 id ──
    "exT": "ExecPanel",
    "exBar": "exec.bar",
    "exCrit": "ExecPanel",
    "exEye": "ExecPanel",
    "exDrawer": "exec.drawer",
    "exGo": "exec.go",
    "exItem": "exec.item",
    "exItemN": "exec.item",
    "exMin": "exec.min",
    "exQuit": "exec.quit",
    "exSlots": "ExecPanel",
    "exTags": "ExecPanel",
    "fpSub": "plate.print",
    "fpTxt": "plate.print",
    "fvRem": "fail.remedy",
    "mvDetail": "main.detail",
    "mvGo": "main.dispatch",
    "mvNew": "main.newGoal",
    "mvX": "main.close",
    "plPrint": "plate.print",
    "plReward": "Plate",
    "rsBar": "result.bar",
    "rsBarI": "result.bar.fill",
    "rsCard": "result.card",
    "rsExp": "ResultPanel",
    "rsGain": "result.gain",
    "rsGlyph": "result.glyph",
    "rsHead": "ResultPanel",
    "rsLv": "ResultPanel",
    "rsNear": "ResultPanel",
    "rsNeed": "ResultPanel",
    "rsSave": "result.save",
    "rsTags": "ResultPanel",
    "wipe": "sheet.danger",
    # ── 故意不移植的 ────────────────────────────────────────────
    "demo": None,       # 桌面演示控制台（开发工具）
    "dmCrit": None,
    "desk": None,       # 桌面外壳：把手机框 + 控制台并排摆
    "phone": None,
    "filePick": None,   # 证据拍照（要真相机；等规则）
    "hit": None,        # 戳她的命中层（要模型）
    "stage": None,      # Live2D 画布
    "stageCv": None,
}

# 这些 id 之所以没移植，必须写清原因（报告里会印出来）
WHY = {
    "demo": "桌面演示控制台 —— 开发工具，移动端不需要",
    "dmCrit": "同上",
    "desk": "桌面外壳（手机框并排演示台）—— 移动端不需要",
    "phone": "同上",
    "filePick": "证据拍照：要真相机（image_picker）+ 证据规则",
    "hit": "戳她的命中层：依赖 B1 模型",
    "stage": "Live2D 画布：依赖 B1 模型（见 STAGE-OPTIONS.md）",
    "stageCv": "同上",
}


def proto_ids() -> list:
    """原型里出现的全部 id（index.html 的 + JS 动态建的）"""
    out = set()
    for f in [PROTO / "index.html"] + sorted((PROTO / "js").glob("*.js")):
        text = f.read_text(encoding="utf-8", errors="ignore")
        out |= set(re.findall(r'id="([A-Za-z0-9_-]+)"', text))
        out |= set(re.findall(r"\.id\s*=\s*'([A-Za-z0-9_-]+)'", text))
    return sorted(out)


def app_sources() -> str:
    return "\n".join(
        p.read_text(encoding="utf-8", errors="ignore")
        for p in APP.rglob("*.dart")
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", action="store_true", help="输出 Markdown")
    args = ap.parse_args()

    src = app_sources()
    ids = proto_ids()
    rows = []
    for i in ids:
        token = MAP.get(i, "?")
        if token == "?":
            rows.append((i, "?", False, "?? 映射表里没登记这个 id"))
            continue
        if token is None:
            rows.append((i, "—", False, WHY.get(i, "故意不移植")))
            continue
        hit = re.search(r"\b" + re.escape(token) + r"\b", src) is not None
        rows.append((i, token, hit, "" if hit else "[MISS] 代码里找不到这个标识"))

    done = [r for r in rows if r[2]]
    skipped = [r for r in rows if r[1] == "—"]
    missing = [r for r in rows if not r[2] and r[1] != "—"]

    if args.md:
        print("| 原型 id | Flutter | 状态 |")
        print("|---|---|---|")
        for i, token, hit, why in rows:
            mark = "OK" if hit else ("--" if token == "--" else "[MISS]")
            note = f"（{why}）" if why else ""
            print(f"| `#{i}` | {token} | {mark}{note} |")
        print()
    print(f"原型 id 共 {len(rows)} 个：已移植 {len(done)}，"
          f"故意不移植 {len(skipped)}，缺失 {len(missing)}")
    for i, token, hit, why in missing:
        print(f"  [MISS] #{i} -> {token} {why}")
    for i, token, hit, why in skipped:
        print(f"  —  #{i}：{why}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())

