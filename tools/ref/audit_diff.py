import pathlib
from PIL import Image, ImageChops, ImageDraw
ROOT = pathlib.Path(r"E:\repo\system_panel\.verify")
PAIRS = [
    ("主线全景", "ref-mainv-390x844.png", "flutter-step10-mainv.png"),
    ("面板·系统", "ref-system-390x844.png", "flutter-step8-system.png"),
    ("执行", "ref-exec-390x844.png", "flutter-step4-exec.png"),
    ("派单板", "ref-plate-390x844.png", "flutter-step3-plate.png"),
]
for name, rf, ff in PAIRS:
    r = Image.open(ROOT/rf).convert("RGB")
    f = Image.open(ROOT/ff).convert("RGB").resize((390,844), Image.LANCZOS)
    d = ImageChops.difference(r, f).convert("L")
    # 放大差异、并把 >60 的部分标红，方便一眼看出结构性偏差
    d4 = d.point(lambda v: min(255, v*4)).convert("RGB")
    px = d4.load()
    for y in range(844):
        for x in range(390):
            if d.getpixel((x,y)) > 60:
                px[x,y] = (255,60,60)
    out = Image.new("RGB", (390*3+20, 844), (7,11,18))
    out.paste(r, (0,0)); out.paste(f, (400,0)); out.paste(d4, (800,0))
    out.save(ROOT/f"_audit_{name.replace('·','_')}.png")
    h = d.histogram()
    strong = sum(h[60:]); tot = 390*844
    print(f"{name:<10} 差异>60 的像素 {strong:6d} ({strong/tot*100:4.1f}%)   → _audit_{name.replace('·','_')}.png")
