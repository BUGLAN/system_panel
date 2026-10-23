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

## ▸ 2026-10-24 · iOS 真机三点实测（先看这条再看下面的历史结论）

把三种口径各构建一次、装 iPhone 15 Pro Max、同大厅机位截帧量（全部数字见
`docs/46` §3.7 / §3.8，物证 `.verify/l2d-clarity-ios/`）：

| 口径 | 中频 | 高频 | 结论 |
|---|---|---|---|
| 原版 `LINEAR_MIPMAP_LINEAR` | 基准 | 基准 | 最干净、最软 |
| `nearest` | 大厅 +6% | ×1.4 | 大厅略利；**派单特写 −8.6%（LOD 0.53 被取整到 mip1）** |
| `linear`（本脚本默认） | **+12.5~270%** | **×2.8~3.3** | **肉眼明显更利，但发丝/腮红/缎带有点状噪光** |

⚠️ 关键前提（这一轮才量出来）：iOS lobby 的 mip LOD ≈ **1.07~1.22**，也就是**贴图相对屏幕
已经是 1:1**（虹膜 96×112 texel 摊到 34~41 px）—— 所以补丁换来的**不是"更多细节"，
是"更利的走样"**。Android（LOD 1.37~1.95）收益才大。
⇒ 想"只赚不赔"要走 LOD bias −0.5（仿真 +7.9%/+9.4%，本轮没落地：GLES2 没有
`GL_TEXTURE_MAX_LOD` token）。

## ⚠️ 历史结论（2026-10-11 · iOS 真机）：**当时的默认是"不要打"**

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
MARK = "[patch_plugin.py]"

# 两种"变锐"口径（2026-10-24 iOS 真机三点实测后加的）：
#   linear  —— 彻底关 mip 链。最锐，但缩小倍数 ≈2.4× 时是"欠采样"，
#              发丝/睫毛会出现**点状噪光**（宿主 2026-10-11 判"变差了"的那个）。
#   nearest —— 保留 mip 链，只把"跨级三线性混合"换成"取最近一级"。
#              大厅 +6%、无点状噪光；**但派单特写（LOD 0.53）会被取整到 mip1，中频 −8.6%**，
#              别当"无代价"选项用。
#   （还有一条 `GL_TEXTURE_MAX_LOD=1.0` 的"只赚不赔"口径：只把 mip 上限压到 mip1，
#    大厅 LOD 1.2→1.0 变锐、派单 LOD 0.53 完全不受影响。**但 GLES2 头里没有这个 token**
#    （desktop/GLES3 才有），用 0x813B 硬写又有可能吃到 GL_INVALID_ENUM，2026-10-24 本轮
#    放弃；要试就在 `SetupTexture` 里加 `glTexParameterf(GL_TEXTURE_2D, 0x813B, 1.0f)`
#    并用 Xcode 控制台确认没有 `GL error 0x500`。）
VARIANTS = {
    "linear": "GL_TEXTURE_MIN_FILTER, GL_LINEAR);  // [patch_plugin.py] 关 mipmap",
    "nearest": "GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST);  // [patch_plugin.py] mip 近邻",
}

# ── LOD bias（--bias）：不换过滤模式，只让采样器"取更细一级" ──────────────────
# 与超采样（Live2DStage.kViewFamilies）**可叠加**：超采样把像素密度拉高，
# bias 再把贴图采样推细，多出来的混叠被超采样平均掉 —— 这是"更清晰但不脏"的组合。
# GLSL ES 1.00 的 texture2D 第三参数 bias 各驱动支持不一，**打之前先看画面**：
# 编译失败 = 模型整个不画（不是变糊），一测就知道。
SHADER_DIR = pathlib.Path("ios/CubismFramework/Rendering/OpenGL/Shaders/StandardES")
BIAS_OLD = "texture2D(s_texture0, v_texCoord)"
BIAS_NEW = "texture2D(s_texture0, v_texCoord, {bias})  // [patch_plugin.py] LOD bias"
BIAS_MARK = "[patch_plugin.py] LOD bias"


def shader_files(path: pathlib.Path) -> tuple[pathlib.Path, ...]:
    """所有采样模型贴图（s_texture0）的 frag —— 蒙版/混合贴图不碰"""
    d = path / SHADER_DIR
    if not d.is_dir():
        return ()
    return tuple(
        p for p in sorted(d.glob("*.frag"))
        if "s_texture0, v_texCoord" in p.read_text("utf-8", errors="ignore")
    )


def apply_bias(path: pathlib.Path, bias: float) -> str:
    files = shader_files(path)
    if not files:
        return f"没有 {SHADER_DIR}/*.frag"
    new = BIAS_NEW.format(bias=bias)
    n = 0
    for p in files:
        backup = pathlib.Path(str(p) + ".orig")
        src = backup.read_text("utf-8") if backup.is_file() else p.read_text("utf-8")
        if BIAS_OLD not in src:
            continue
        if not backup.is_file():
            shutil.copyfile(p, backup)
        p.write_text(src.replace(BIAS_OLD, new), "utf-8")
        n += 1
    return f"已加 LOD bias {bias}（{n} 个 frag）"


def bias_status(path: pathlib.Path) -> str:
    files = shader_files(path)
    if not files:
        return "无 frag"
    on = sum(1 for p in files if BIAS_MARK in p.read_text("utf-8", errors="ignore"))
    return f"LOD bias {on}/{len(files)} 个 frag 已加" if on else "LOD bias 未加"


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


def _variant_of(text: str) -> str | None:
    for name, new in VARIANTS.items():
        if new in text:
            return name
    return None


def status(path: pathlib.Path, target: str) -> str:
    files = files_for(path, target)
    if not files:
        return f"没有 {target} 的文件"
    texts = [(path / f).read_text("utf-8", errors="ignore") for f in files]
    done = [_variant_of(t) for t in texts]
    left = sum(1 for t in texts if OLD in t)
    if all(done):
        kinds = sorted({d for d in done if d})
        return "已补丁（" + "、".join(kinds) + "）"
    if left:
        marked = sum(1 for d in done if d)
        if marked:
            return f"部分补丁（{marked}/{len(files)} 已打，{left} 处仍是 mipmap）"
        return f"未补丁（{left}/{len(files)} 处仍是 mipmap）"
    return "签名不匹配（插件版本变了？）"


def revert_all(path: pathlib.Path, target: str) -> str:
    """整文件还原：过滤（.mm/.cpp）+ frag（LOD bias）都从 .orig 拷回"""
    files = list(files_for(path, target)) + list(shader_files(path))
    n = 0
    for f in files:
        orig = pathlib.Path(str(f) + ".orig") if f.is_absolute() else pathlib.Path(str(path / f) + ".orig")
        if orig.is_file():
            shutil.copyfile(orig, f if f.is_absolute() else path / f)
            n += 1
    return f"已从 .orig 还原 {n} 个文件" if n else "没有备份，无需还原"


def apply(path: pathlib.Path, target: str, revert: bool, variant: str = "linear") -> str:
    files = files_for(path, target)
    if revert:
        return revert_all(path, target)
    new = VARIANTS[variant]
    changed = 0
    for f in files:
        p = path / f
        backup = pathlib.Path(str(p) + ".orig")
        # 基准文本一律取 .orig（原版）—— 这样 linear ↔ nearest 可以来回切，
        # 不会因为"上一版已经是补丁"而找不到签名。
        src = backup.read_text("utf-8") if backup.is_file() else p.read_text("utf-8")
        if OLD not in src:
            continue
        if not backup.is_file():
            shutil.copyfile(p, str(backup))
        p.write_text(src.replace(OLD, new), "utf-8")
        changed += 1
    return f"已打补丁 [{variant}]（{changed} 个文件，留 .orig 备份）" if changed else "未找到签名，未改"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--revert", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--target", choices=["ios", "android", "all"], default="all")
    ap.add_argument(
        "--bias", type=float, default=None,
        help="给模型贴图采样加 LOD bias（负数=更细/更锐，例如 -0.5）。与超采样可叠加；"
             "GLSL ES 1.00 支持不一，打完必须看真机画面",
    )
    ap.add_argument(
        "--variant", choices=["off"] + sorted(VARIANTS), default="linear",
        help=(
            "linear=彻底关 mipmap（最锐，但发丝/腮红有点状噪光）；"
            "nearest=保留 mip 链只取最近一级（大厅 +6%，但派单特写 LOD 0.53 会被取整到 mip1 → −8.6%，慎用）"
        ),
    )
    args = ap.parse_args()

    ps = candidates()
    if not ps:
        print("没找到 pub 缓存里的 flutter_live2d-1.0.2 —— 先 `flutter pub get`")
        print("（找过的位置：" + "、".join(str(r) for r in cache_roots()) + "）")
        return 1
    for p in ps:
        before = status(p, args.target)
        bias = bias_status(p)
        if args.check:
            print(f"{p}\n  → [{args.target}] {before} · {bias}")
            continue
        # ⚠️ 控制台编码可能是 GBK（Windows），打印只用 ASCII 箭头
        if args.revert:
            after = apply(p, args.target, True, args.variant)
            print(f"{p}\n  -> [{args.target}] {before} => {after}")
            continue
        parts = []
        if args.bias is not None:
            parts.append(apply_bias(p, args.bias))
        if args.variant != "off":
            parts.append(apply(p, args.target, False, args.variant))
        print(f"{p}\n  -> [{args.target}] {before} => " + "；".join(parts or ["未改"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
