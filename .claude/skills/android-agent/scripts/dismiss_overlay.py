# -*- coding: utf-8 -*-
"""dismiss_overlay.py — 关闭当前弹层。

策略（按序，每步后重新快照验证）:
  1. 找名为 × / X / 关闭 / 取消 的可点元素 → 点（点两次，间隔 300ms）
  2. 点屏幕上方空白区 (W/2, 60)
  3. keyevent 4（返回）
  4. 仍失败 → 打印元素清单，退出码 2

用法:
    python dismiss_overlay.py [--serial S] [--expect "元素名"] [--max-tries 3]

退出码: 0=已关闭 / 2=关不掉（附元素清单）
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agent_common import (DEFAULT_SERIAL, adb, scan, find_by_name,
                          element_names, keyevent, tap, wait_stable, skip_boot)


def screen_size(serial):
    rc, out, _ = adb(serial, 'shell', 'wm', 'size')
    # Physical size: 780x1688 / Override size: 780x1688
    w = h = 0
    for line in out.splitlines():
        if ':' in line and 'x' in line:
            val = line.split(':')[-1].strip()
            try:
                w, h = [int(v) for v in val.split('x')]
            except ValueError:
                pass
    return w or 780, h or 1688


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--serial', default=DEFAULT_SERIAL)
    ap.add_argument('--expect', default=None, help='关闭后应出现的元素名（验证用）')
    ap.add_argument('--max-tries', type=int, default=3)
    ap.add_argument('--out', default=os.path.join(os.getcwd(), '.verify', 'agent'))
    args = ap.parse_args()

    close_keys = ['×', 'X', '✕', '关闭', '取消', 'close', '等会儿']

    # 若在 boot 过场，先跳过
    skip_boot(args.serial, out_dir=args.out)

    for attempt in range(1, args.max_tries + 1):
        print('--- 第 %d 轮 ---' % attempt)
        els = scan(args.serial, out_dir=args.out, name='dismiss_%d' % attempt)
        if not els:
            print('[warn] 扫描为空，重试')
            time.sleep(0.5)
            continue

        if args.expect and find_by_name(els, args.expect):
            print('已出现目标元素「%s」，无需关闭' % args.expect)
            return 0

        btn = find_by_name(els, close_keys, clickable_only=True)
        if btn:
            print('找到关闭按钮「%s」(%d,%d)，点击两次' % (
                (btn.get('name') or '').replace('\n', ' '), btn['x'], btn['y']))
            for _ in range(2):
                tap(args.serial, btn['x'], btn['y'])
                time.sleep(0.3)
            after = wait_stable(args.serial, timeout=3.0, out_dir=args.out)
            if args.expect and find_by_name(after, args.expect):
                print('✓ 已关闭（出现「%s」）' % args.expect)
                return 0
            if args.expect is None and not find_by_name(after, close_keys, clickable_only=True):
                print('✓ 关闭按钮已消失，视为已关闭')
                return 0

        # 2. 点上方空白
        w, h = screen_size(args.serial)
        print('尝试点上方空白 (%d, 60)' % (w // 2))
        tap(args.serial, w // 2, 60)
        time.sleep(0.4)
        after = wait_stable(args.serial, timeout=2.5, out_dir=args.out)
        if args.expect and find_by_name(after, args.expect):
            print('✓ 已关闭（出现「%s」）' % args.expect)
            return 0

        # 3. 返回键
        print('尝试返回键')
        keyevent(args.serial, 4)
        time.sleep(0.5)
        after = wait_stable(args.serial, timeout=2.5, out_dir=args.out)

        # 返回键可能把 App 退了 —— 检测并拉回
        rc, out, _ = adb(args.serial, 'shell', 'dumpsys window | grep mCurrentFocus')
        from agent_common import PACKAGE, launch_app
        if PACKAGE not in out:
            print('[warn] 返回键把 App 退到后台，正在拉回')
            launch_app(args.serial)
            time.sleep(1.5)

    print('[fail] %d 轮后仍未关闭' % args.max_tries)
    els = scan(args.serial, out_dir=args.out, name='dismiss_fail')
    print('当前元素:', element_names(els))
    return 2


if __name__ == '__main__':
    sys.exit(main())
