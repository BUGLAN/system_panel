# -*- coding: utf-8 -*-
"""wait_stable.py — 等待界面稳定。

连续两次快照的元素「数量 + 名称集合」相同 → 认为稳定。

用法:
    python wait_stable.py [--serial S] [--timeout 8] [--interval 0.4]

退出码: 0=稳定 / 4=超时
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agent_common import DEFAULT_SERIAL, scan, element_names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--serial', default=DEFAULT_SERIAL)
    ap.add_argument('--timeout', type=float, default=8.0)
    ap.add_argument('--interval', type=float, default=0.4)
    ap.add_argument('--out', default=os.path.join(os.getcwd(), '.verify', 'agent'))
    args = ap.parse_args()

    deadline = time.time() + args.timeout
    prev = None
    while time.time() < deadline:
        cur = scan(args.serial, out_dir=args.out, name='stable')
        names = element_names(cur)
        if prev is not None and prev == names:
            print('✓ 已稳定（%d 个元素）' % len(cur))
            return 0
        prev = names
        time.sleep(args.interval)

    print('[timeout] %.1fs 内未稳定' % args.timeout)
    return 4


if __name__ == '__main__':
    sys.exit(main())
