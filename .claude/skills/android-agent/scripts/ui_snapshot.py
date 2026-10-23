# -*- coding: utf-8 -*-
"""ui_snapshot.py — 截图 + 元素 JSON + 标注图，支持基线对比。

用法:
    python ui_snapshot.py [--serial S] [--name NAME] [--out DIR] [--compare BASELINE.json]

退出码:
    0 = 正常 / 无差异
    1 = --compare 模式下发现差异
    2 = 环境错误（设备不在线 / 扫描失败）
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agent_common import DEFAULT_SERIAL, PACKAGE, adb, scan, element_names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--serial', default=DEFAULT_SERIAL)
    ap.add_argument('--name', default='snapshot')
    ap.add_argument('--out', default=os.path.join(os.getcwd(), '.verify', 'agent'))
    ap.add_argument('--compare', default=None, help='基线 elements.json 路径')
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    rc, out, err = adb(args.serial, 'get-state')
    if 'device' not in out:
        print('[error] 设备不在线: %s (%s)' % (args.serial, err.strip()))
        return 2

    elements = scan(args.serial, out_dir=args.out, name=args.name)
    if not elements:
        print('[error] 扫描失败或界面为空')
        return 2

    json_path = os.path.join(args.out, args.name + '_elements.json')
    print('元素数: %d' % len(elements))
    print('截图: %s' % os.path.join(args.out, args.name + '_annotated.png'))
    print('JSON: %s' % json_path)

    if not args.compare:
        return 0

    if not os.path.isfile(args.compare):
        print('[error] 基线不存在: %s' % args.compare)
        return 2

    with open(args.compare, encoding='utf-8') as f:
        base = json.load(f)
    base_els = base if isinstance(base, list) else base.get('elements', [])

    def normalize(els):
        out = []
        for e in els:
            item = dict(e)
            c = e.get('coords') or {}
            item.setdefault('x', c.get('x'))
            item.setdefault('y', c.get('y'))
            if not item.get('name'):
                item['name'] = item.get('text') or item.get('content_desc') or ''
            if item.get('x') is not None and item.get('y') is not None:
                out.append(item)
        return out

    def keyed(els):
        d = {}
        for e in normalize(els):
            n = (e.get('name') or '').replace('\n', ' ').strip()
            if n:
                d[n] = e
        return d

    b, c = keyed(base_els), keyed(elements)
    added = sorted(set(c) - set(b))
    removed = sorted(set(b) - set(c))
    moved = []
    for n in sorted(set(b) & set(c)):
        dx = abs(b[n].get('x', 0) - c[n].get('x', 0))
        dy = abs(b[n].get('y', 0) - c[n].get('y', 0))
        if dx > 8 or dy > 8:
            moved.append((n, b[n].get('x'), b[n].get('y'), c[n].get('x'), c[n].get('y')))

    print('')
    print('===== 与基线对比 =====')
    print('新增 %d:' % len(added), added[:10])
    print('消失 %d:' % len(removed), removed[:10])
    print('移动 %d (>8px):' % len(moved))
    for n, x1, y1, x2, y2 in moved[:10]:
        print('  %-20s (%d,%d) -> (%d,%d)' % (n, x1, y1, x2, y2))

    return 1 if (added or removed or moved) else 0


if __name__ == '__main__':
    sys.exit(main())
