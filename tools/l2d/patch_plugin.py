#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 `flutter_live2d`（pub 锁定 1.0.2）打**本机补丁**：关掉贴图 mipmap 缩小过滤。

## 为什么（2026-10-11 iOS 真机轮实测）

宿主验收："她有点糊"。逐层排查：

1. **不是显示链路**：Flutter 文字边缘 1px、她的强边也 1px ⇒ FBO/合成没糊。
2. **不是贴图尺寸**：贴图 Lanczos 2× 上采样（2048²→4096²，`convert.py
   --tex-scale`）后高频能量只 +3% —— mipmap 链把有效细节**归一化**了：
   贴图再大，GPU 也按缩小倍数选到同一级 mip，等于采样前先预模糊一遍。
3. 插件两处把 `MIN_FILTER` 设成 mipmap 过滤：
   · `ios/Classes/Live2DWrapper.mm`（贴图创建，成功分支）
   · `ios/CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.cpp:1101`
     （**绘制时重设** —— 只改前者会让纹理不完整，采样返回黑色：
     2026-10-11 实测过一次，她变成"黑剪影"，所以两处必须一起改）
   Live2D 这种"线稿 + 平涂"素材在 1:1 附近显示时，mipmap 只会吃掉笔触；
   关掉它换来更利的线（代价：极快推镜时可能有轻微闪烁/走样，可接受）。

## ⚠️ 实测结论（2026-10-11）：**默认不要打这个补丁**

两处一起改后画面**不再是黑剪影**（只改 wrapper 会黑：绘制时被
`CubismShader_OpenGLES2.cpp:1101` 重设成 mipmap 过滤 → 纹理不完整 → 采样返回黑），
但**宿主主观验收为「变差了」**：缩小时没有 mip 链会有走样/噪点感。
⇒ **插件保持原版**（脚本可用 `--revert` 还原；本机已还原）。
留着这个脚本是为了：将来素材/显示尺寸变化（例如换 AI 放大素材、
或把她显示得更小）时，mipmap 的取舍值得再验一次，而不是从零重查。

## 做什么 / 纪律

- 只改本机 pub 缓存（`~/.pub-cache/hosted/*/flutter_live2d-1.0.2/`），
  **不进仓库、不动 pubspec 锁**（插件里的 Cubism Core 二进制归 Live2D Inc.
  授权，同模型数据的版权红线，不入库）。
- 幂等；`--revert` 从 `.orig` 备份**整文件还原**（不做反向字符串替换 ——
  第一版那么干过，把原本就是 `GL_LINEAR` 的兜底分支改错了）。
- ⚠️ `flutter pub cache repair` / 删 `~/.pub-cache` 后要重跑本脚本。

用法：
    python3 tools/l2d/patch_plugin.py            # 打补丁
    python3 tools/l2d/patch_plugin.py --revert   # 还原
    python3 tools/l2d/patch_plugin.py --check    # 只看状态
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import sys

WRAPPER = pathlib.Path("ios/Classes/Live2DWrapper.mm")
SHADER = pathlib.Path(
    "ios/CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.cpp"
)
FILES = (WRAPPER, SHADER)

OLD = "GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);"
NEW = "GL_TEXTURE_MIN_FILTER, GL_LINEAR);  // [patch_plugin.py] 关 mipmap"
MARK = "patch_plugin.py"


def candidates() -> list[pathlib.Path]:
    root = pathlib.Path.home() / ".pub-cache" / "hosted"
    out: list[pathlib.Path] = []
    if root.is_dir():
        for host in sorted(root.iterdir()):
            p = host / "flutter_live2d-1.0.2"
            if (p / WRAPPER).is_file() and (p / SHADER).is_file():
                out.append(p)
    return out


def status(path: pathlib.Path) -> str:
    texts = [(path / f).read_text("utf-8", errors="ignore") for f in FILES]
    if all(MARK in t for t in texts):
        return "已补丁"
    if any(OLD in t for t in texts):
        return "未补丁"
    return "签名不匹配（插件版本变了？）"


def apply(path: pathlib.Path, revert: bool) -> str:
    if revert:
        n = 0
        for f in FILES:
            orig = pathlib.Path(str(path / f) + ".orig")
            if orig.is_file():
                shutil.copyfile(orig, path / f)
                n += 1
        return f"已从 .orig 还原 {n} 个文件" if n else "没有备份，无需还原"
    if status(path) == "已补丁":
        return "已补丁（跳过）"
    changed = 0
    for f in FILES:
        p = path / f
        src = p.read_text("utf-8")
        if OLD not in src:
            continue
        shutil.copyfile(p, str(p) + ".orig")
        p.write_text(src.replace(OLD, NEW), "utf-8")
        changed += 1
    return f"已打补丁（{changed} 个文件，留 .orig 备份）" if changed else "未找到签名，未改"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--revert", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    ps = candidates()
    if not ps:
        print("没找到 pub 缓存里的 flutter_live2d-1.0.2 —— 先 `flutter pub get`")
        return 1
    for p in ps:
        before = status(p)
        if args.check:
            print(f"{p}\n  → {before}")
            continue
        print(f"{p}\n  → {before} ⇒ {apply(p, args.revert)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
