#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 `flutter_live2d`（pub 锁定 1.0.2）打**本机补丁**：关掉贴图 mipmap 缩小过滤。

## 为什么（2026-10-11 iOS 真机轮实测）

宿主验收："她有点糊"。逐层排查：

1. **不是显示链路**：Flutter 文字边缘 1px、她的强边也 1px ⇒ FBO/合成没糊。
2. **不是贴图尺寸**：贴图 Lanczos 2× 上采样（2048²→4096²，`convert.py
   --tex-scale`）后高频能量只 +3% —— mipmap 链把有效细节**归一化**了：
   贴图再大，GPU 也按缩小倍数选到同一级 mip，等于采样前先预模糊一遍。
3. 插件把 `MIN_FILTER` 设成 mipmap 过滤，而且**两处**都要改：
   · 贴图创建时（iOS `ios/Classes/Live2DWrapper.mm` / Android
     `android/src/main/cpp/Live2DTextureManager.cpp`）
   · **绘制时重设**（`CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.cpp`，
     两端的 SDK 副本各一份）—— 只改前者会让纹理不完整、采样返回黑色：
     2026-10-11 实测过一次，她变成"黑剪影"，所以两处必须一起改。
   Live2D 这种"线稿 + 平涂"素材在 1:1 附近显示时，mipmap 只会吃掉笔触；
   关掉它换来更利的线（代价：极快推镜时可能有轻微闪烁/走样，可接受）。

## ⚠️ 实测结论（2026-10-11 · iOS 真机）：**默认不要打这个补丁**

两处一起改后画面**不再是黑剪影**（只改 wrapper 会黑：绘制时被
`CubismShader_OpenGLES2.cpp` 重设成 mipmap 过滤 → 纹理不完整 → 采样返回黑），
但**宿主主观验收为「变差了」**：缩小时没有 mip 链会有走样/噪点感。
⇒ **插件保持原版**（脚本可用 `--revert` 还原；本机已还原）。
留着这个脚本是为了：将来素材/显示尺寸变化（例如换 AI 放大素材、
或把她显示得更小）时，mipmap 的取舍值得再验一次，而不是从零重查。

## ▸ 2026-10-12 · Android（MuMu）复验

宿主拿"原始数据网页"对照，再次报「比较模糊」。逐层量完（证据留在
`.verify/l2d-clarity/`，结论写进 `app/STAGE-OPTIONS.md`）：

| 量的是什么 | 数 |
|---|---|
| App 两张贴图 vs 原始 PNG | **sha256 完全一致**（不是转换压图） |
| 贴图里虹膜直径 | ≈ 60~77 px（`texture_00` 2048²） |
| App 大厅里虹膜直径 | ≈ 30 px ⇒ 贴图被**缩小 ≈ 2×**采样 |
| 插件 MIN_FILTER | `GL_LINEAR_MIPMAP_LINEAR` ⇒ 缩小 2× 时选到 **mip1**（1024²） |
| 原始数据自己的采样配置 | `mipCount: 1` / `m_FilterMode: 1`（= LINEAR，**无 mip 链**） |
| 参考网页里她的大小 | App 的 **5.7×**（人脸特写 vs 全身），那边是**放大**采样 |

⇒ 「模糊」是**两件事叠起来**：① 参考页面把她放大 5.7 倍显示（那边根本没有
缩小、mip 链不参与）；② 我们的原生路径在缩小 2× 时被 mip1 预模糊。
本脚本的补丁消掉 ②，代价是缩小场景下的走样 —— **必须让宿主在真机上看过再定**。

## 做什么 / 纪律

- 只改本机 pub 缓存里的 `flutter_live2d-1.0.2/`（`PUB_CACHE` /
  `~/.pub-cache` / `%LOCALAPPDATA%/Pub/Cache` 都找一遍），
  **不进仓库、不动 pubspec 锁**（插件里的 Cubism Core 二进制归 Live2D Inc.
  授权，同模型数据的版权红线，不入库）。
- 幂等；`--revert` 从 `.orig` 备份**整文件还原**（不做反向字符串替换 ——
  第一版那么干过，把原本就是 `GL_LINEAR` 的兜底分支改错了）。
- `--target ios|android|all`：只打某一端（默认 all，缺哪端就跳哪端）。
- ⚠️ `flutter pub cache repair` / 删 pub 缓存后要重跑本脚本。

用法：
    python3 tools/l2d/patch_plugin.py                 # 打补丁（两端）
    python3 tools/l2d/patch_plugin.py --target android
    python3 tools/l2d/patch_plugin.py --revert        # 还原
    python3 tools/l2d/patch_plugin.py --check         # 只看状态
"""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import sys

IOS_FILES = (
    pathlib.Path("ios/Classes/Live2DWrapper.mm"),
    pathlib.Path("ios/CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.cpp"),
)
ANDROID_FILES = (
    pathlib.Path("android/src/main/cpp/Live2DTextureManager.cpp"),
    pathlib.Path(
        "android/src/main/cpp/CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.cpp"
    ),
)
TARGETS = {"ios": IOS_FILES, "android": ANDROID_FILES}

OLD = "GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);"
NEW = "GL_TEXTURE_MIN_FILTER, GL_LINEAR);  // [patch_plugin.py] 关 mipmap"
MARK = "patch_plugin.py"


def cache_roots() -> list[pathlib.Path]:
    """本机 pub 缓存可能有多个位置（PUB_CACHE / 老默认 / Windows 重定位）"""
    roots: list[pathlib.Path] = []
    env = os.environ.get("PUB_CACHE")
    if env:
        roots.append(pathlib.Path(env) / "hosted")
    roots.append(pathlib.Path.home() / ".pub-cache" / "hosted")
    local = os.environ.get("LOCALAPPDATA")
    if local:
        roots.append(pathlib.Path(local) / "Pub" / "Cache" / "hosted")
    return [r for r in roots if r.is_dir()]


def candidates() -> list[pathlib.Path]:
    out: list[pathlib.Path] = []
    for root in cache_roots():
        for host in sorted(root.iterdir()):
            p = host / "flutter_live2d-1.0.2"
            if any((p / f).is_file() for fs in TARGETS.values() for f in fs):
                if p not in out:
                    out.append(p)
    return out


def files_for(path: pathlib.Path, target: str) -> tuple[pathlib.Path, ...]:
    want = TARGETS.values() if target == "all" else (TARGETS[target],)
    return tuple(f for fs in want for f in fs if (path / f).is_file())


def status(path: pathlib.Path, target: str) -> str:
    files = files_for(path, target)
    if not files:
        return f"没有 {target} 的文件"
    texts = [(path / f).read_text("utf-8", errors="ignore") for f in files]
    done = sum(1 for t in texts if MARK in t)
    left = sum(1 for t in texts if OLD in t)
    if done == len(files):
        return "已补丁"
    if left:
        return f"未补丁（{left}/{len(files)} 处仍是 mipmap）"
    return "签名不匹配（插件版本变了？）"


def apply(path: pathlib.Path, target: str, revert: bool) -> str:
    files = files_for(path, target)
    if revert:
        n = 0
        for f in files:
            orig = pathlib.Path(str(path / f) + ".orig")
            if orig.is_file():
                shutil.copyfile(orig, path / f)
                n += 1
        return f"已从 .orig 还原 {n} 个文件" if n else "没有备份，无需还原"
    changed = 0
    for f in files:
        p = path / f
        src = p.read_text("utf-8")
        if OLD not in src:
            continue
        if not pathlib.Path(str(p) + ".orig").is_file():
            shutil.copyfile(p, str(p) + ".orig")
        p.write_text(src.replace(OLD, NEW), "utf-8")
        changed += 1
    return f"已打补丁（{changed} 个文件，留 .orig 备份）" if changed else "未找到签名，未改"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--revert", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--target", choices=["ios", "android", "all"], default="all")
    args = ap.parse_args()

    ps = candidates()
    if not ps:
        print("没找到 pub 缓存里的 flutter_live2d-1.0.2 —— 先 `flutter pub get`")
        print("（找过的位置：" + "、".join(str(r) for r in cache_roots()) + "）")
        return 1
    for p in ps:
        before = status(p, args.target)
        if args.check:
            print(f"{p}\n  → [{args.target}] {before}")
            continue
        # ⚠️ 控制台编码可能是 GBK（Windows），打印只用 ASCII 箭头
        after = apply(p, args.target, args.revert)
        print(f"{p}\n  -> [{args.target}] {before} => {after}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
