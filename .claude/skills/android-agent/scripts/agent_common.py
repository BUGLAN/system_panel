# -*- coding: utf-8 -*-
"""android-agent · 公共模块

被 dismiss_overlay / go_back / goto_lobby / ui_snapshot / wait_stable 共用。
依赖 mumu-control 的 common.py（元素模型 + OCR）。
"""
import io
import json
import os
import subprocess
import sys
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

DEFAULT_SERIAL = os.environ.get('AGENT_SERIAL', '127.0.0.1:16512')
PACKAGE = 'com.systempanel.app'
ACTIVITY = 'com.systempanel.app/.MainActivity'
SKILL_DIR = os.environ.get(
    'MUMU_CONTROL_DIR',
    r'C:/Users/buglan/.agents/skills/mumu-control',
)

# 把 mumu-control 的 scripts 目录加入 sys.path
_SCRIPTS = os.path.join(SKILL_DIR, 'scripts')
if os.path.isdir(_SCRIPTS) and _SCRIPTS not in sys.path:
    sys.path.insert(0, _SCRIPTS)


def adb(serial, *args, timeout=20):
    """执行 adb 命令，返回 (returncode, stdout, stderr)。"""
    cmd = ['adb', '-s', serial] + list(args)
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout)
        return (p.returncode,
                p.stdout.decode('utf-8', errors='replace'),
                p.stderr.decode('utf-8', errors='replace'))
    except subprocess.TimeoutExpired:
        return (124, '', 'timeout')
    except FileNotFoundError:
        return (127, '', 'adb not found')


def shell(serial, cmd, timeout=20):
    return adb(serial, 'shell', cmd, timeout=timeout)


def tap(serial, x, y):
    return shell(serial, 'input tap %d %d' % (int(x), int(y)))


def keyevent(serial, code):
    return shell(serial, 'input keyevent %d' % code)


def current_package(serial):
    """当前前台包名；取不到返回空串。"""
    rc, out, _ = shell(serial, 'dumpsys window | grep mCurrentFocus')
    if PACKAGE in out:
        return PACKAGE
    # 兜底：用 dumpsys activity
    rc, out2, _ = shell(serial, 'dumpsys activity activities | grep mResumedActivity')
    if PACKAGE in out2:
        return PACKAGE
    return ''


def launch_app(serial):
    return adb(serial, 'shell', 'am start -n %s' % ACTIVITY)


def scan(serial, out_dir=None, name='scan'):
    """调用 mumu-control 的 uiscan.py，返回元素列表。

    返回: list[dict(index,x,y,name,type,clickable,raw)]
    失败返回 []
    """
    out_dir = out_dir or os.path.join(os.getcwd(), '.verify', 'agent')
    os.makedirs(out_dir, exist_ok=True)
    script = os.path.join(_SCRIPTS, 'uiscan.py')
    if not os.path.isfile(script):
        print('[warn] uiscan.py 不存在: %s' % script)
        return []
    cmd = [sys.executable, script, '-s', serial, '-o', out_dir, '-n', name, '--save-json']
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=180)
    except subprocess.TimeoutExpired:
        print('[warn] uiscan 超时')
        return []
    out = p.stdout.decode('utf-8', errors='replace')
    if p.returncode != 0:
        print('[warn] uiscan 失败: %s' % p.stderr.decode('utf-8', errors='replace')[:300])
        return []
    json_path = os.path.join(out_dir, name + '_elements.json')
    if os.path.isfile(json_path):
        try:
            with open(json_path, encoding='utf-8') as f:
                data = json.load(f)
            # mumu-control 可能直接给 list 或 {'elements': [...]}
            els = data if isinstance(data, list) else data.get('elements', [])
            # 归一化：uiscan 的坐标在 coords.{x,y}，统一提到顶层 x/y
            norm = []
            for e in els:
                c = e.get('coords') or {}
                item = dict(e)
                if 'x' not in item:
                    item['x'] = c.get('x')
                if 'y' not in item:
                    item['y'] = c.get('y')
                sz = e.get('size') or {}
                if 'w' not in item:
                    item['w'] = sz.get('width')
                if 'h' not in item:
                    item['h'] = sz.get('height')
                # name 兜底：text / content_desc
                if not item.get('name'):
                    item['name'] = item.get('text') or item.get('content_desc') or ''
                norm.append(item)
            return [e for e in norm if e.get('x') is not None and e.get('y') is not None]
        except Exception as e:
            print('[warn] 读取元素 JSON 失败: %s' % e)
    return []


def find_by_name(elements, keywords, clickable_only=False):
    """按名称模糊查找（任一关键词命中）。返回第一个匹配元素或 None。"""
    if isinstance(keywords, str):
        keywords = [keywords]
    for el in elements:
        name = (el.get('name') or '') + ' ' + (el.get('text') or '') + ' ' + (el.get('content_desc') or '')
        name = name.replace('\n', ' ')
        if clickable_only and not el.get('clickable'):
            continue
        for kw in keywords:
            if kw in name:
                return el
    return None


def element_names(elements):
    return sorted({(el.get('name') or '').replace('\n', ' ').strip() for el in elements})


def same_screen(a, b):
    """两次快照是否可视为同一界面（元素名集合相同）。"""
    return element_names(a) == element_names(b)


BOOT_MARKERS = ['SYS//BOOT', '唤醒序列就绪', '触碰屏幕']


def is_boot_screen(elements):
    """是否停在 boot 过场 / 唤醒页（需要点击才能继续）。"""
    names = ' '.join(element_names(elements))
    return any(m in names for m in BOOT_MARKERS)


def skip_boot(serial, out_dir=None, max_wait=30.0):
    """若在 boot 过场，点击屏幕唤醒；返回是否成功离开。"""
    deadline = time.time() + max_wait
    while time.time() < deadline:
        els = scan(serial, out_dir=out_dir, name='boot_check')
        if not is_boot_screen(els):
            return True
        print('[boot] 检测到过场/唤醒页，点击唤醒')
        # 屏幕中下部（唤醒区）
        rc, out, _ = adb(serial, 'shell', 'wm', 'size')
        w, h = 780, 1688
        for line in out.splitlines():
            if ':' in line and 'x' in line:
                try:
                    w, h = [int(v) for v in line.split(':')[-1].strip().split('x')]
                except ValueError:
                    pass
        tap(serial, w // 2, int(h * 0.92))
        time.sleep(2.0)
    return False


def wait_stable(serial, timeout=8.0, interval=0.4, out_dir=None):
    """等待界面稳定：连续两次快照元素集合相同。返回最后一次元素列表。"""
    deadline = time.time() + timeout
    prev = None
    last = []
    while time.time() < deadline:
        cur = scan(serial, out_dir=out_dir, name='stable')
        if prev is not None and same_screen(prev, cur):
            return cur
        prev = cur
        last = cur
        time.sleep(interval)
    return last
