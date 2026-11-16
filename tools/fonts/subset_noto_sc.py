#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NotoSansSC 可变字体子集化（安装包瘦身，2026-11-06）。

为什么要裁：原版 NotoSansSC-VF.ttf 有 3 万多个字形、17MB，是安装包里最大的单个
资源；App 的界面文案、内置台词加上用户/LLM 日常会写出的汉字，GB2312 的 6763 个
常用字基本兜得住。裁完仍是**可变字体**（保留 fvar / gvar / HVAR / avar / STAT，
wght 100–900 照常可调），OpenType 布局特性全部保留。

字符集 = 下面四块的并集（只收原字体里真有的字）：
  1. GB2312 全部字符（用 Python 自带的 gb2312 编解码逐码位枚举，不下载字表）：
     6763 个汉字 + 全角符号 / 假名 / 希腊 / 西里尔 / 制表符 / 拼音等 682 个非汉字
  2. ASCII 可见字符
  3. 常用标点与符号区块（见 EXTRA_BLOCKS）
  4. 扫 app/lib/**/*.dart 里出现过的所有字符（含 \\uXXXX / \\u{...} 转义），
     保证界面文案与内置台词 100% 覆盖

用法（在仓库根目录）：
    python3 tools/fonts/subset_noto_sc.py           # 从 tools/fonts/src 原版重新生成并校验
    python3 tools/fonts/subset_noto_sc.py --check   # 不生成，只校验现有子集（改了文案后跑）

依赖：fontTools（本机 4.25 已够用；没有就
    pip install -U fonttools -i https://mirrors.cloud.tencent.com/pypi/simple/ ）

缺字时会怎样：子集里没有的字，Flutter 会按 fontFamilyFallback → 系统字体
（iOS 苹方 / Android Noto Sans CJK）兜底显示，不会出豆腐块，只是字形略有差异。
"""
import argparse
import pathlib
import re
import sys

from fontTools import subset as ftsubset
from fontTools import version as FONTTOOLS_VERSION
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tools" / "fonts" / "src" / "NotoSansSC-VF.ttf"
OUT = ROOT / "app" / "assets" / "fonts" / "NotoSansSC-VF.ttf"
LIB = ROOT / "app" / "lib"

# 常用标点与符号区块（闭区间）。只是「候选」，原字体没有的码位会被自动忽略。
EXTRA_BLOCKS = [
    (0x00A0, 0x00FF),  # Latin-1 Supplement：· × ÷ ° ± ¥ 等
    (0x2000, 0x206F),  # General Punctuation：— – … ‘’“” ‰ ※ 等
    (0x2100, 0x214F),  # Letterlike Symbols：℃ № ™ 等
    (0x2150, 0x218F),  # Number Forms：Ⅰ–Ⅻ 等罗马数字
    (0x2190, 0x21FF),  # Arrows：← ↑ → ↓ ⇒ 等
    (0x2200, 0x22FF),  # Mathematical Operators：≈ ≠ ≤ ≥ ∞ 等
    (0x2460, 0x24FF),  # Enclosed Alphanumerics：① ⑴ ⒈ 等
    (0x2500, 0x257F),  # Box Drawing
    (0x25A0, 0x25FF),  # Geometric Shapes：■ □ ▲ △ ○ ● ◆ 等
    (0x2600, 0x26FF),  # Miscellaneous Symbols：★ ☆ 等
    (0x2700, 0x27BF),  # Dingbats：✓ ✗ 等（原字体多半没有，没有就由系统字体兜底）
    (0x3000, 0x303F),  # CJK Symbols and Punctuation：、。〈〉《》「」『』【】〜 等
    (0xFE30, 0xFE4F),  # CJK Compatibility Forms：﹏ 等
    (0xFF00, 0xFFEF),  # Halfwidth and Fullwidth Forms：全角 ！（），：；？ 等
]

# 抽查：界面里一定会出现的字（动作区固定用词 + 产品名 + 常见数字标点）
UI_SAMPLE = "宿主系统快照记录提交任务认输主线委托档案补给结算经验等级暴击毒舌靠谱，。！？…—「」【】·0123456789ABCabc"
# 抽查：GB2312 以外、原字体里有、App 代码里也没有的生僻字 —— 子集里必须缺失
RARE_SAMPLE = "龘"


def gb2312_chars():
    """逐个码位解 EUC-CN：区 0xA1–0xF7 × 位 0xA1–0xFE，解不出来的是空位。"""
    out = set()
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                out.add(bytes((hi, lo)).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return out


def is_han(ch):
    return 0x4E00 <= ord(ch) <= 0x9FFF


_ESC = re.compile(r"\\u\{([0-9a-fA-F]{1,6})\}|\\u([0-9a-fA-F]{4})")


def dart_chars():
    """app/lib 下所有 .dart 文件里出现过的字符（含 Dart 字符串里的 \\u 转义）。"""
    out = set()
    files = sorted(LIB.rglob("*.dart"))
    for p in files:
        text = p.read_text(encoding="utf-8")
        out.update(ch for ch in text if ord(ch) >= 0x20)
        for m in _ESC.finditer(text):
            cp = int(m.group(1) or m.group(2), 16)
            if cp >= 0x20:
                out.add(chr(cp))
    return out, len(files)


def build_charset():
    gb = gb2312_chars()
    ascii_ = {chr(c) for c in range(0x20, 0x7F)}
    blocks = {chr(c) for a, b in EXTRA_BLOCKS for c in range(a, b + 1)}
    code, nfiles = dart_chars()
    parts = {
        "GB2312（全部）": gb,
        "  其中汉字": {c for c in gb if is_han(c)},
        "ASCII": ascii_,
        "标点/符号区块（候选）": blocks,
        f"app/lib 扫描（{nfiles} 个 .dart）": code,
    }
    return gb | ascii_ | blocks | code, parts, code


def make_subset(unicodes):
    opts = ftsubset.Options()
    opts.layout_features = ["*"]  # 全部 OpenType 特性（palt / halt / fwid / locl / kern / vert …）
    opts.layout_scripts = ["*"]
    opts.name_IDs = ["*"]  # fvar 实例名、STAT 引用的 name 记录都要留着
    opts.name_languages = ["*"]
    opts.notdef_outline = True  # .notdef 保留轮廓，万一走不到兜底也看得出是缺字
    opts.recalc_timestamp = False  # 不改 head.modified，同输入同版本 → 同字节，可复现
    opts.ignore_missing_unicodes = True
    font = ftsubset.load_font(str(SRC), opts)
    sub = ftsubset.Subsetter(options=opts)
    sub.populate(unicodes=sorted(ord(c) for c in unicodes))
    sub.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    ftsubset.save_font(font, str(OUT), opts)
    font.close()


def var_signature(font, ch):
    """一个字的「可变字形指纹」：默认轮廓 + 默认字宽 + gvar 全部变化量。

    gvar 的变化量里含 4 个幻影点（phantom points），字宽随 wght 的变化也编码在里面，
    所以指纹一致 ⇒ 任意字重下轮廓与字宽都与原版一致（不必整份 instancer 实例化，
    那样跑原版要两分钟）。
    """
    name = font.getBestCmap()[ord(ch)]
    glyf = font["glyf"]
    coords, ends, _ = glyf[name].getCoordinates(glyf)
    deltas = [(v.axes, list(v.coordinates)) for v in font["gvar"].variations.get(name, [])]
    return list(coords), list(ends), font["hmtx"][name], deltas


def features(font, tag):
    if tag not in font:
        return set()
    return {fr.FeatureTag for fr in font[tag].table.FeatureList.FeatureRecord}


def verify(code_chars):
    """校验子集：可变轴还在、特性没丢、界面用字都在、生僻字确实被裁掉。"""
    src = TTFont(str(SRC), lazy=True)
    out = TTFont(str(OUT), lazy=True)
    ok = True

    def check(cond, msg):
        nonlocal ok
        print(("  ✔ " if cond else "  ✘ ") + msg)
        ok = ok and cond

    print("\n校验")
    for tag in ("fvar", "gvar", "HVAR", "avar", "STAT", "GSUB", "GPOS", "GDEF"):
        if tag in src:
            check(tag in out, f"表 {tag} 保留")
    axes = [(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in out["fvar"].axes]
    src_axes = [(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in src["fvar"].axes]
    check(axes == src_axes, f"fvar 轴不变：{axes}")
    check(
        len(out["fvar"].instances) == len(src["fvar"].instances),
        f"fvar 命名实例 {len(out['fvar'].instances)} 个",
    )
    for tag in ("GSUB", "GPOS"):
        lost = features(src, tag) - features(out, tag)
        check(not lost, f"{tag} 特性 {sorted(features(out, tag))}" + (f"（丢了 {sorted(lost)}）" if lost else ""))

    src_cmap = src.getBestCmap()
    out_cmap = out.getBestCmap()
    print(f"  · 字形 {src['maxp'].numGlyphs} → {out['maxp'].numGlyphs}，cmap 码位 {len(src_cmap)} → {len(out_cmap)}")

    missing_ui = [c for c in UI_SAMPLE if ord(c) not in out_cmap]
    check(not missing_ui, f"界面抽查字全在（{len(UI_SAMPLE)} 个）" + (f"，缺 {missing_ui}" if missing_ui else ""))
    if not missing_ui:
        drift = [c for c in UI_SAMPLE if var_signature(src, c) != var_signature(out, c)]
        check(not drift, "抽查字的轮廓 / 字宽 / gvar 变化量与原版逐点一致（wght 可变）" + (f"，不一致 {drift}" if drift else ""))

    # App 代码里出现、原字体也有的字，子集必须一个不少（漏了就说明脚本坏了）
    code_lost = sorted(c for c in code_chars if ord(c) in src_cmap and ord(c) not in out_cmap)
    check(not code_lost, "app/lib 用到且原字体有的字全部保留" + (f"，缺 {code_lost[:20]}" if code_lost else ""))
    # 代码里用到、但原字体本来就没有的（emoji / ✓ 之类）：只提示，运行时走系统字体
    no_glyph = sorted(c for c in code_chars if ord(c) > 0x7E and ord(c) not in src_cmap)
    if no_glyph:
        shown = " ".join(f"{c}(U+{ord(c):04X})" for c in no_glyph[:30])
        print(f"  · 代码里有、原字体本来就没有的字 {len(no_glyph)} 个（运行时由系统字体兜底）：{shown}")

    for c in RARE_SAMPLE:
        if c in code_chars:  # 哪天界面真用上了它，就该保留，这条抽查跳过
            print(f"  · 生僻字 {c} 已出现在 app/lib 里，跳过「应缺失」抽查")
            continue
        check(ord(c) in src_cmap, f"生僻字 {c}(U+{ord(c):04X}) 原字体里有")
        check(ord(c) not in out_cmap, f"生僻字 {c}(U+{ord(c):04X}) 子集里已裁掉（GB2312 外、代码里没用）")

    src.close()
    out.close()
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="只校验现有子集，不重新生成")
    args = ap.parse_args()

    if not SRC.exists():
        sys.exit(f"找不到原版字体：{SRC}")
    print(f"fontTools {FONTTOOLS_VERSION}")
    charset, parts, code = build_charset()
    for name, s in parts.items():
        print(f"  {name}: {len(s)}")
    print(f"  并集: {len(charset)}")

    if not args.check:
        make_subset(charset)
    elif not OUT.exists():
        sys.exit(f"找不到子集：{OUT}（先不带 --check 跑一次）")

    a, b = SRC.stat().st_size, OUT.stat().st_size
    print(f"\n大小 {a / 1048576:.2f} MB → {b / 1048576:.2f} MB（{b / a:.1%}）")
    if not verify(code):
        sys.exit("校验失败")
    print("\n完成。")


if __name__ == "__main__":
    main()
