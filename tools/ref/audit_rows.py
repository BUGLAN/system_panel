import pathlib
from PIL import Image, ImageChops
ROOT = pathlib.Path(r"E:\repo\system_panel\.verify")
PAIRS = [
    ("面板·系统", "ref-system-390x844.png", "flutter-step8-system.png"),
    ("主线全景", "ref-mainv-390x844.png", "flutter-step10-mainv.png"),
    ("执行", "ref-exec-390x844.png", "flutter-step4-exec.png"),
]
for name, rf, ff in PAIRS:
    r = Image.open(ROOT/rf).convert("RGB")
    f = Image.open(ROOT/ff).convert("RGB").resize((390,844), Image.LANCZOS)
    d = ImageChops.difference(r, f).convert("L")
    rows = []
    for y in range(844):
        s = 0
        for x in range(390):
            v = d.getpixel((x,y))
            if v > 60: s += 1
        rows.append(s)
    # 找出连续的高差异行段（结构性差异往往成段出现）
    segs, cur = [], None
    for y, v in enumerate(rows):
        if v >= 40:
            cur = [y, y] if cur is None else [cur[0], y]
        else:
            if cur and cur[1]-cur[0] >= 2: segs.append(tuple(cur))
            cur = None
    if cur and cur[1]-cur[0] >= 2: segs.append(tuple(cur))
    segs.sort(key=lambda s: -(s[1]-s[0]))
    print(f"\n{name}: 高差异行段 TOP5（原型 vs 实机）")
    for a,b in segs[:5]:
        tot = sum(rows[a:b+1])
        print(f"  y {a:3d}~{b:3d}（高 {b-a+1:3d}px） 差异像素 {tot:5d}")
