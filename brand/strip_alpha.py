#!/usr/bin/env python3
"""iOS 图标去 alpha 通道。

App Store 的 1024 营销图标不接受透明通道（Xcode 会报 "Invalid Image …
contains an alpha channel"）。我们的底板本来就画满整格，所以这里只是把
RGBA 压成 RGB，像素值一个不动。

用法：python3 brand/strip_alpha.py <AppIcon.appiconset 目录>
"""
import sys
from pathlib import Path

from PIL import Image


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not root.is_dir():
        print(f"[strip_alpha] 不是目录：{root}", file=sys.stderr)
        return 2
    n = 0
    for p in sorted(root.glob("*.png")):
        im = Image.open(p)
        if im.mode in ("RGB",):
            continue
        if im.mode == "P":
            im = im.convert("RGBA")
        if im.mode == "RGBA":
            bg = Image.new("RGB", im.size, (3, 6, 14))  # 虚空蓝黑兜底
            bg.paste(im, mask=im.split()[-1])
            out = bg
        else:
            out = im.convert("RGB")
        out.save(p, "PNG", optimize=True)
        n += 1
    print(f"[strip_alpha] 已去 alpha：{n} 个（{root}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
