#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  把 MuMu 实例的**物理面板分辨率**设成指定档位 —— 只改面板，不改逻辑尺寸。
#
#  为什么不用 `adb shell wm size`：
#    `wm size` 是**运行时覆盖**，会让 SurfaceFlinger 从「1:1 直通」变成
#    「先缩后放」，实测中频清晰度掉 45%。只有改**实例面板**才是零重采样。
#    （证据与量测见 docs/46-Live2D清晰度-DPR与mipmap.md）
#
#  用法：
#    bash tools/mumu/set-panel-resolution.sh        # 390x844dp @ DPR3（默认，推荐）
#    bash tools/mumu/set-panel-resolution.sh 2      # 390x844dp @ DPR2（旧档位）
#    bash tools/mumu/set-panel-resolution.sh --show # 只看当前状态
#
#  ⚠️ 会**关闭并重启**实例（MuMu 的分辨率设置只在关机态可写）。
# ═══════════════════════════════════════════════════════════
set -euo pipefail

MUMU="${MUMU_HOME:-E:/MuMu Player 12}/nx_main"
CLI="$MUMU/mumu-cli.exe"
ADB="$MUMU/adb.exe"
VMINDEX="${VMINDEX:-4}"
SERIAL="${SERIAL:-127.0.0.1:16512}"
PKG="com.systempanel.app"

# 逻辑尺寸固定 390x844 dp（与 iPhone 15 Pro 的 393x852 接近，布局不变）
LOGICAL_W=390
LOGICAL_H=844

show() {
  echo "── 实例面板（mumu-cli）──"
  "$CLI" setting -v "$VMINDEX" --all 2>/dev/null \
    | grep -E '"resolution_(width|height|dpi)"|"resolution_mode"' || true
  echo "── 运行时（adb）──"
  "$ADB" -s "$SERIAL" shell wm size    2>/dev/null || true
  "$ADB" -s "$SERIAL" shell wm density 2>/dev/null || true
  echo "── SurfaceFlinger 缩放（1:1 才算对）──"
  "$ADB" -s "$SERIAL" shell dumpsys SurfaceFlinger 2>/dev/null \
    | grep -oE 'displayFrame=\[[0-9 ]+\] sourceCrop=\[[0-9. ]+\]' \
    | grep -v '000000 000000 000000' | sort -u | head -3 || true
}

if [[ "${1:-}" == "--show" ]]; then show; exit 0; fi

DPR="${1:-3}"
W=$((LOGICAL_W * DPR))
H=$((LOGICAL_H * DPR))
# Android: dp = px / (dpi/160)  ⇒  要得到 DPR，必须 dpi = 160 × DPR
#   780x1688 @320dpi → 780/(320/160)=390dp ✓ (DPR2)
#   1170x2532 @480dpi → 1170/(480/160)=390dp ✓ (DPR3)
# ⚠️ 别写成固定 160dpi：那样 1170px 会被解释成 1170dp，布局全变。
DPI=$((160 * DPR))

echo "目标：${LOGICAL_W}x${LOGICAL_H}dp × DPR${DPR} = ${W}x${H} @ ${DPI}dpi"

# 1) 必须关机态写设置
echo "→ 关闭实例 $VMINDEX"
"$CLI" control -v "$VMINDEX" shutdown >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  started=$("$CLI" info -v "$VMINDEX" 2>/dev/null | grep -o '"is_process_started": *[a-z]*' | grep -o '[a-z]*$' || echo false)
  [[ "$started" == "false" ]] && break
  sleep 2
done

# 2) 切 custom 再写 .custom 后缀键
#    ⚠️ 顺序陷阱：切成 custom 会把三个值清零；且普通键报 key not writable，
#       必须写 resolution_*.custom（见 docs/46 §2）
echo "→ 写面板分辨率"
"$CLI" setting -v "$VMINDEX" --key resolution_mode          --value custom >/dev/null
"$CLI" setting -v "$VMINDEX" --key resolution_width.custom  --value "$W"    >/dev/null
"$CLI" setting -v "$VMINDEX" --key resolution_height.custom --value "$H"    >/dev/null
"$CLI" setting -v "$VMINDEX" --key resolution_dpi.custom    --value "$DPI"  >/dev/null

# 3) 启动并等就绪
echo "→ 启动实例 $VMINDEX"
"$CLI" control -v "$VMINDEX" launch >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  state=$("$CLI" info -v "$VMINDEX" 2>/dev/null | grep -o '"player_state": *"[^"]*"' | cut -d'"' -f4 || echo "")
  [[ "$state" == "start_finished" ]] && break
  sleep 2
done

# 4) 关键：清掉运行时覆盖，让 SurfaceFlinger 回到 1:1
#    ⚠️ 实例刚起来时 adb 常报 device offline —— 必须重连+轮询，
#       否则 set -e 会在这里直接中断（实测第一版就这么挂的）。
echo "→ 等待 adb 就绪"
"$ADB" connect "$SERIAL" >/dev/null 2>&1 || true
for _ in $(seq 1 40); do
  if "$ADB" -s "$SERIAL" shell true >/dev/null 2>&1; then break; fi
  "$ADB" connect "$SERIAL" >/dev/null 2>&1 || true
  sleep 2
done
echo "→ 清除 wm 覆盖（必须！否则会缩放）"
if ! "$ADB" -s "$SERIAL" shell wm size reset >/dev/null 2>&1; then
  echo "   ⚠️ wm size reset 失败（已有覆盖仍在，需手工补一刀）："
  echo "      \"$ADB\" -s $SERIAL shell wm size reset && \"$ADB\" -s $SERIAL shell wm density reset"
fi
"$ADB" -s "$SERIAL" shell wm density reset >/dev/null 2>&1 || true

# 5) 拉起 App
echo "→ 重启 App"
"$ADB" -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" -s "$SERIAL" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1 || true
sleep 8

echo
show
echo
echo "✅ 完成。验收看两处：sourceCrop 与 displayFrame 尺寸**相同**；wm size 无 Override 行。"
