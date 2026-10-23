# -*- coding: utf-8 -*-
"""goto_lobby.py — 回到大厅。

快照里若同时有「委托」和「TASK」→ 已在大厅，直接返回。
否则循环：先关弹层，再点「主线」(94,1561)。

用法:
    python goto_lobby.py [--serial S] [--max-steps 6]

退出码: 0=已在大厅 / 2=失败
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agent_common import (DEFAULT_SERIAL, scan, find_by_name,
                          element_names, keyevent, tap, wait_stable, adb, PACKAGE,
                          launch_app, skip_boot)


def is_lobby(els):
    names = ' '.join(element_names(els))
    return ('委托' in names and 'TASK' in names) or ('主线' in names and '补给' in names)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--serial', default=DEFAULT_SERIAL)
    ap.add_argument('--max-steps', type=int, default=6)
    ap.add_argument('--out', default=os.path.join(os.getcwd(), '.verify', 'agent'))
    args = ap.parse_args()

    # 先处理 boot 过场 / 唤醒页
    if not skip_boot(args.serial, out_dir=args.out):
        print('[fail] boot 过场未结束')
        return 2

    for step in range(1, args.max_steps + 1):
        print('--- 第 %d 步 ---' % step)
        els = scan(args.serial, out_dir=args.out, name='lobby_%d' % step)
        if is_lobby(els):
            print('✓ 已在大厅')
            return 0

        # 关弹层：优先点「等会儿」（派单板的退出键）或「×」
        alt = find_by_name(els, ['等会儿', '×', 'X', '关闭'], clickable_only=True)
        if alt:
            print('点「%s」退出当前层' % (alt.get('name') or '').replace('\n', ' '))
            tap(args.serial, alt['x'], alt['y'])
            time.sleep(0.6)
            continue

        # 点主线侧键
        main_btn = find_by_name(els, ['主线'], clickable_only=True)
        if main_btn:
            print('点「主线」(%d,%d)' % (main_btn['x'], main_btn['y']))
            tap(args.serial, main_btn['x'], main_btn['y'])
            time.sleep(0.8)
            continue

        # 兜底：返回键（检测是否退出）
        print('无可用元素，按返回键')
        keyevent(args.serial, 4)
        time.sleep(0.6)
        rc, out, _ = adb(args.serial, 'shell', 'dumpsys window | grep mCurrentFocus')
        if PACKAGE not in out:
            print('[warn] 已退出 App，重新启动')
            launch_app(args.serial)
            time.sleep(2.0)

    print('[fail] %d 步后仍未回到大厅' % args.max_steps)
    return 2


if __name__ == '__main__':
    sys.exit(main())
