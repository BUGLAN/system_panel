#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
总回归：把 `.verify/cmp_step*.py` 全部跑一遍，抽出每份的 `full:` 行汇总成一张表。

为什么要有这个：单页比对脚本有十几个，改完一处（比如相机弹簧、抽屉、药丸）
要靠手一个个跑、再人工对照，很容易漏掉"这一改动把别的页带歪了"。
一条命令出一张表，超阈值的直接标出来。

用法：
    python tools/ref/regress.py             # 跑全部并出表
    python tools/ref/regress.py --limit 4   # 只报超过 4% 的（默认 4.0）

注意：它**只读**已有的截图，不负责抓图。抓图见 README 的驱动流程。
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
VERIFY = ROOT / ".verify"

# 脚本 → 页面名（顺序即报告顺序）
#
# ⚠️ 开机屏那一页**天生不适合比对**：它的 TIPS 是随机取一句、日志行是逐行出现的，
#    两次抓图本来就不一样。它列在这里是为了"不漏页"，但那个数字不能当回归信号。
PAGES = [
    ("cmp_step1.py", "开机屏(随机，仅参考)"),
    ("cmp_step13.py", "绑定仪式"),
    ("cmp_step13b.py", "横幅"),
    ("cmp_step2.py", "大厅"),
    ("cmp_step3.py", "派单板"),
    ("cmp_step4.py", "执行"),
    ("cmp_step5.py", "结算"),
    ("cmp_step6.py", "失败"),
    ("cmp_step10.py", "主线全景"),
    ("cmp_step7.py", "面板·档案"),
    ("cmp_step8.py", "面板·补给 + 系统"),
    ("cmp_step16.py", "环场(只比环区*)"),
]

# 两种写法都要认：
#   多数脚本 → `full: diff>40 6901 (2.1%)`
#   cmp_step1.py → `全图: 差异>40 的像素 32709 (9.9%)`（注意那个「的像素」）
FULL = re.compile(
    r"(?:full|全图):\s*(?:diff|差异)>40\s*(?:的像素\s*)?(\d+)\s*\(([\d.]+)%\)"
)

# 这些页的整帧百分比**不能当判定**（只列出来不漏页）：
#   开机屏  —— TIPS 随机取一句、日志逐行出现，两次抓图本来就不一样
#   环场    —— 参考图只裁了环区，整帧对比的是"环区 vs 整屏"
NO_JUDGE = {"开机屏(随机，仅参考)", "环场(只比环区*)"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=float, default=4.0,
                    help="超过这个百分比就标红（默认 4.0）")
    args = ap.parse_args()

    rows, worst = [], 0.0
    for script, page in PAGES:
        path = VERIFY / script
        if not path.exists():
            rows.append((page, script, None, "脚本不存在"))
            continue
        # ⚠️ 子脚本在 Windows 上默认按 GBK 打印中文（"全图: 差异>40 像素 …"），
        #    这里必须让它也用 UTF-8 输出，否则中文关键字解码成乱码、正则匹配不上
        #    —— 症状就是"没抓到 full: 行"（开机屏那一页踩过）。
        env = dict(os.environ, PYTHONIOENCODING="utf-8")
        out = subprocess.run(
            [sys.executable, str(path)],
            capture_output=True, text=True, encoding="utf-8", errors="ignore",
            env=env,
        ).stdout
        hits = FULL.findall(out)
        if not hits:
            rows.append((page, script, None, "没抓到 full: 行"))
            continue
        # 一个脚本可能比多页（cmp_step8 有补给 + 系统两段），全列出来
        for n, pct in hits:
            rows.append((page, script, (int(n), float(pct)), ""))
            if page not in NO_JUDGE:
                worst = max(worst, float(pct))

    print(f"{'页面':<20} {'diff>40':>9} {'占比':>7}  判定")
    print("-" * 56)
    bad = 0
    for page, script, val, err in rows:
        if val is None:
            print(f"{page:<20} {'-':>9} {'-':>7}  {err}")
            continue
        n, pct = val
        if page in NO_JUDGE:
            flag = "参考"
        else:
            flag = "OK" if pct <= args.limit else "!! 超阈值"
            if pct > args.limit:
                bad += 1
        print(f"{page:<20} {n:>9} {pct:>6.1f}%  {flag}")
    print("-" * 56)
    print(f"最差 {worst:.1f}% · 阈值 {args.limit}% · "
          f"{'全部通过' if bad == 0 else f'{bad} 页超阈值'}")
    print("* 环场那张参考图只裁了环区（`refRings`），所以它的整帧百分比"
          "没有意义 —— 看脚本自己印的区域表。")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
