# -*- coding: utf-8 -*-
"""go_back.py — 逐级返回（不退出 App）。

逻辑:
  发 keyevent 4 → 快照 → 若前台包名不是 com.systempanel.app（退到桌面）
  → 立即 am start 拉回并告警（退出码 3）

用法:
    python go_back.py [--serial S] [--steps N] [--expect "元素名"]

退出码: 0=成功 / 2=扫描失败 / 3=返回键导致退出（已自动拉回）
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agent_common import (DEFAULT_SERIAL, PACKAGE, adb, scan, find_by_name,
                          keyevent, launch_app, wait_stable)


def foreground_package(serial):
    rc, out, _ = adb(serial, 'shell', 'dumpsys window | grep mCurrentFocus')
    if PACKAGE in out:
        return PACKAGE
    rc, out2, _ = adb(serial, 'shell', 'dumpsys activity activities | grep mResumedActivity')
    if PACKAGE in out2:
        return PACKAGE
    return out.strip()[:120] or '(unknown)'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--serial', default=DEFAULT_SERIAL)
    ap.add_argument('--steps', type=int, default=1)
    ap.add_argument('--expect', default=None)
    ap.add_argument('--out', default=os.path.join(os.getcwd(), '.verify', 'agent'))
    args = ap.parse_args()

    for i in range(args.steps):
        print('--- 返回第 %d/%d 步 ---' % (i + 1, args.steps))
        keyevent(args.serial, 4)
        time.sleep(0.6)

        fg = foreground_package(args.serial)
        print('前台: %s' % fg)
        if PACKAGE not in fg:
            print('[warn] 返回键退出了 App，正在拉回')
            launch_app(args.serial)
            time.sleep(2.0)
            return 3

        els = wait_stable(args.serial, timeout=3.0, out_dir=args.out)
        if args.expect:
            if find_by_name(els, args.expect):
                print('✓ 已出现「%s」' % args.expect)
                return 0
            else:
                print('[warn] 未出现「%s」，继续' % args.expect)

    return 0


if __name__ == '__main__':
    sys.exit(main())
