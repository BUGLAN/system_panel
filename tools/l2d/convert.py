#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 sakiko 的 Unity prefab 转成**标准 Live2D 文件**（model3 / motion3 / exp3 / physics3）。

## 为什么可行（这是查过数据得出的，不是猜）

`live2d/sakiko/models/adv_..._01.json` 是一个 Unity 工程序列化：
`.moc3`（标准）+ 2 张贴图（标准）+ 一个 7.4MB 的 prefab。
prefab 里 766 个节点带这些组件：

| 组件 | 数量 | 里面是什么 |
|---|---|---|
| `CubismParameter` / `CubismPart` / `CubismDrawable` | 210 / 160 / 389 | 参数、部件、网格 |
| `CubismExpressionData` | 28 | **表情**：`{Type, FadeInTime, FadeOutTime, Parameters:[{Id,Value,Blend}]}` |
| （动作） | 63 | **动作**：`{MotionName, MotionLength, FadeInTime, FadeOutTime, ParameterIds, ParameterCurves:[{m_Curve:[{time,value,inSlope,outSlope}]}], ParameterFadeInTimes, ParameterFadeOutTimes}` |
| `CubismPhysicsController` | 1 | **物理**：`_rig.SubRigs[{Name, Input, Output, Particles, Normalization}]` + `Gravity/Wind/Fps` |

也就是说：**表情的字段与 `exp3.json` 几乎同名；动作是 Cubism 的 `CubismFadeMotionData`
（摊平的动作，参数 ID 可读）；物理与 `physics3.json` 字段一一对应。**
所以这不是"逆向工程二进制"，是**换一层壳 + 一个标准插值转换**。

## 关键换算：Unity 的 Hermite → Live2D 的贝塞尔段

`motion3.json` 的 `Segments` 是一个扁平数组：
第一个数是**首段类型**（0 线性 / 1 贝塞尔 / 2 阶跃），随后每段追加点；
**类型相同时不重复写类型**。贝塞尔每段贡献 `(c1, c2, 终点)` 6 个数。

Unity 的 `inSlope` / `outSlope` 是 Hermite 切线，转贝塞尔控制点：

    c1 = (t0 + dt/3, v0 + outSlope(t0) * dt/3)
    c2 = (t1 - dt/3, v1 - inSlope(t1)  * dt/3)

⚠️ `--slope-scale` 就是那个 `1/3`。Unity 各版本对 tangent 的缩放约定不完全一致，
   所以它是参数、不是写死的 —— 对不上的症状是"动作幅度明显偏大/偏小"。

## 输出

    prototype/opus-v2-dir/live2d/sakiko/std/
      sakiko.model3.json · sakiko.moc3 · sakiko.physics3.json
      textures/texture_00.png · texture_01.png
      motions/*.motion3.json （63） · expressions/*.exp3.json （28）

（该目录在 `.gitignore` 的 `prototype/*/live2d/` 之下 —— 模型版权红线，不入库。）
"""
import argparse
import gzip
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "prototype" / "opus-v2-dir" / "live2d" / "sakiko"
if not SRC.exists():
    # Mac 轮（2026-10-11）：原型目录不带模型数据（版权不入库），原始 prefab
    # 全套在本机 sakiko_orig（已验证：manifest + 766 节点 + moc3.gz + 双贴图）。
    SRC = ROOT / "app" / "assets" / "live2d" / "sakiko_orig"
# ⚠️ 默认直接写进 app 的 assets —— `flutter_live2d` 要求模型目录在
#    `pubspec.yaml` 的 `flutter.assets` 里声明。该目录在 `.gitignore` 之下，
#    不会入库（模型版权红线）。
OUT = ROOT / "app" / "assets" / "live2d" / "sakiko"

# Unity 的 CubismPhysicsSourceComponent：0=X, 1=Y, 2=Angle
PHYS_AXIS = {0: "X", 1: "Y", 2: "Angle"}
# exp3.json 的 Blend 枚举：0=Add, 1=Multiply, 2=Overwrite（Unity 侧同序）
BLEND = {0: "Add", 1: "Multiply", 2: "Overwrite"}


def load_prefab():
    """把 manifest 指向的 prefab 三段拼起来读"""
    manifest = json.loads(next((SRC / "models").glob("*.json")).read_text("utf-8"))
    parts = manifest["files"][next(k for k in manifest["files"] if k.endswith(".prefab.json"))]["parts"]
    nodes = None
    for key, rel, _size, _stored in parts:
        if key != "nodes":
            continue
        nodes = json.loads(gzip.decompress((SRC / rel).read_bytes()))
    if nodes is None:
        raise SystemExit("prefab 里没找到 nodes")
    return manifest, nodes


def walk(o, depth=0):
    """深度优先遍历出所有 dict"""
    if depth > 16:
        return
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v, depth + 1)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v, depth + 1)


def collect(nodes):
    """把 prefab 里几类东西分出来。

    ⚠️ 动作与表情**不是**组件的顶层字段，而是嵌在组件内部的（Unity 把资产
       序列化成嵌套对象），所以这里必须**深度遍历每个组件**再判定 ——
       第一版只在顶层找，结果动作 0 / 表情 0。
    """
    motions, exprs, params, parts, drawables, phys = [], [], [], [], [], None
    eyeblink, lipsync = [], []
    seen = set()

    def add(bucket, obj):
        if id(obj) in seen:
            return
        seen.add(id(obj))
        bucket.append(obj)

    for n in nodes:
        # ⚠️ `CubismParameter` / `CubismEyeBlinkParameter` / `CubismMouthParameter`
        #    的 `m_Name` 都是空的 —— **参数 ID 就是它所在节点的名字**。
        node_name = str(n.get("name") or "")
        for c in (n.get("components") or []):
            cl = str(c.get("class"))
            if cl == "CubismParameter":
                params.append(c)
            elif cl == "CubismPart":
                parts.append(c)
            elif cl == "CubismDrawable":
                drawables.append(c)
            elif cl == "CubismPhysicsController":
                phys = c.get("_rig")
            elif cl == "CubismEyeBlinkParameter":
                eyeblink.append({"m_Name": node_name})
            elif cl == "CubismMouthParameter":
                lipsync.append({"m_Name": node_name})
            # 嵌套资产：动作（CubismFadeMotionData）与表情（CubismExpressionData）
            for o in walk(c):
                if "ParameterIds" in o and "ParameterCurves" in o:
                    add(motions, o)
                elif o.get("asset") == "CubismExpressionData":
                    add(exprs, o)
    return motions, exprs, params, parts, drawables, phys, eyeblink, lipsync


def hermite_to_bezier_segments(curve, slope_scale):
    """Unity 的关键帧 → Live2D 的 Segments（全贝塞尔，类型 1 只写一次）"""
    ks = curve
    if not ks:
        return []
    seg = [1, ks[0]["time"], ks[0]["value"]]
    for i in range(len(ks) - 1):
        a, b = ks[i], ks[i + 1]
        dt = b["time"] - a["time"]
        if dt <= 0:
            dt = 1e-6
        c1t = a["time"] + dt / 3
        c1v = a["value"] + a.get("outSlope", 0.0) * dt * slope_scale
        c2t = b["time"] - dt / 3
        c2v = b["value"] - b.get("inSlope", 0.0) * dt * slope_scale
        seg += [c1t, c1v, c2t, c2v, b["time"], b["value"]]
    return seg


def asset_name(raw: str) -> str:
    """Unity 侧的资产名常常是**全路径**：
    `Assets/AddressableResources/…/common/motions/mtn_sad01_C.motion3.json`
    → 取 basename 再去掉后缀。"""
    base = pathlib.PurePosixPath(str(raw).replace("\\", "/")).name
    # 反复剥后缀：`x.motion3.json` → `x`（一次只剥一层会把 `.motion3.json`
    # 拆成 `.motion3` + `.json`，结果拼出 `x.motion3.motion3.json`）
    for _ in range(4):
        stripped = re.sub(r"\.(motion3\.json|exp3\.json|json|fade|motion3|exp3)$", "", base)
        if stripped == base:
            break
        base = stripped
    return base or "unnamed"


def write_motions(motions, slope_scale, fps):
    d = OUT / "motions"
    d.mkdir(parents=True, exist_ok=True)
    names = []
    for m in motions:
        name = asset_name(m.get("MotionName") or m.get("m_Name") or "motion")
        ids = m["ParameterIds"]
        curves = m["ParameterCurves"]
        fin = m.get("ParameterFadeInTimes") or []
        fout = m.get("ParameterFadeOutTimes") or []
        dur = float(m.get("MotionLength") or 0)
        out_curves = []
        total_seg = total_pt = 0
        for i, pid in enumerate(ids):
            if i >= len(curves):
                break
            seg = hermite_to_bezier_segments(curves[i].get("m_Curve") or [], slope_scale)
            if not seg:
                continue
            c = {"Target": "Parameter", "Id": pid, "Segments": seg}
            if i < len(fin):
                c["FadeInTime"] = fin[i]
            if i < len(fout):
                c["FadeOutTime"] = fout[i]
            out_curves.append(c)
            total_seg += (len(seg) - 3) // 6
            total_pt += 1 + (len(seg) - 3) // 6
        doc = {
            "Version": 3,
            "Meta": {
                "Duration": round(dur, 6),
                "Loop": bool(m.get("IsLoop", False)),
                "AreBeziersRestricted": True,
                "FadeInTime": m.get("FadeInTime", 1.0),
                "FadeOutTime": m.get("FadeOutTime", 1.0),
                "CurveCount": len(out_curves),
                "TotalSegmentCount": total_seg,
                "TotalPointCount": total_pt,
                "UserDataCount": 0,
                "TotalUserDataSize": 0,
                "Fps": fps,
            },
            "Curves": out_curves,
        }
        (d / f"{name}.motion3.json").write_text(
            json.dumps(doc, ensure_ascii=False, separators=(",", ":")), "utf-8"
        )
        names.append(name)
    return names


def write_expressions(exprs):
    d = OUT / "expressions"
    d.mkdir(parents=True, exist_ok=True)
    names = []
    # ⚠️ **按名字排序**再写。prefab 里表情的顺序是随机的（导出顺序），
    #    `model3.json` 的 `Expressions` 数组顺序 = 插件 `setExpression(index)`
    #    的下标，所以顺序必须确定、可读 —— 否则调用方没法按名字查下标。
    for e in sorted(exprs, key=lambda x: str(x.get("m_Name") or x.get("name") or "")):
        raw = e.get("m_Name") or e.get("name") or "exp"
        name = asset_name(raw)
        ps = []
        for p in e.get("Parameters") or []:
            ps.append(
                {
                    "Id": p["Id"],
                    "Value": p["Value"],
                    "Blend": BLEND.get(int(p.get("Blend", 0)), "Add"),
                }
            )
        doc = {
            "Version": 3,
            "Type": "Live2D Expression",
            "FadeInTime": e.get("FadeInTime", 0.5),
            "FadeOutTime": e.get("FadeOutTime", 0.5),
            "Parameters": ps,
        }
        (d / f"{name}.exp3.json").write_text(
            json.dumps(doc, ensure_ascii=False, separators=(",", ":")), "utf-8"
        )
        names.append(name)
    return names


# ── 系统合成表情（2026-10-11 · iOS 真机表演补完，STAGE-OPTIONS 有完整决策）──
#
# 为什么需要：插件 wrapper 的 `SetParam` 走 method channel，下一帧就被
# `LoadParameters→motion→SaveParameters` 循环覆写（单帧失效）；而**表情在管线里
# 于 eyeblink 之后应用**（Update: motion → drag → eyeblink → expression →
# physics），Blend=Overwrite 可持续覆写眼部/头部参数 —— 是原型 `faceT`
# 脸层的原生等价物。
#
# 参数值全部对照原型 stage.js：FACES.sleep（L39: lid 0 / ay -16 / az 2 /
# cheek .1）、look('down')（L475: tx -.25 / ty -.75）、wake() 的眼皮颤两下
# （flows.js L80-84: lid .35 → 140ms → .05 → 120ms）。
# FadeIn 刻意压小：默认 0.5s 会把 140/120ms 的颤动拍子糊掉。
SYS_EXPRESSIONS = {
    "exp_sys_sleep": {
        "FadeInTime": 0.5,
        "Parameters": [
            {"Id": "ParamEyeLOpen", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamEyeROpen", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamAngleY", "Value": -16.0, "Blend": "Overwrite"},
            {"Id": "ParamAngleZ", "Value": 2.0, "Blend": "Overwrite"},
            {"Id": "ParamEyeBallX", "Value": -0.25, "Blend": "Overwrite"},
            {"Id": "ParamEyeBallY", "Value": -0.6, "Blend": "Overwrite"},
            {"Id": "ParamCheek", "Value": 0.1, "Blend": "Add"},
        ],
    },
    "exp_sys_wake": {
        "FadeInTime": 0.25,
        "Parameters": [
            {"Id": "ParamEyeLOpen", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamEyeROpen", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamAngleY", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamAngleZ", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamEyeBallX", "Value": 0.0, "Blend": "Overwrite"},
            {"Id": "ParamEyeBallY", "Value": 0.0, "Blend": "Overwrite"},
        ],
    },
    "exp_sys_lid35": {
        "FadeInTime": 0.06,
        "Parameters": [
            {"Id": "ParamEyeLOpen", "Value": 0.35, "Blend": "Overwrite"},
            {"Id": "ParamEyeROpen", "Value": 0.35, "Blend": "Overwrite"},
        ],
    },
    "exp_sys_lid05": {
        "FadeInTime": 0.06,
        "Parameters": [
            {"Id": "ParamEyeLOpen", "Value": 0.05, "Blend": "Overwrite"},
            {"Id": "ParamEyeROpen", "Value": 0.05, "Blend": "Overwrite"},
        ],
    },
}


def write_sys_expressions():
    """把上面 4 个合成表情写盘并返回名字表（追加在 28 个原版之后，字母序由
    调用方统一排序保证 `setExpression(index)` 下标与 Dart 名表一致）。"""
    d = OUT / "expressions"
    d.mkdir(parents=True, exist_ok=True)
    for name, spec in SYS_EXPRESSIONS.items():
        doc = {
            "Version": 3,
            "Type": "Live2D Expression",
            "FadeInTime": spec["FadeInTime"],
            # ⚠️ 淡出必须**短**：睁眼编排是 .35→(140ms)→.05→(120ms)→睁开，
            # 0.25s 的淡出会把这两下颤动整个糊掉（实机肉眼看不出来）。
            # 0.05 ≈ 一帧，切换即生效 —— 等价原型 faceT 直接写参数的手感。
            "FadeOutTime": 0.05,
            "Parameters": spec["Parameters"],
        }
        (d / f"{name}.exp3.json").write_text(
            json.dumps(doc, ensure_ascii=False, separators=(",", ":")), "utf-8"
        )
    return list(SYS_EXPRESSIONS)


def write_physics(rig):
    """`_rig` → physics3.json（字段一一对应）"""
    if not rig:
        return False
    settings = []
    dictionary = []
    n_in = n_out = n_vert = 0
    for i, sr in enumerate(rig.get("SubRigs") or []):
        sid = f"PhysicsSetting{i + 1}"
        dictionary.append({"Id": sid, "Name": sr.get("Name") or sid})
        ins = []
        for x in sr.get("Input") or []:
            ins.append(
                {
                    "Source": {"Target": "Parameter", "Id": x.get("SourceId")},
                    "Weight": x.get("Weight", 100.0),
                    "Type": PHYS_AXIS.get(int(x.get("SourceComponent", 0)), "X"),
                    "Reflect": bool(x.get("IsInverted", 0)),
                }
            )
        outs = []
        for x in sr.get("Output") or []:
            sc = x.get("AngleScale")
            if sc in (None, 0):
                sc = (x.get("TranslationScale") or {}).get("x") or 1.0
            outs.append(
                {
                    "Destination": {"Target": "Parameter", "Id": x.get("DestinationId")},
                    "VertexIndex": int(x.get("ParticleIndex", 1)),
                    "Scale": sc,
                    "Weight": x.get("Weight", 100.0),
                    "Type": PHYS_AXIS.get(int(x.get("SourceComponent", 0)), "Angle"),
                    "Reflect": bool(x.get("IsInverted", 0)),
                }
            )
        verts = []
        for p in sr.get("Particles") or []:
            pos = p.get("Position") or {"x": 0.0, "y": 0.0}
            verts.append(
                {
                    "Position": {"X": pos.get("x", 0.0), "Y": pos.get("y", 0.0)},
                    "Mobility": p.get("Mobility", 1.0),
                    "Delay": p.get("Delay", 1.0),
                    "Acceleration": p.get("Acceleration", 1.0),
                    "Radius": p.get("Radius", 0.0),
                }
            )
        norm = sr.get("Normalization") or {}
        # Unity 侧归一化字段名与 physics3 不完全同名，逐项兜底
        def nrm(src, dflt_min=-10.0, dflt_max=10.0, dflt_def=0.0):
            if not src:
                src = {}
            return {
                "Minimum": src.get("Minimum", dflt_min),
                "Maximum": src.get("Maximum", dflt_max),
                "Default": src.get("Default", dflt_def),
                "MinimumDefault": src.get("MinimumDefault", dflt_min),
                "MaximumDefault": src.get("MaximumDefault", dflt_max),
            }

        settings.append(
            {
                "Id": sid,
                "Input": ins,
                "Output": outs,
                "Vertices": verts,
                "Normalization": {
                    "Position": nrm(norm.get("Position")),
                    "Angle": nrm(norm.get("Angle")),
                },
            }
        )
        n_in += len(ins)
        n_out += len(outs)
        n_vert += len(verts)
    g = rig.get("Gravity") or {"x": 0.0, "y": -1.0}
    w = rig.get("Wind") or {"x": 0.0, "y": 0.0}
    doc = {
        "Version": 3,
        "Meta": {
            "PhysicsSettingCount": len(settings),
            "TotalInputCount": n_in,
            "TotalOutputCount": n_out,
            "VertexCount": n_vert,
            "Fps": rig.get("Fps", 30.0),
            "EffectiveForces": {
                "Gravity": {"X": g.get("x", 0.0), "Y": g.get("y", -1.0)},
                "Wind": {"X": w.get("x", 0.0), "Y": w.get("y", 0.0)},
            },
            "PhysicsDictionary": dictionary,
        },
        "PhysicsSettings": settings,
    }
    (OUT / "sakiko.physics3.json").write_text(
        json.dumps(doc, ensure_ascii=False, separators=(",", ":")), "utf-8"
    )
    return True


def write_assets(manifest, tex_scale=1):
    """moc3 解压 + 贴图拷出来（`tex_scale>1` 时用 Lanczos 上采样贴图）"""
    files = manifest["files"]
    for key, meta in files.items():
        rel = meta.get("asset")
        if not rel:
            continue
        src = SRC / rel
        if key.endswith(".moc3"):
            (OUT / "sakiko.moc3").write_bytes(gzip.decompress(src.read_bytes()))
        elif key.startswith("textures/"):
            name = key.split("/", 1)[1].split("-")[0] + ".png"  # texture_00-f765bdff.png → texture_00.png
            (OUT / "textures").mkdir(parents=True, exist_ok=True)
            dst = OUT / "textures" / name
            if tex_scale <= 1:
                shutil.copyfile(src, dst)
                continue
            # ⚠️ 2026-10-11 iOS 真机「她有点糊」的修法：
            #    贴图是 2048²，而真机上她按「大厅 92% 屏高」渲染 ≈ 2571 物理像素高。
            #    实测贴图里两眼间距 71px、屏幕上 111px ⇒ **放大 1.56×** 采样，边缘发虚。
            #    先用 Lanczos 上采样（2 的幂尺寸）再交给 GPU：渲染变成 0.78× 缩小
            #    采样，比 GPU 双线性放大清晰一档（Live2D 高 DPI 常规做法）。
            #    ⚠️ 放大后必须仍是 **2 的幂**：ES2 里 NPOT 纹理不能带 mipmap，而插件
            #       会 glGenerateMipmap（NPOT + mipmap 在 ES2 下会让纹理不完整）。
            from PIL import Image  # noqa: PLC0415

            im = Image.open(src).convert("RGBA")
            w, h = im.size
            nw, nh = int(w * tex_scale), int(h * tex_scale)
            if (nw & (nw - 1)) or (nh & (nh - 1)):
                raise SystemExit(
                    f"贴图放大后必须是 2 的幂（{w}x{h} × {tex_scale} = {nw}x{nh}）"
                )
            im.resize((nw, nh), Image.LANCZOS).save(dst, optimize=True)
            print(f"  贴图 {name}: {w}x{h} → {nw}x{nh}（Lanczos ×{tex_scale}）")


def write_model3(manifest, motions, exprs, has_phys, eyeblink, lipsync):
    canvas = manifest["model"]["canvas"]
    refs = {
        "Moc": "sakiko.moc3",
        "Textures": ["textures/texture_00.png", "textures/texture_01.png"],
    }
    if has_phys:
        refs["Physics"] = "sakiko.physics3.json"
    # 动作按前缀分组（idle / smile / cry …），组名取 `mtn_<组>..` 里的组
    groups = {}
    for name in motions:
        body = name[4:] if name.startswith("mtn_") else name
        g = re.sub(r"\d.*$", "", body) or "misc"
        groups.setdefault(g, []).append({"File": f"motions/{name}.motion3.json"})
    refs["Motions"] = groups
    # ⚠️ `"Idle"` 别名组（2026-10-11 · iOS 真机表演补完）：
    # flutter_live2d 的 iOS wrapper 把待机兜底组名与「循环播放」都写死在
    # 字面 `"Idle"` 上（Hiyori 约定，sakiko 全小写对不上 → 播一遍就冻结，
    # STAGE-OPTIONS「表演补完」节有完整根因）。别名指向 mtn_idle01_C
    # （= 原型 stage.js L167 的 `playMotion(defaultMotion, {loop:true})` 常驻
    # 基底），17 个语义组原样不动、桥接表零影响。
    if "idle" in groups and "Idle" not in groups:
        refs["Motions"]["Idle"] = [
            {"File": "motions/mtn_idle01_C.motion3.json"}
        ]
    refs["Expressions"] = [{"Name": n, "File": f"expressions/{n}.exp3.json"} for n in exprs]
    doc = {
        "Version": 3,
        "Name": "sakiko (converted from Our Notes prefab)",
        "FileReferences": refs,
        "Groups": [
            {
                "Target": "Parameter",
                "Name": "EyeBlink",
                "Ids": [c.get("m_Name") or c.get("_id") or "" for c in eyeblink],
            },
            {
                "Target": "Parameter",
                "Name": "LipSync",
                "Ids": [c.get("m_Name") or c.get("_id") or "" for c in lipsync],
            },
        ],
        "HitAreas": [],
    }
    doc["Groups"] = [g for g in doc["Groups"] if any(g["Ids"])]
    (OUT / "sakiko.model3.json").write_text(
        json.dumps(doc, ensure_ascii=False, separators=(",", ":")), "utf-8"
    )
    return doc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--slope-scale", type=float, default=1 / 3,
                    help="Hermite 切线 → 贝塞尔控制点的缩放（默认 1/3）")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument(
        "--tex-scale", type=float, default=1.0,
        help="贴图上采样倍数（默认 1 = 原始 2048²）。2026-10-11 真机实测："
             "2× Lanczos 上采样只 +3%% 高频能量（插件 mipmap 链会把有效细节"
             "归一化），宿主主观验收为『更糊』、且 GPU 显存 4 倍 —— 故回到 1。"
             "将来若换 AI 放大（Real-ESRGAN 等真加细节）再开这个选项")
    args = ap.parse_args()

    manifest, nodes = load_prefab()
    motions, exprs, params, parts, drawables, phys, eyeblink, lipsync = collect(nodes)
    print(f"prefab: 节点 {len(nodes)} · 动作 {len(motions)} · 表情 {len(exprs)} · "
          f"参数 {len(params)} · 部件 {len(parts)} · drawable {len(drawables)} · "
          f"物理 {'有' if phys else '无'}")

    OUT.mkdir(parents=True, exist_ok=True)
    write_assets(manifest, args.tex_scale)
    mn = write_motions(motions, args.slope_scale, args.fps)
    en = write_expressions(exprs) + write_sys_expressions()
    # ⚠️ 下标纪律：`setExpression(index)` 的下标 = model3.json Expressions
    #    数组顺序，Dart 名表（live2d_stage.dart）必须与这里**同一排序**。
    en = sorted(en)
    has_phys = write_physics(phys)
    doc = write_model3(manifest, mn, en, has_phys, eyeblink, lipsync)

    print(f"输出 → {OUT}")
    print(f"  sakiko.moc3 · sakiko.model3.json · physics3={'有' if has_phys else '无'}")
    print(f"  motions {len(mn)} · expressions {len(en)}（含 4 个 exp_sys_* 合成）· textures 2")
    print(f"  model3 动作分组 {len(doc['FileReferences']['Motions'])} 个: "
          f"{list(doc['FileReferences']['Motions'])[:8]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
