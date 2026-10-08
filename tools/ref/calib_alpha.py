#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""舞台标定 —— alpha 包围盒法（T7，docs/18 §1.5.3）。

⚠️ 纪律：**只做阈值包围盒，禁止任何"量截图轮廓/找边缘"的量测**。
   旧 AVD 时代用"竖条轮廓"量身高，三次都吃到委托按钮和地面光晕的噪声
   （bot 恒为 807），把噪声当信号标出过错的 scale —— HANDOFF 有前车之鉴。

做法：对屏幕截图取**亮度/alpha 阈值**的行列包围盒（她身后是深蓝虚空
#0A0E1A，人物与环都比背景亮得多；阈值法与 alpha 阈值等价，对 RGBA 截图
自动优先用 alpha 通道），再与目标相机（大厅 s=.92，syF=.505）反解
`StageCalib.kSize / dx / dy` 的建议值。

用法：
  # 从设备直接抓（默认 127.0.0.1:16512，MuMu；截图 780x1688 → 缩到 390x844）
  python tools/ref/calib_alpha.py --device 127.0.0.1:16512

  # 或喂一张现成 PNG
  python tools/ref/calib_alpha.py --png shot.png

  # 标定前把页面切到大厅并尽量清场（无弹层）；阈值可调：
  python tools/ref/calib_alpha.py --device 127.0.0.1:16512 --thresh 40

输出：包围盒（top/bot/left/right，逻辑像素与占屏高比例）+ StageCalib 建议值。
把建议值回填 app/lib/stage/live2d_stage.dart 的 StageCalib 常数，热重载复查。
"""

from __future__ import annotations

import argparse
import io
import subprocess
import sys

# 设计基准（ENV/惯例）：MuMu wm size 780x1688 + density 320 → 逻辑 390x844
LOGICAL_W = 390.0
LOGICAL_H = 844.0

# 目标相机（大厅）：Cam.all['lobby'] = Cam(.92, 0, -.535, .5, .505)
TARGET_S = 0.92
TARGET_SYF = 0.505
TARGET_SXF = 0.50


def grab_from_device(device: str) -> bytes:
    """adb exec-out screencap -p —— PNG 字节。"""
    adb = subprocess.run(
        ["adb", "-s", device, "exec-out", "screencap", "-p"],
        capture_output=True,
        check=True,
    )
    return adb.stdout


def bbox_alpha_or_luma(png_bytes: bytes, thresh: int) -> tuple[int, int, int, int]:
    """返回 (top, bot, left, right) 逻辑像素包围盒。

    优先 alpha 通道（α > thresh）；没有 alpha（screencap 的 framebuffer 就是
    不透明的）用**对背景中位亮度的偏移**做阈值 —— 本质仍是阈值包围盒，
    不是轮廓量测。
    """
    try:
        from PIL import Image  # noqa: PLC0415
    except ImportError as e:  # pragma: no cover
        sys.exit("需要 Pillow：pip install pillow")

    img = Image.open(io.BytesIO(png_bytes))
    w, h = img.size
    sx, sy = w / LOGICAL_W, h / LOGICAL_H  # 物理→逻辑缩放

    if img.mode in ("RGBA", "LA"):
        alpha = img.getchannel("A")
        mask = alpha.point(lambda a: 255 if a > thresh else 0)
        src = "alpha"
    else:
        gray = img.convert("L")
        px = list(gray.getdata())
        # 背景中位亮度（四角取样）——虚空底色
        corners = [
            px[0], px[w - 1], px[(h - 1) * w], px[h * w - 1],
            px[(h // 2) * w],  # 顺手一个中缝样本
        ]
        base = sorted(corners)[len(corners) // 2]
        mask = gray.point(lambda v: 255 if abs(v - base) > thresh else 0)
        src = f"luma(base={base})"

    bbox = mask.getbbox()  # (l, t, r, b) 物理像素
    if bbox is None:
        sys.exit(f"阈值 {thresh} 下没找到任何前景（{src}）——调 --thresh")

    l, t, r, b = bbox
    return (
        t / sy,
        b / sy,
        l / sx,
        r / sx,
    ), src


def suggest(top: float, bot: float, left: float, right: float) -> None:
    """与目标相机反解 StageCalib 建议值。

    实测占屏高比 p = (bot - top) / LOGICAL_H；
    中心 y 比 cy = (top + bot) / 2 / LOGICAL_H。
    矩形边长 = H * TARGET_S * kSize → kSize = p / TARGET_S；
    dy = (cy - TARGET_SYF) * LOGICAL_H；dx 同理（对照 TARGET_SXF）。
    """
    span = bot - top
    cy = (top + bot) / 2.0
    cx = (left + right) / 2.0
    p = span / LOGICAL_H
    k = p / TARGET_S
    dy = (cy - TARGET_SYF) * LOGICAL_H
    dx = (cx - TARGET_SXF) * LOGICAL_W
    print("── 实测包围盒（逻辑像素）──")
    print(f"top={top:.1f} bot={bot:.1f} left={left:.1f} right={right:.1f}")
    print(f"占屏高 {p * 100:.1f}%  中心=({cx:.1f}, {cy:.1f})")
    print("── StageCalib 建议值（回填 app/lib/stage/live2d_stage.dart）──")
    print(f"static const double kSize = {k:.4f};")
    print(f"static const double dx = {dx:.1f};")
    print(f"static const double dy = {dy:.1f};")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--device", default="127.0.0.1:16512", help="adb 设备")
    ap.add_argument("--png", help="直接喂截图文件（跳过 adb）")
    ap.add_argument("--thresh", type=int, default=36, help="阈值（0-255）")
    args = ap.parse_args()

    if args.png:
        with open(args.png, "rb") as f:
            data = f.read()
    else:
        # MuMu 惯例：wm 覆盖在重启后丢，先钉回基准再截
        subprocess.run(
            ["adb", "-s", args.device, "shell", "wm", "size", "780x1688"],
            capture_output=True,
        )
        subprocess.run(
            ["adb", "-s", args.device, "shell", "wm", "density", "320"],
            capture_output=True,
        )
        data = grab_from_device(args.device)

    (top, bot, left, right), src = bbox_alpha_or_luma(data, args.thresh)
    print(f"[阈值来源：{src} · 阈值 {args.thresh}]")
    suggest(top, bot, left, right)


if __name__ == "__main__":
    main()
